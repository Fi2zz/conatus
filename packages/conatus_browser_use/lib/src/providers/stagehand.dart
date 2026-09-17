/// Stagehand Provider（AI 辅助浏览器操作）——骨架实现。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import '../provider.dart';
import '../session_browser.dart';

/// 通过 Stagehand SDK 的原生浏览器 Provider。
///
/// **骨架实现**：Stagehand 的 AI 辅助动作、观测与提取需要外部 Stagehand SDK
/// 及其**显式配置的原生模型**（conatus 的 `llm` 不参与其推理）。本包不携带
/// 该 SDK，因此 [initializeFor] 抛 [UnsupportedError]。接入方式：
///
/// ```dart
/// provideBrowserUse(app, provider: StagehandProvider(
///   apiKey: credentials.require('STAGEHAND_API_KEY').value,
/// ));
/// ```
///
/// 暂缓工作：DSH 模型路由、凭据复用、底层推理请求/响应捕获，以及与 Session
/// 用量计量的集成。返回的 SDK 数据与元数据仍作为普通工具结果记录。
class StagehandProvider implements BrowserUseProvider {
  /// 构造。
  StagehandProvider({
    required this.apiKey,
    this.model = 'gpt-4o',
    this.config = const BrowserConfig(),
  });

  /// Stagehand 原生模型的 API Key。
  final String apiKey;

  /// Stagehand 使用的原生模型名。
  final String model;

  /// 浏览器配置。
  final BrowserConfig config;

  @override
  String get name => 'stagehand';

  @override
  Future<SessionBrowser> initializeFor(Session session) {
    throw UnsupportedError(
      'Stagehand 需要外部 Stagehand SDK 与原生模型推理，'
      'conatus_browser_use 暂未接入。',
    );
  }

  @override
  Future<void> release(Session session) async {}

  @override
  Future<void> dispose() async {}
}
