import 'package:conatus_agent/conatus_agent.dart';
import 'package:test/test.dart';

void main() {
  group('TokenUsage.parse', () {
    test('Chat Completions 键名与缓存明细都归一', () {
      final TokenUsage usage = TokenUsage.parse(<String, dynamic>{
        'prompt_tokens': 1000,
        'prompt_tokens_details': <String, dynamic>{'cached_tokens': 400},
        'completion_tokens': 50,
      });

      expect(usage.prompt, 1000);
      expect(usage.cachedPrompt, 400);
      expect(usage.completion, 50);
      expect(usage.known, isTrue);
    });

    test('Responses 键名与缓存明细都归一', () {
      final TokenUsage usage = TokenUsage.parse(<String, dynamic>{
        'input_tokens': 1000,
        'input_tokens_details': <String, dynamic>{'cached_tokens': 400},
        'output_tokens': 50,
      });

      expect(usage.prompt, 1000);
      expect(usage.cachedPrompt, 400);
      expect(usage.completion, 50);
    });

    test('空用量未知', () {
      expect(TokenUsage.parse(const <String, dynamic>{}).known, isFalse);
      expect(const TokenUsage().known, isFalse);
    });

    test('嵌套表类型不符时按 0 计', () {
      final TokenUsage usage = TokenUsage.parse(<String, dynamic>{
        'prompt_tokens': 10,
        'prompt_tokens_details': 'oops',
      });

      expect(usage.prompt, 10);
      expect(usage.cachedPrompt, 0);
    });
  });

  test('缓存数超过输入数时未缓存部分夹到 0', () {
    const TokenUsage usage = TokenUsage(prompt: 100, cachedPrompt: 150);

    expect(usage.freshPrompt, 0);
  });

  test('TokenUsage 相加累加三个维度', () {
    const TokenUsage a = TokenUsage(prompt: 10, cachedPrompt: 4, completion: 2);
    const TokenUsage b = TokenUsage(prompt: 5, cachedPrompt: 1, completion: 3);

    final TokenUsage sum = a + b;

    expect(sum.prompt, 15);
    expect(sum.cachedPrompt, 5);
    expect(sum.completion, 5);
  });

  group('ModelRate.costOf', () {
    test('未缓存、缓存、输出三段分价', () {
      const ModelRate rate = ModelRate(
        inputPerMillion: 5,
        cachedPerMillion: 0.5,
        outputPerMillion: 30,
      );
      const TokenUsage usage =
          TokenUsage(prompt: 1000000, cachedPrompt: 200000, completion: 100000);

      expect(
        rate.costOf(usage),
        closeTo(
            800000 / 1e6 * 5 + 200000 / 1e6 * 0.5 + 100000 / 1e6 * 30, 1e-9),
      );
    });

    test('零用量成本为零', () {
      const ModelRate rate = ModelRate(
        inputPerMillion: 5,
        cachedPerMillion: 0.5,
        outputPerMillion: 30,
      );

      expect(rate.costOf(const TokenUsage()), 0);
    });
  });

  group('CostAccumulator', () {
    test('按费率累计成本与 token', () {
      final CostAccumulator meter = CostAccumulator(
        rate: const ModelRate(
          inputPerMillion: 2,
          cachedPerMillion: 1,
          outputPerMillion: 4,
        ),
      );

      meter.add(<String, dynamic>{'prompt_tokens': 1000000});
      meter.add(<String, dynamic>{'prompt_tokens': 500000});

      expect(meter.calls, 2);
      expect(meter.tokens.prompt, 1500000);
      expect(meter.cost, closeTo(3, 1e-9));
      expect(meter.unknownRateCalls, 0);
    });

    test('费率缺失时成本为 null 且单独计数', () {
      final CostAccumulator meter = CostAccumulator();

      meter.add(<String, dynamic>{'prompt_tokens': 10, 'completion_tokens': 1});

      expect(meter.calls, 1);
      expect(meter.cost, isNull);
      expect(meter.unknownRateCalls, 1);
    });

    test('用量未知的调用不计数', () {
      final CostAccumulator meter = CostAccumulator();

      meter.add(const <String, dynamic>{});

      expect(meter.calls, 0);
      expect(meter.tokens.known, isFalse);
    });

    test('没有调用时成本为 null', () {
      final CostAccumulator meter = CostAccumulator(
        rate: const ModelRate(
          inputPerMillion: 1,
          cachedPerMillion: 1,
          outputPerMillion: 1,
        ),
      );

      expect(meter.cost, isNull);
    });

    test('Cost-of-Pass 在零成功时为 null', () {
      final CostAccumulator meter = CostAccumulator(
        rate: const ModelRate(
          inputPerMillion: 1,
          cachedPerMillion: 1,
          outputPerMillion: 1,
        ),
      );
      meter.add(<String, dynamic>{'prompt_tokens': 1000000});

      expect(meter.costOfPass(0), isNull);
      expect(meter.costOfPass(2), closeTo(0.5, 1e-9));
    });

    test('费率缺失时 Cost-of-Pass 为 null', () {
      final CostAccumulator meter = CostAccumulator();
      meter.add(<String, dynamic>{'prompt_tokens': 1000000});

      expect(meter.costOfPass(1), isNull);
    });
  });
}
