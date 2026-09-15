/// HashiCorp Vault KV v2 凭据来源：只读，可定时刷新。
library;

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'credentials.dart';

/// Vault KV v2 连接配置。
class VaultConfig {
  const VaultConfig({
    required this.address,
    required this.token,
    required this.path,
    this.mount = 'secret',
    this.refreshInterval,
  });

  /// Vault 地址（如 `http://127.0.0.1:8200`）；末尾斜杠可有可无。
  final String address;

  /// Vault Token，作为 `X-Vault-Token` 发送。
  final String token;

  /// KV v2 路径（如 `conatus/llm`）。
  final String path;

  /// KV 挂载点，默认 `secret`。
  final String mount;

  /// 定时刷新间隔；`null` 表示只在显式 [VaultCredentials.refresh] 时拉取。
  final Duration? refreshInterval;
}

/// Vault KV v2 凭据：`GET {address}/v1/{mount}/data/{path}`，读 `data.data`。
///
/// 只读——[update] 抛 [CredentialsException]（`read-only`）。`data.data` 里每项
/// 可以是字符串，也可以是 `{"value": ..., "expiresAt": ...}` 对象。
/// 非 200 抛 `vault-http`，网络异常包成 `vault-network`。
class VaultCredentials extends Credentials {
  VaultCredentials({required VaultConfig config, http.Client? client})
      : _config = config,
        _client = client ?? http.Client();

  final VaultConfig _config;
  final http.Client _client;
  final CredentialSnapshot _snapshot = CredentialSnapshot();
  Timer? _timer;

  /// 后端地址；传入的 `http.Client` 生命周期由调用方管理，这里不关闭。
  Uri get _endpoint {
    final String address = _config.address.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$address/v1/${_config.mount}/data/${_config.path}');
  }

  @override
  List<String> get keys => _snapshot.keys;

  @override
  Stream<Credential> get changes => _snapshot.changes;

  @override
  Credential? get(String key) => _snapshot.get(key);

  @override
  Future<void> update(String key, String value) async {
    throw const CredentialsException('read-only', 'Vault 凭据是只读来源。');
  }

  @override
  Future<void> refresh() async {
    final http.Response response;
    try {
      response = await _client.get(_endpoint, headers: <String, String>{
        'X-Vault-Token': _config.token,
      });
    } catch (error) {
      throw CredentialsException('vault-network', '访问 Vault 失败：$error');
    }
    if (response.statusCode != 200) {
      throw CredentialsException(
        'vault-http',
        'Vault 返回 HTTP ${response.statusCode}。',
      );
    }
    _snapshot.refreshSnapshot(_parse(response.body));
    _schedule();
  }

  @override
  void close() {
    _timer?.cancel();
    _timer = null;
    _snapshot.close();
  }

  Map<String, Credential> _parse(String body) {
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map) return <String, Credential>{};
    final Object? data = decoded['data'];
    if (data is! Map) return <String, Credential>{};
    return parseCredentialMap(data['data']);
  }

  void _schedule() {
    final Duration? interval = _config.refreshInterval;
    if (interval == null || _timer != null) return;
    _timer = Timer.periodic(interval, (_) => unawaited(refresh()));
  }
}
