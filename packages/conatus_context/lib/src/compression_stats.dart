/// 按内容类型累计的压缩统计。
///
/// 字符数口径；token 是 `chars / 4` 的估算，输出带 `estimated: true`。
library;

import 'compression_result.dart';
import 'content_kind.dart';

/// 单一内容类型的统计。
class KindStats {
  /// 实际压缩次数。
  int applied = 0;

  /// 跳过次数。
  int skipped = 0;

  /// 压缩器抛错次数（已计入 skipped）。
  int failures = 0;

  /// 压缩前字符数。
  int beforeChars = 0;

  /// 压缩后字符数。
  int afterChars = 0;

  /// 存入 CCR 的次数。
  int ccrStored = 0;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'applied': applied,
        'skipped': skipped,
        'failures': failures,
        'beforeChars': beforeChars,
        'afterChars': afterChars,
        'savedChars': beforeChars - afterChars,
        'ccrStored': ccrStored,
      };
}

/// 全局压缩统计。
class CompressionStats {
  /// 按类型分组的统计。
  final Map<ContentKind, KindStats> byKind = <ContentKind, KindStats>{};

  /// 压缩次数。
  int applied = 0;

  /// 跳过次数。
  int skipped = 0;

  /// 失败次数。
  int failures = 0;

  /// 压缩前字符数。
  int beforeChars = 0;

  /// 压缩后字符数。
  int afterChars = 0;

  /// 存入 CCR 的次数。
  int ccrStored = 0;

  /// CCR 命中次数。
  int ccrHits = 0;

  /// 处理过的总条数。
  int get total => applied + skipped;

  /// 取某类型的统计（不存在时创建）。
  KindStats kindStats(ContentKind kind) =>
      byKind.putIfAbsent(kind, KindStats.new);

  /// 记录一次结果。
  void record(ContextCompressionResult result, {bool ccrStored = false}) {
    final KindStats kind = kindStats(result.kind);
    kind.beforeChars += result.beforeChars;
    kind.afterChars += result.afterChars;
    beforeChars += result.beforeChars;
    afterChars += result.afterChars;
    if (result.applied) {
      applied++;
      kind.applied++;
    } else {
      skipped++;
      kind.skipped++;
    }
    if (ccrStored) {
      this.ccrStored++;
      kind.ccrStored++;
    }
  }

  /// 记录一次压缩器失败。
  void recordFailure(ContentKind kind) {
    failures++;
    kindStats(kind).failures++;
  }

  /// 记录一次 CCR 命中。
  void countCcrHit() {
    ccrHits++;
  }

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'estimated': true,
        'tokenEstimator': 'chars/4',
        'applied': applied,
        'skipped': skipped,
        'failures': failures,
        'beforeChars': beforeChars,
        'afterChars': afterChars,
        'savedChars': beforeChars - afterChars,
        'estimatedTokensSaved': (beforeChars - afterChars) ~/ 4,
        'ccrStored': ccrStored,
        'ccrHits': ccrHits,
        'byKind': <String, Object?>{
          for (final MapEntry<ContentKind, KindStats> entry in byKind.entries)
            entry.key.name: entry.value.toJson(),
        },
      };
}
