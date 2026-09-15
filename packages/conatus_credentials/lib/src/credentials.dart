/// 凭据能力缝：`ctx.credentials` 服务、统一契约与可复用的内存快照。
///
/// 读取是**同步**的（[Credentials.get] / [Credentials.require] /
/// [Credentials.validate]），读的是内存快照；远端来源用 [Credentials.refresh]
/// 把值拉进快照，或用 [Credentials.changes] 推送轮换。这样 LLM Provider 之类
/// 需要在构造函数里同步解析 Key 的调用方不必改成异步形状。
library;

import 'dart:async';
import 'package:conatus_core/conatus_core.dart';
import 'credentials_env.dart';
import 'credentials_types.dart';

export 'credentials_types.dart';

/// 凭据内存快照 + 变更广播，供各来源复用。
///
/// 快照把「值从哪来」（env / 文件 / Vault / AWS）与「值怎么被消费」解耦：
/// 来源负责写入，消费方只读 [get] 并订阅 [changes]。
class CredentialSnapshot {
  final Map<String, Credential> _values = <String, Credential>{};
  final StreamController<Credential> _controller =
      StreamController<Credential>.broadcast();
  bool _closed = false;

  /// 快照中的键（不可变副本）。
  List<String> get keys => List<String>.unmodifiable(_values.keys);

  /// 变更流：写入与快照替换时推送被更新的凭据。
  Stream<Credential> get changes => _controller.stream;

  /// 快照是否已关闭。
  bool get closed => _closed;

  /// 按键取值；不存在或**已过期**时返回 `null`（过期即视为没有）。
  Credential? get(String key) {
    final Credential? credential = _values[key];
    if (credential == null || credential.expired) return null;
    return credential;
  }

  /// 写入一条凭据并推送 [changes]；已关闭时忽略。
  void update(Credential credential) {
    if (_closed) return;
    _values[credential.key] = credential;
    _controller.add(credential);
  }

  /// 整体替换快照，并逐一推送新增或发生变化的凭据。
  ///
  /// 移除无法用 [Credential] 表达，因此只推送留存项；调用方按键订阅即可。
  void refreshSnapshot(Map<String, Credential> values) {
    if (_closed) return;
    final List<Credential> changed = <Credential>[
      for (final MapEntry<String, Credential> entry in values.entries)
        if (_changed(entry.key, entry.value)) entry.value,
    ];
    _values
      ..clear()
      ..addAll(values);
    for (final Credential credential in changed) {
      _controller.add(credential);
    }
  }

  bool _changed(String key, Credential next) {
    final Credential? previous = _values[key];
    return previous == null ||
        previous.value != next.value ||
        previous.expiresAt != next.expiresAt;
  }

  /// 关闭快照并结束 [changes]。幂等；关闭后写入被忽略。
  void close() {
    if (_closed) return;
    _closed = true;
    unawaited(_controller.close());
  }
}

/// 凭据契约：同步读内存快照，异步刷新。
///
/// 只读来源（env / file / vault / aws）的 [update] 抛
/// [CredentialsException]（`read-only`）；可写来源（memory）立即生效并推送。
abstract class Credentials {
  /// 按键取值；找不到或已过期返回 `null`。
  Credential? get(String key);

  /// 按键取值；找不到或已过期抛 [CredentialsException]（`missing`）。
  Credential require(String key) {
    final Credential? credential = get(key);
    if (credential == null) {
      throw CredentialsException('missing', '缺少凭据 "$key"。');
    }
    return credential;
  }

  /// 校验若干键是否齐备：任一缺失即快速失败，消息列出**全部**缺失键。
  void validate(List<String> requiredKeys) {
    final List<String> missing = <String>[
      for (final String key in requiredKeys)
        if (get(key) == null) key,
    ];
    if (missing.isEmpty) return;
    throw CredentialsException('missing', '缺少凭据：${missing.join(', ')}');
  }

  /// 写入一条凭据；只读来源抛 [CredentialsException]（`read-only`）。
  Future<void> update(String key, String value);

  /// 变更流：更新或刷新后推送。
  Stream<Credential> get changes;

  /// 当前快照中的键。
  List<String> get keys;

  /// 从底层来源重新拉取快照。默认无操作。
  Future<void> refresh() async {}

  /// 释放来源：取消订阅与定时器。幂等。
  void close();
}

/// `ctx.credentials`：当前上下文可见的凭据服务。
extension CredentialsContext on Context {
  /// 取当前上下文可见的 [Credentials]（未提供时抛 [StateError]）。
  Credentials get credentials => require<Credentials>('credentials');
}

/// 将 [Credentials] 作为 `'credentials'` 服务提供到上下文。
///
/// [credentials] 缺省为 [EnvCredentials]（读 `Platform.environment`）。
/// 服务随上下文释放而 [Credentials.close]；同一上下文重复提供抛 [StateError]。
Credentials provideCredentials(Context ctx, {Credentials? credentials}) {
  final Credentials resolved = credentials ?? EnvCredentials();
  ctx.provide('credentials', resolved);
  ctx.onDispose(resolved.close);
  return resolved;
}
