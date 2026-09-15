/// 环境变量凭据来源：只读，进程启动即定形。
library;

import 'dart:io';
import 'credentials.dart';

/// 环境变量凭据：构造时把全部**非空**环境变量装入快照。
///
/// 只读——[update] 抛 [CredentialsException]（`read-only`）。[refresh] 重读
/// [Platform.environment]（注入自定义 [environment] 时读注入的映射），
/// 用于进程内曾改动环境映射（测试替身）的场景。
class EnvCredentials extends Credentials {
  /// 用 [environment] 建立快照；缺省读 `Platform.environment`。
  EnvCredentials({Map<String, String>? environment})
      : _environment = environment ?? Platform.environment {
    _snapshot.refreshSnapshot(_read());
  }

  final Map<String, String> _environment;
  final CredentialSnapshot _snapshot = CredentialSnapshot();

  @override
  List<String> get keys => _snapshot.keys;

  @override
  Stream<Credential> get changes => _snapshot.changes;

  @override
  Credential? get(String key) => _snapshot.get(key);

  @override
  Future<void> update(String key, String value) async {
    throw const CredentialsException('read-only', '环境变量凭据是只读来源。');
  }

  @override
  Future<void> refresh() async => _snapshot.refreshSnapshot(_read());

  @override
  void close() => _snapshot.close();

  Map<String, Credential> _read() => <String, Credential>{
        for (final MapEntry<String, String> entry in _environment.entries)
          if (entry.value.isNotEmpty)
            entry.key: Credential(key: entry.key, value: entry.value),
      };
}
