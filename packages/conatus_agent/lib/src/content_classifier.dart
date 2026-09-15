/// content-classifier 插件：给模型消息分类，并为每类内容指定压缩策略。
///
/// 服务键 `'contentClassifier'`（`ctx.contentClassifier`）。分类是上下文工程的
/// 第一层：先弄清「这条消息是什么」，分层压缩才能决定谁原文保留、谁折叠进摘要、
/// 谁被压成摘要 + 指针。默认实现 [RuleBasedContentClassifier] 是纯规则、可解释的；
/// 需要更强信号（例如让模型判任务与偏好）时实现 [ContentClassifier] 替换即可。
///
/// 边界：`classify` 只看单条消息本身（role / content / toolCalls），**不看位置**。
/// 「早期还是近期」由调用方（分层压缩器）遍历时按
/// [ContentClassifier.recentWindow] 决定，因此分类器不持有索引状态：同一批消息
/// 在任何遍历顺序下结论一致。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_llm/conatus_llm.dart';

/// 模型消息的内容类别。
enum MessageCategory {
  /// system 中的人设与指令部分（稳定前缀）。
  systemPrompt,

  /// system 中的工具说明部分（稳定前缀）。
  toolDefinition,

  /// system 中的技能清单部分（稳定前缀）。
  skillList,

  /// 工具结果：可由日志或工具重放重建，压成摘要 + 指针。
  toolResult,

  /// 用户偏好表达：跨轮生效，原文保留。
  userPreference,

  /// 用户任务描述：当前目标，原文保留。
  userTask,

  /// 早期对话：折叠进滚动摘要。
  earlyConversation,

  /// 近期对话：留给滑动窗口。
  recentConversation,
}

/// 类别对应的压缩策略。
enum CompressionStrategy {
  /// 原样保留（稳定前缀，任何压缩都是纯损失）。
  none,

  /// 原文保留（不折叠进摘要）。
  keep,

  /// 折叠为自然语言摘要。
  summarize,

  /// 压成摘要 + 指针，正文丢弃。
  evict,
}

/// 内容分类器能力（Capability Seam）。
abstract class ContentClassifier {
  /// 判断单条消息的类别。
  ///
  /// 只依据消息自身的字段；位置相关的早期/近期区分由调用方遍历时决定。
  MessageCategory classify(LlmMessage message);

  /// 类别对应的压缩策略。
  CompressionStrategy strategyFor(MessageCategory category);

  /// 对话消息的近期窗口（条数）：距末尾不超过该条数的对话算「近期」。
  ///
  /// 分类器无法从单条消息判断位置，因此位置划分由调用方按这个窗口执行。
  int get recentWindow;
}

/// 规则驱动的分类器：角色 + 关键词 + 位置窗口，全部可解释。
///
/// 判定规则：
///
/// * `role == 'tool'` → [MessageCategory.toolResult]；
/// * `role == 'system'` → 含技能关键词为 [MessageCategory.skillList]，含工具
///   关键词为 [MessageCategory.toolDefinition]，否则
///   [MessageCategory.systemPrompt]；
/// * 带 `toolCalls` 的 assistant → [MessageCategory.recentConversation]：它是
///   工具调用轨迹的一部分，位置与内容都随轮次变化，压掉会切断调用配对；
/// * 其余 user / assistant → 命中偏好关键词为 [MessageCategory.userPreference]，
///   否则 [MessageCategory.recentConversation]。
///
/// [MessageCategory.userTask] 与位置类别的区分需要比关键词更强的信号，
/// 规则分类器不产出它们，交由分层压缩器按 [recentWindow] 处理。
class RuleBasedContentClassifier implements ContentClassifier {
  /// [recentWindow] 是对话消息的近期窗口（条数），缺省 20。
  RuleBasedContentClassifier({this.recentWindow = 20});

  @override
  final int recentWindow;

  @override
  MessageCategory classify(LlmMessage message) {
    final MessageCategory? structural = _structural(message);
    if (structural != null) return structural;
    if (_preferenceKeywords.hasMatch(message.content)) {
      return MessageCategory.userPreference;
    }
    return MessageCategory.recentConversation;
  }

  @override
  CompressionStrategy strategyFor(MessageCategory category) =>
      _strategies[category]!;

  MessageCategory? _structural(LlmMessage message) {
    if (message.role == 'tool') return MessageCategory.toolResult;
    if (message.role == 'system') return _systemCategory(message.content);
    if (message.toolCalls.isNotEmpty) {
      return MessageCategory.recentConversation;
    }
    return null;
  }

  MessageCategory _systemCategory(String content) {
    if (_skillKeywords.hasMatch(content)) return MessageCategory.skillList;
    if (_toolKeywords.hasMatch(content)) return MessageCategory.toolDefinition;
    return MessageCategory.systemPrompt;
  }

  static const Map<MessageCategory, CompressionStrategy> _strategies =
      <MessageCategory, CompressionStrategy>{
    MessageCategory.systemPrompt: CompressionStrategy.none,
    MessageCategory.toolDefinition: CompressionStrategy.none,
    MessageCategory.skillList: CompressionStrategy.none,
    MessageCategory.toolResult: CompressionStrategy.evict,
    MessageCategory.userPreference: CompressionStrategy.keep,
    MessageCategory.userTask: CompressionStrategy.keep,
    MessageCategory.earlyConversation: CompressionStrategy.summarize,
    MessageCategory.recentConversation: CompressionStrategy.keep,
  };

  static final RegExp _preferenceKeywords =
      RegExp('记住|以后都|今后|我喜欢|我不喜欢|不要|务必|始终|偏好', caseSensitive: false);
  static final RegExp _skillKeywords = RegExp('技能|skill', caseSensitive: false);
  static final RegExp _toolKeywords = RegExp('工具|tool', caseSensitive: false);
}

/// `ctx.contentClassifier`：当前上下文可见的内容分类器。
extension ContentClassifierContext on Context {
  /// 取当前上下文可见的 [ContentClassifier]（未提供时抛 [StateError]）。
  ContentClassifier get contentClassifier =>
      require<ContentClassifier>('contentClassifier');
}

/// 把 [ContentClassifier] 作为 `'contentClassifier'` 服务提供到上下文。
///
/// 未显式传入 [classifier] 时使用 [RuleBasedContentClassifier]。
ContentClassifier provideContentClassifier(
  Context ctx, {
  ContentClassifier? classifier,
}) {
  final ContentClassifier resolved = classifier ?? RuleBasedContentClassifier();
  ctx.provide('contentClassifier', resolved);
  return resolved;
}
