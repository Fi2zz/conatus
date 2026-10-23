import 'package:conatus_agent/conatus_agent.dart';
import 'package:test/test.dart';

SelectionCandidate _c(String id, double passRate, double meanCost) =>
    SelectionCandidate(id: id, passRate: passRate, meanCost: meanCost);

void main() {
  group('paretoFrontier', () {
    test('空集合返回空', () {
      expect(paretoFrontier(const <SelectionCandidate>[]), isEmpty);
    });

    test('单元素返回自身', () {
      final SelectionCandidate only = _c('only', 0.5, 1);

      expect(paretoFrontier(<SelectionCandidate>[only]),
          <SelectionCandidate>[only]);
    });

    test('被支配者被剔除，更高分更高价者保留', () {
      final SelectionCandidate cheap = _c('cheap', 0.80, 1);
      final SelectionCandidate dominated = _c('dominated', 0.70, 2);
      final SelectionCandidate strong = _c('strong', 0.95, 3);

      final List<SelectionCandidate> frontier =
          paretoFrontier(<SelectionCandidate>[cheap, dominated, strong]);

      expect(frontier, <SelectionCandidate>[cheap, strong]);
    });

    test('两项相同不互相支配，都保留', () {
      final SelectionCandidate a = _c('a', 0.8, 1);
      final SelectionCandidate b = _c('b', 0.8, 1);

      expect(paretoFrontier(<SelectionCandidate>[a, b]), hasLength(2));
    });

    test('同分低价支配同分高价', () {
      final SelectionCandidate cheaper = _c('cheaper', 0.8, 1);
      final SelectionCandidate pricier = _c('pricier', 0.8, 2);

      expect(
        paretoFrontier(<SelectionCandidate>[cheaper, pricier]),
        <SelectionCandidate>[cheaper],
      );
    });

    test('同价高分支配同价低分', () {
      final SelectionCandidate higher = _c('higher', 0.9, 1);
      final SelectionCandidate lower = _c('lower', 0.6, 1);

      expect(
        paretoFrontier(<SelectionCandidate>[higher, lower]),
        <SelectionCandidate>[higher],
      );
    });
  });

  group('selectRepresentative', () {
    // 前沿三点：高分高价 / 低分低价 / 中间点。
    final SelectionCandidate balanced = _c('balanced', 0.90, 1.0);
    final SelectionCandidate cheapest = _c('cheapest', 0.80, 0.5);
    final SelectionCandidate strongest = _c('strongest', 0.95, 0.9);
    final List<SelectionCandidate> frontier = <SelectionCandidate>[
      balanced,
      cheapest,
      strongest
    ];

    test('lite 偏向成本', () {
      expect(
          selectRepresentative(frontier, SelectionMode.lite)?.id, 'cheapest');
    });

    test('heavy 偏向通过率', () {
      expect(
          selectRepresentative(frontier, SelectionMode.heavy)?.id, 'strongest');
    });

    test('medium 与 heavy 在该数据下同选最强点', () {
      expect(selectRepresentative(frontier, SelectionMode.medium)?.id,
          'strongest');
    });

    test('单点前沿任何模式都选它', () {
      final List<SelectionCandidate> single = <SelectionCandidate>[
        _c('only', 1, 1)
      ];

      for (final SelectionMode mode in SelectionMode.values) {
        expect(selectRepresentative(single, mode)?.id, 'only');
      }
    });

    test('通过率全相同：只按成本排，lite 选最便宜', () {
      final List<SelectionCandidate> flat = <SelectionCandidate>[
        _c('a', 0.8, 3),
        _c('b', 0.8, 1),
        _c('c', 0.8, 2),
      ];

      expect(selectRepresentative(flat, SelectionMode.lite)?.id, 'b');
    });

    test('成本全相同：按通过率排，heavy 选最高', () {
      final List<SelectionCandidate> flat = <SelectionCandidate>[
        _c('a', 0.7, 1),
        _c('b', 0.9, 1),
        _c('c', 0.8, 1),
      ];

      expect(selectRepresentative(flat, SelectionMode.heavy)?.id, 'b');
    });

    test('全部相同返回第一个，不产生 NaN', () {
      final List<SelectionCandidate> flat = <SelectionCandidate>[
        _c('a', 0.8, 1),
        _c('b', 0.8, 1),
      ];

      final SelectionCandidate? pick =
          selectRepresentative(flat, SelectionMode.medium);

      expect(pick?.id, 'a');
    });

    test('空集合返回 null', () {
      expect(
        selectRepresentative(const <SelectionCandidate>[], SelectionMode.lite),
        isNull,
      );
    });
  });

  group('selectRepresentatives', () {
    test('一次返回三档且各自独立', () {
      final Map<SelectionMode, SelectionCandidate> picked =
          selectRepresentatives(<SelectionCandidate>[
        _c('balanced', 0.90, 1.0),
        _c('cheapest', 0.80, 0.5),
        _c('strongest', 0.95, 0.9),
        _c('dominated', 0.70, 2.0),
      ]);

      expect(picked.keys, containsAll(SelectionMode.values));
      expect(picked[SelectionMode.lite]?.id, 'cheapest');
      expect(picked[SelectionMode.heavy]?.id, 'strongest');
    });

    test('空集合返回空表', () {
      expect(selectRepresentatives(const <SelectionCandidate>[]), isEmpty);
    });
  });
}
