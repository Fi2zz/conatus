/// ask_user 插件：在上下文中声明式地向用户提问。
///
/// 设计目标：
///
/// * 通过 [AskUser] 接口抽象提问方式，CLI 只是默认实现；
/// * 提问本身是一个**可逆效应**——若上下文在等待用户输入期间被释放，
///   正在进行的提问会被取消；
/// * 多轮对话可以复用同一个 [AskUser] 实例。
library;

import 'dart:async';
import 'dart:io';
import 'package:conatus_core/conatus_core.dart';

/// 提问器接口。实现者负责从某个来源获取用户输入。
abstract class AskUser {
  /// 向用户展示 [prompt]，返回其输入。
  ///
  /// 若在等待期间调用 [cancel]，应抛出 [AskCancelledException]。
  Future<String> ask(String prompt);

  /// 取消所有正在进行的提问。幂等。
  void cancel();
}

/// 提问被取消时抛出。
class AskCancelledException implements Exception {
  const AskCancelledException([this.message = '提问已取消']);

  final String message;

  @override
  String toString() => 'AskCancelledException: $message';
}

/// 基于标准输入输出的默认提问器。
class CliAskUser implements AskUser {
  CliAskUser({IOSink? sink}) : _sink = sink ?? stdout;

  final IOSink _sink;
  final List<Completer<String>> _pending = <Completer<String>>[];
  bool _cancelled = false;

  @override
  Future<String> ask(String prompt) {
    if (_cancelled) {
      throw const AskCancelledException();
    }
    _sink.writeln(prompt);
    final Completer<String> completer = Completer<String>();
    _pending.add(completer);
    return completer.future;
  }

  /// 将一行输入投递给最早等待中的提问。
  ///
  /// 供测试或自定义输入源（如 GUI 事件循环）调用。
  void submit(String line) {
    if (_pending.isEmpty) return;
    final Completer<String> completer = _pending.removeAt(0);
    if (!completer.isCompleted) {
      completer.complete(line);
    }
  }

  @override
  void cancel() {
    _cancelled = true;
    for (final Completer<String> c in _pending) {
      if (!c.isCompleted) c.completeError(const AskCancelledException());
    }
    _pending.clear();
  }
}

/// 将 [AskUser] 作为服务提供到上下文中。
///
/// ```dart
/// app.plugin('ask-user', (ctx) => provideAskUser(ctx));
///
/// app.plugin('chat', (ctx) {
///   ctx.inject(['askUser'], (child) {
///     final ask = child.require<AskUser>('askUser');
///     ask.ask('你的名字是？').then(print);
///   });
/// });
/// ```
Disposer provideAskUser(Context ctx, {AskUser? askUser}) {
  final AskUser instance = askUser ?? CliAskUser();
  final Disposer disposer = ctx.provide('askUser', instance);
  ctx.onDispose(instance.cancel);
  return disposer;
}
