/// 失败分类与重试策略。
///
/// 分成两半：
///
/// * [LlmErrorKind] —— **该不该**重试（重试同一提供商解决不了的问题不该浪费
///   时间：缺 Key、401、参数非法）；
/// * [RetryPolicy] / [RetryingLlm] —— 隔多久重试、重试几次。
///
/// 回退（换提供商）是另一个维度，见 `llm_fallback.dart`。典型装配是每个候选
/// 各包一层 [RetryingLlm]，再由 `FallbackLlm` 串联：先在原提供商上退避重试，
/// 仍失败才换下一个。
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'llm.dart';

/// 调用失败的类别；[isRetryable] 决定重试是否有意义。
///
/// 只管重试，不管回退：401 在重试维度是死路，但在回退维度完全该走（换一个
/// 有 Key 的提供商）。
enum LlmErrorKind {
  /// 配置问题：缺 API Key、端点不合法。重试无意义。
  config,

  /// 认证 / 授权失败（401 / 403）。重试无意义。
  auth,

  /// 限流（429、529）。**该**退避重试。
  rateLimit,

  /// 服务端错误（5xx）。该重试。
  server,

  /// 传输层失败：超时、连接被拒、连接中断。该重试。
  network,

  /// 请求本身被拒（4px 其余：400 / 404 / 413 …）。重试只会再被拒一次。
  badRequest;

  /// 由 HTTP 状态码推断类别；`null`（无状态码）按 [network] 处理。
  static LlmErrorKind infer(int? statusCode) {
    if (statusCode == null) return LlmErrorKind.network;
    return switch (statusCode) {
      401 || 403 => LlmErrorKind.auth,
      429 || 529 => LlmErrorKind.rateLimit,
      _ when statusCode >= 500 => LlmErrorKind.server,
      _ => LlmErrorKind.badRequest,
    };
  }

  /// 重试是否可能得到不同结果。
  bool get isRetryable =>
      this == LlmErrorKind.rateLimit ||
      this == LlmErrorKind.server ||
      this == LlmErrorKind.network;

  /// 面向用户的中文原因短语。
  String get label => switch (this) {
        LlmErrorKind.config => '配置不完整',
        LlmErrorKind.auth => '认证失败',
        LlmErrorKind.rateLimit => '触发限流',
        LlmErrorKind.server => '服务端错误',
        LlmErrorKind.network => '网络异常',
        LlmErrorKind.badRequest => '请求被拒',
      };
}

/// 该错误是否值得重试。
///
/// [LlmException] 按自身类别判定（wire 层已在抛出时标注）；传输层异常
/// （超时 / 连接错误）一律算可重试；其余类型（断言失败、参数类型错误……）
/// 视为编程错误，重试只会重复失败。
bool isRetryableError(Object error) => switch (error) {
      final LlmException e => e.isRetryable,
      TimeoutException() => true,
      SocketException() => true,
      HandshakeException() => true,
      _ => false,
    };

/// 取出服务端给的 `Retry-After`（已解析成时长）；没有则 `null`。
Duration? retryAfterOf(Object error) =>
    error is LlmException ? error.retryAfter : null;

/// 重试策略：次数、间隔上限与抖动。
class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 4,
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 30),
    this.jitter = 0.25,
  });

  /// 只试一次（等价于关闭重试）。
  static const RetryPolicy none = RetryPolicy(maxAttempts: 1);

  /// 总尝试次数（**含**首次请求），因此 `1` 表示不重试。
  final int maxAttempts;

  /// 首次退避时长；此后按 2 的幂翻倍。
  final Duration baseDelay;

  /// 单次退避的硬上限。
  final Duration maxDelay;

  /// 抖动比例（`0.25` = ±25%）。
  ///
  /// 并发客户端不加抖动会踩同一个节奏重试，形成惊群；服务端给了
  /// `Retry-After` 时按服务端说的等，不再叠加抖动。
  final double jitter;

  /// 第 [attempt] 次尝试失败后（1 起）到下一次之间的等待时长。
  Duration delayFor(int attempt, {Duration? retryAfter, Random? random}) {
    if (retryAfter != null && retryAfter > Duration.zero) {
      return _cap(retryAfter);
    }
    final int shift = attempt < 1 ? 0 : attempt - 1;
    final int scaled = baseDelay.inMilliseconds * (1 << shift);
    return _cap(_jitter(Duration(milliseconds: scaled), random));
  }

  Duration _jitter(Duration delay, Random? random) {
    if (jitter <= 0) return _cap(delay);
    final double factor =
        1 - jitter + 2 * jitter * (random?.nextDouble() ?? _pseudoRandom());
    return _cap(Duration(milliseconds: (delay.inMilliseconds * factor).round()));
  }

  /// 无 [Random] 注入时的确定性抖动源（0.5 = 不偏移），保证默认行为可预期。
  static double _pseudoRandom() => 0.5;

  Duration _cap(Duration delay) =>
      delay > maxDelay ? maxDelay : (delay.isNegative ? Duration.zero : delay);
}

/// 一次重试的通知；宿主用它把「限流，2s 后重试」呈给用户。
class LlmRetryAttempt {
  const LlmRetryAttempt({
    required this.provider,
    required this.attempt,
    required this.maxAttempts,
    required this.delay,
    required this.error,
  });

  /// 提供商名。
  final String provider;

  /// 即将进行的第几次尝试（1 起）。
  final int attempt;

  /// 总尝试次数。
  final int maxAttempts;

  /// 这次等待了多久。
  final Duration delay;

  /// 引起重试的原始错误。
  final Object error;

  /// 服务端要求优先时为真（本次等待照服务端说的，未叠加抖动）。
  bool get honoredRetryAfter => retryAfterOf(error) != null;

  /// 一行中文摘要，供屏上直接显示。
  String get summary {
    final Object error = this.error;
    final String reason = error is LlmException
        ? error.errorKind.label
        : LlmErrorKind.network.label;
    return '$provider $reason，${_seconds(delay)}s 后重试'
        '（$attempt/$maxAttempts）';
  }

  static String _seconds(Duration duration) =>
      (duration.inMilliseconds / 1000).toStringAsFixed(1);
}

/// 睡眠函数；测试注入立即返回的实现即可断言退避序列而不真的等。
typedef LlmSleeper = Future<void> Function(Duration duration);

/// 重试装饰器：把 [inner] 的可重试失败按 [policy] 退避重试。
///
/// **流式只在尚未产出任何事件时重试**——已经 yield 出去的增量收不回来，
/// 静默重来只会让用户看到重复内容（与 `FallbackLlm` 的回退约束同源）。
class RetryingLlm implements LlmProvider {
  RetryingLlm(
    this.inner, {
    this.policy = const RetryPolicy(),
    LlmSleeper? sleep,
    Random? random,
    LlmRetryReporter? onRetry,
  })  : _sleep = sleep ?? _defaultSleep,
        _random = random,
        _onRetry = onRetry;

  /// 被包装的提供商。
  final LlmProvider inner;

  /// 重试策略。
  final RetryPolicy policy;

  final LlmSleeper _sleep;
  final Random? _random;
  final LlmRetryReporter? _onRetry;

  @override
  String get name => inner.name;

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      _retrying(() => inner.chat(messages, options: options, tools: tools));

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      _retryingStream(
        () => inner.chatStream(messages, options: options, tools: tools),
      );

  Future<LlmResult> _retrying(Future<LlmResult> Function() attempt) async {
    for (int i = 1; ; i++) {
      try {
        return await attempt();
      } catch (error) {
        if (!_worthAnother(i, error)) rethrow;
        await _waitBefore(i, error);
      }
    }
  }

  Stream<LlmStreamEvent> _retryingStream(
    Stream<LlmStreamEvent> Function() attempt,
  ) async* {
    for (int i = 1; ; i++) {
      bool emitted = false;
      try {
        await for (final LlmStreamEvent event in attempt()) {
          emitted = true;
          yield event;
        }
        return;
      } catch (error) {
        if (emitted || !_worthAnother(i, error)) rethrow;
        await _waitBefore(i, error);
      }
    }
  }

  /// 还有次数、且这个错误重试有意义吗。
  bool _worthAnother(int attempt, Object error) =>
      attempt < policy.maxAttempts && isRetryableError(error);

  Future<void> _waitBefore(int attempt, Object error) async {
    final Duration delay = policy.delayFor(
      attempt,
      retryAfter: retryAfterOf(error),
      random: _random,
    );
    _onRetry?.call(LlmRetryAttempt(
      provider: inner.name,
      attempt: attempt + 1,
      maxAttempts: policy.maxAttempts,
      delay: delay,
      error: error,
    ));
    await _sleep(delay);
  }

  static Future<void> _defaultSleep(Duration duration) =>
      Future<void>.delayed(duration);

  @override
  void close() => inner.close();
}

/// 重试通知回调。
typedef LlmRetryReporter = void Function(LlmRetryAttempt attempt);
