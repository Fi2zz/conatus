import 'package:conatus_skill/conatus_skill.dart';
import 'package:test/test.dart';

SkillCandidate candidate(
  String name, {
  String provider = 'filesystem',
  String source = kSkillSourceProjectConatus,
  int rank = 0,
}) =>
    SkillCandidate(
      rank: rank,
      summary: SkillSummary(
        name: name,
        description: '$name 的说明',
        source: source,
        provider: provider,
      ),
    );

SkillCandidateBatch batchOf(
  int providerOrder,
  List<SkillCandidate> candidates,
) =>
    SkillCandidateBatch(providerOrder: providerOrder, candidates: candidates);

List<String> namesOf(List<SkillCandidate> candidates) => <String>[
      for (final SkillCandidate candidate in candidates) candidate.summary.name,
    ];

void main() {
  group('层内排序', () {
    test('rank 小的先赢下同名', () {
      final List<SkillCandidate> result =
          rankSkillCandidates(<SkillCandidateBatch>[
        batchOf(0, <SkillCandidate>[
          candidate('shared', rank: 200),
        ]),
        batchOf(1, <SkillCandidate>[
          candidate('shared',
              provider: 'user-skills',
              source: kSkillSourceUserConatus,
              rank: 100),
        ]),
      ]);

      expect(result, hasLength(1));
      expect(result.single.summary.provider, 'user-skills');
      expect(result.single.rank, 100);
    });

    test('同 rank 时 provider 注册顺序靠前的赢', () {
      final List<SkillCandidate> result =
          rankSkillCandidates(<SkillCandidateBatch>[
        batchOf(1, <SkillCandidate>[candidate('shared', provider: 'later')]),
        batchOf(0, <SkillCandidate>[candidate('shared', provider: 'earlier')]),
      ]);

      expect(result.single.summary.provider, 'earlier');
    });

    test('同 rank 同 provider 时按产出顺序', () {
      final List<SkillCandidate> result =
          rankSkillCandidates(<SkillCandidateBatch>[
        batchOf(0, <SkillCandidate>[
          candidate('shared'),
          candidate('shared', source: kSkillSourceProjectAgents),
        ]),
      ]);

      expect(result.single.summary.source, kSkillSourceProjectConatus);
    });

    test('不同名技能全部保留并按名字码位升序', () {
      final List<SkillCandidate> result =
          rankSkillCandidates(<SkillCandidateBatch>[
        batchOf(1, <SkillCandidate>[
          candidate('gamma', provider: 'later', rank: 100),
          candidate('alpha', provider: 'later', rank: 100),
        ]),
        batchOf(0, <SkillCandidate>[
          candidate('beta', provider: 'earlier', rank: 100),
          candidate('delta', provider: 'earlier', rank: 100),
        ]),
      ]);

      expect(namesOf(result), <String>['alpha', 'beta', 'delta', 'gamma']);
    });
  });

  group('同名遮蔽', () {
    test('被遮蔽的候选不出现在结果里并上报', () {
      final List<String> shadowed = <String>[];
      final List<SkillCandidate> result = rankSkillCandidates(
        <SkillCandidateBatch>[
          batchOf(1, <SkillCandidate>[
            candidate('shared', provider: 'project-skills', rank: 100),
          ]),
          batchOf(0, <SkillCandidate>[
            candidate('shared',
                provider: 'user-skills',
                source: kSkillSourceUserAgents,
                rank: 500),
          ]),
        ],
        onShadowed: shadowed.add,
      );

      expect(result, hasLength(1));
      expect(result.single.summary.provider, 'project-skills');
      expect(shadowed, hasLength(1));
      expect(shadowed.single, contains('shared'));
      expect(shadowed.single, contains('project-skills'));
      expect(shadowed.single, contains(kSkillSourceUserAgents));
    });

    test('三个同名候选只留赢家，其余逐个上报', () {
      final List<String> shadowed = <String>[];
      final List<SkillCandidate> result = rankSkillCandidates(
        <SkillCandidateBatch>[
          batchOf(0, <SkillCandidate>[
            candidate('shared', provider: 'late', rank: 300),
          ]),
          batchOf(1, <SkillCandidate>[
            candidate('shared', provider: 'mid', rank: 200),
          ]),
          batchOf(2, <SkillCandidate>[
            candidate('shared', provider: 'early', rank: 100),
          ]),
        ],
        onShadowed: shadowed.add,
      );

      expect(result.single.summary.provider, 'early');
      expect(shadowed, hasLength(2));
    });

    test('不传 onShadowed 时静默收敛', () {
      final List<SkillCandidate> result =
          rankSkillCandidates(<SkillCandidateBatch>[
        batchOf(0, <SkillCandidate>[candidate('shared', provider: 'winner')]),
        batchOf(1, <SkillCandidate>[candidate('shared', provider: 'loser')]),
      ]);

      expect(result, hasLength(1));
      expect(result.single.summary.provider, 'winner');
    });
  });

  group('边界', () {
    test('空输入返回空列表', () {
      expect(rankSkillCandidates(const <SkillCandidateBatch>[]), isEmpty);
      expect(
        rankSkillCandidates(<SkillCandidateBatch>[
          batchOf(0, const <SkillCandidate>[]),
        ]),
        isEmpty,
      );
    });
  });
}
