/// 本地 JSON 文件凭据来源：只读，可定时刷新。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'credentials.dart';

/// 本地 JSON 文件凭据，两种形态都支持：
///
/// ```json
/// { "ARK_API_KEY": "sk-xxx" }
/// { "ARK_API_KEY": { "value": "sk-xxx", "expiresAt": "2026-01-01T00:00:00Z" } }
/// ```
///
/// 只读——[update] 抛 [CredentialsException]（`read-only`）。构造后需调用
/// [load]（或 [refresh]）把文件读进快照；[refreshInterval] 非空时 [load] 之后
/// 会自动起定时器，每次到点重读文件，[close] 取消。文件不存在时若给了
/// `fallback` 则用 `fallback`，否则快照为空。
class FileCredentials extends Credentials {
  /// 读 [path] 处的 JSON 文件；[fallback] 是文件缺失时的兜底值。
  FileCredentials({
    required String path,
    Map<String, String>? fallback,
    Duration? refreshInterval,
  })  : _path = path,
        _refreshInterval = refreshInterval,
        _fallback = <String, Credential>{
          for (final MapEntry<String, String> entry
              in (fallback ?? const <String, String>{}).entries)
            entry.key: Credential(key: entry.key, value: entry.value),
        };

  final String _path;
  final Duration? _refreshInterval;
  final Map<String, Credential> _fallback;
  final CredentialSnapshot _snapshot = CredentialSnapshot();
  Timer? _timer;

  @override
  List<String> get keys => _snapshot.keys;

  @override
  Stream<Credential> get changes => _snapshot.changes;

  @override
  Credential? get(String key) => _snapshot.get(key);

  @override
  Future<void> update(String key, String value) async {
    throw const CredentialsException('read-only', '文件凭据是只读来源。');
  }

  /// 读文件入快照；文件不存在时退回 `fallback`。之后按需续上定时刷新。
  Future<void> load() async {
    final File file = File(_path);
    if (await file.exists()) {
      _snapshot.refreshSnapshot(
          parseCredentialMap(jsonDecode(await file.readAsString())));
    } else {
      _snapshot.refreshSnapshot(_fallback);
    }
    _schedule();
  }

  @override
  Future<void> refresh() => load();

  @override
  void close() {
    _timer?.cancel();
    _timer = null;
    _snapshot.close();
  }

  void _schedule() {
    final Duration? interval = _refreshInterval;
    if (interval == null || _timer != null) return;
    _timer = Timer.periodic(interval, (_) => unawaited(refresh()));
  }
}
