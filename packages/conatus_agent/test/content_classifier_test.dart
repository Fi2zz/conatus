import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _FixedClassifier implements ContentClassifier {
  @override
  int get recentWindow => 1;

  @override
  MessageCategory classify(LlmMessage message) => MessageCategory.userTask;

  @override
  CompressionStrategy strategyFor(MessageCategory category) =>
      CompressionStrategy.keep;
}

void main() {
  final ContentClassifier classifier = RuleBasedContentClassifier();

  group('RuleBasedContentClassifier.classify', () {
    test('system 消息按关键词细分', () {
      expect(classifier.classify(const LlmMessage('system', '你是一个可靠的助手。')),
          MessageCategory.systemPrompt);
      expect(
          classifier.classify(
              const LlmMessage('system', '可用工具：read_file、write_file')),
          MessageCategory.toolDefinition);
      expect(classifier.classify(const LlmMessage('system', '已启用技能：查天气')),
          MessageCategory.skillList);
    });

    test('tool 消息为工具结果', () {
      expect(
          classifier
              .classify(const LlmMessage('tool', '12:00', toolCallId: 'c1')),
          MessageCategory.toolResult);
    });

    test('带 toolCalls 的 assistant 归入近期对话', () {
      const LlmMessage message =
          LlmMessage('assistant', '', toolCalls: <LlmToolCall>[
        LlmToolCall(id: 'c1', name: 'get_time'),
      ]);

      expect(message.toolCalls, isNotEmpty);
      expect(classifier.classify(message), MessageCategory.recentConversation);
    });

    test('偏好关键词的 user 消息为偏好表达', () {
      expect(classifier.classify(const LlmMessage('user', '记住：以后都用中文回答')),
          MessageCategory.userPreference);
      expect(classifier.classify(const LlmMessage('user', '今天几点')),
          MessageCategory.recentConversation);
    });

    test('位置类别不由 classify 决定：同一条消息结论恒等', () {
      const LlmMessage message = LlmMessage('user', '帮我看看这个文件');

      expect(classifier.classify(message), MessageCategory.recentConversation);
      expect(classifier.classify(message), classifier.classify(message));
      expect(classifier.recentWindow, 20);
    });
  });

  test('策略表覆盖全部类别', () {
    const Map<MessageCategory, CompressionStrategy> expected =
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

    for (final MapEntry<MessageCategory, CompressionStrategy> entry
        in expected.entries) {
      expect(classifier.strategyFor(entry.key), entry.value);
    }
  });

  group('provideContentClassifier', () {
    test('缺省提供规则分类器', () {
      final Context ctx = Context.root();

      final ContentClassifier provided = provideContentClassifier(ctx);

      expect(provided, isA<RuleBasedContentClassifier>());
      expect(identical(ctx.contentClassifier, provided), isTrue);
      ctx.dispose();
    });

    test('可注入自定义分类器', () {
      final Context ctx = Context.root();
      final ContentClassifier custom = _FixedClassifier();

      expect(
          identical(provideContentClassifier(ctx, classifier: custom), custom),
          isTrue);
      expect(identical(ctx.contentClassifier, custom), isTrue);
      ctx.dispose();
    });

    test('未提供时 ctx.contentClassifier 抛 StateError', () {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);

      expect(() => ctx.contentClassifier, throwsStateError);
    });
  });
}
