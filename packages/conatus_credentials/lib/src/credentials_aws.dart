/// AWS Secrets Manager 凭据来源：只读，可定时刷新。
library;

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'credentials.dart';
import 'credentials_sigv4.dart';

/// AWS Secrets Manager 连接配置。
class AwsSecretsConfig {
  const AwsSecretsConfig({
    required this.accessKey,
    required this.secretKey,
    required this.region,
    required this.secretId,
    this.sessionToken,
    this.endpoint,
    this.refreshInterval,
  });

  /// 访问密钥 ID（`AKIA...` / `ASIA...`）。
  final String accessKey;

  /// 访问密钥密文。
  final String secretKey;

  /// 区域（如 `us-east-1`），用于签名 scope 与默认端点。
  final String region;

  /// Secret 名称或 ARN。
  final String secretId;

  /// 临时凭证的会话令牌；非空时随 `X-Amz-Security-Token` 发送并参与签名。
  final String? sessionToken;

  /// 自定义端点（VPC Endpoint / localstack / 测试替身）；缺省按 [region] 推导。
  final String? endpoint;

  /// 定时刷新间隔；`null` 表示只在显式 [AwsSecretsCredentials.refresh] 时拉取。
  final Duration? refreshInterval;
}

/// AWS Secrets Manager 凭据：`GetSecretValue`，读响应里的 `SecretString`。
///
/// 只读——[update] 抛 [CredentialsException]（`read-only`）。`SecretString` 若是
/// JSON 对象则展开成多个键，否则以 [AwsSecretsConfig.secretId] 作为单一键。
/// 非 200 抛 `aws-http`，网络异常包成 `aws-network`。
class AwsSecretsCredentials extends Credentials {
  AwsSecretsCredentials({required AwsSecretsConfig config, http.Client? client})
      : _config = config,
        _client = client ?? http.Client();

  final AwsSecretsConfig _config;
  final http.Client _client;
  final CredentialSnapshot _snapshot = CredentialSnapshot();
  Timer? _timer;

  SigV4Signer get _signer => SigV4Signer(
        accessKey: _config.accessKey,
        secretKey: _config.secretKey,
        sessionToken: _config.sessionToken,
        region: _config.region,
        service: 'secretsmanager',
      );

  Uri get _endpoint => Uri.parse(_config.endpoint ??
      'https://secretsmanager.${_config.region}.amazonaws.com/');

  @override
  List<String> get keys => _snapshot.keys;

  @override
  Stream<Credential> get changes => _snapshot.changes;

  @override
  Credential? get(String key) => _snapshot.get(key);

  @override
  Future<void> update(String key, String value) async {
    throw const CredentialsException('read-only', 'AWS 凭据是只读来源。');
  }

  @override
  Future<void> refresh() async {
    final Uri uri = _endpoint;
    final String payload =
        jsonEncode(<String, String>{'SecretId': _config.secretId});
    final Map<String, String> headers = _signer.sign(
      method: 'POST',
      uri: uri,
      headers: <String, String>{
        'Content-Type': 'application/x-amz-json-1.1',
        'X-Amz-Target': 'secretsmanager.GetSecretValue',
      },
      payload: payload,
      timestamp: DateTime.now().toUtc(),
    );
    final http.Response response;
    try {
      response = await _client.post(uri, headers: headers, body: payload);
    } catch (error) {
      throw CredentialsException('aws-network', '访问 Secrets Manager 失败：$error');
    }
    if (response.statusCode != 200) {
      throw CredentialsException(
        'aws-http',
        'Secrets Manager 返回 HTTP ${response.statusCode}。',
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
    final Object? secret = decoded['SecretString'];
    if (secret is! String) return <String, Credential>{};
    final Map<String, Credential> expanded = _expand(secret);
    if (expanded.isNotEmpty) return expanded;
    return <String, Credential>{
      _config.secretId: Credential(key: _config.secretId, value: secret),
    };
  }

  Map<String, Credential> _expand(String secret) {
    try {
      return parseCredentialMap(jsonDecode(secret));
    } on FormatException {
      return <String, Credential>{};
    }
  }

  void _schedule() {
    final Duration? interval = _config.refreshInterval;
    if (interval == null || _timer != null) return;
    _timer = Timer.periodic(interval, (_) => unawaited(refresh()));
  }
}
