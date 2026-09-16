/// cron 运行历史账本：加载、追加、状态推进与封顶。
///
/// 账本惰性加载 JSONL（旧记录在前），对外列表最新在前；追加后整体封顶
/// [kCronMaxHistory] 并原子重写文件；seq 单调连续，加载时从最大 seq 续接。
library;

import 'cron_history.dart';
import 'cron_storage.dart';
import 'cron_types.dart';

/// 运行历史账本。
class CronHistoryBook {
  /// 构造一个账本；[clock] 只用于 finish 的完成时刻。
  CronHistoryBook({required CronStorage storage, DateTime Function()? clock})
      : _storage = storage,
        _clock = clock ?? DateTime.now;

  final CronStorage _storage;
  final DateTime Function() _clock;
  final List<CronRunRecord> _records = <CronRunRecord>[];
  bool _loaded = false;
  int _seq = 0;

  /// 全部记录（旧记录在前）。
  List<CronRunRecord> get records => List<CronRunRecord>.unmodifiable(_records);

  /// 预分配一个记录标识并占用 seq；交付被拒时调用 [releaseRef] 归还。
  CronRecordRef allocateRef(DateTime now) {
    final CronRecordRef ref = CronRecordRef(
      id: 'run-$_seq-${now.millisecondsSinceEpoch.toRadixString(36)}',
      seq: _seq,
    );
    _seq++;
    return ref;
  }

  /// 归还最近一次分配的标识（仅当它是最新分配时生效）。
  void releaseRef(CronRecordRef ref) {
    if (ref.seq == _seq - 1) _seq--;
  }

  /// 追加一条记录并持久化；超帽时从头部裁剪。
  CronRunRecord append(CronRunRecord record) {
    _loadOnce();
    _records.add(record);
    _trim();
    _persist();
    return record;
  }

  /// 推进一条记录到终态；记录不存在时返回 null。摘要截断到 [kCronExcerptLength]。
  CronRunRecord? finish(String recordId, {required bool ok, String? excerpt}) {
    _loadOnce();
    for (final CronRunRecord record in _records) {
      if (record.id != recordId) continue;
      record.status = ok ? CronRunStatus.completed : CronRunStatus.failed;
      record.completedAt = _clock();
      record.excerpt = _truncate(excerpt ?? record.excerpt);
      _persist();
      return record;
    }
    return null;
  }

  /// 最新在前的历史列表；[limit] 非法时退化为 100，封顶 [kCronMaxHistory]。
  List<CronRunRecord> list({int? limit}) {
    _loadOnce();
    final int cap = _resolveCap(limit);
    final int start = _records.length > cap ? _records.length - cap : 0;
    return _records.sublist(start).reversed.toList(growable: false);
  }

  void _loadOnce() {
    if (_loaded) return;
    _loaded = true;
    for (final Map<String, Object?> line in _storage.loadHistory()) {
      final CronRunRecord? record = CronRunRecord.fromJson(line);
      if (record == null) continue;
      _records.add(record);
      if (record.seq >= _seq) _seq = record.seq + 1;
    }
    _trim();
  }

  void _trim() {
    if (_records.length > kCronMaxHistory) {
      _records.removeRange(0, _records.length - kCronMaxHistory);
    }
  }

  void _persist() {
    _storage.saveHistory(<Map<String, Object?>>[
      for (final CronRunRecord record in _records) record.toJson(),
    ]);
  }

  String? _truncate(String? excerpt) {
    if (excerpt == null || excerpt.length <= kCronExcerptLength) return excerpt;
    return excerpt.substring(0, kCronExcerptLength);
  }
}

int _resolveCap(int? limit) {
  if (limit == null || limit <= 0) return 100;
  return limit > kCronMaxHistory ? kCronMaxHistory : limit;
}
