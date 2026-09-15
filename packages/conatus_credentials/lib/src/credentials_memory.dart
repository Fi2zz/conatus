/// 内存凭据来源：可写，进程内临时凭据与测试替身。
library;

import 'credentials.dart';

/// 纯内存凭据：[update] 立即生效并推送 [changes]。
///
/// 适合进程内临时凭据、测试替身，或由外部同步流程（如 `aws configure`
/// 之外的登录流程）写值的场景。[refresh] 继承基类的无操作实现。
class InMemoryCredentials extends Credentials {
  /// 用 [initial] 建立初始快照。
  InMemoryCredentials(
      {Map<String, String> initial = const <String, String>{}}) {
    _snapshot.refreshSnapshot(<String, Credential>{
      for (final MapEntry<String, String> entry in initial.entries)
        entry.key: Credential(key: entry.key, value: entry.value),
    });
  }

  final CredentialSnapshot _snapshot = CredentialSnapshot();

  @override
  List<String> get keys => _snapshot.keys;

  @override
  Stream<Credential> get changes => _snapshot.changes;

  @override
  Credential? get(String key) => _snapshot.get(key);

  @override
  Future<void> update(String key, String value) async {
    _snapshot.update(Credential(key: key, value: value));
  }

  @override
  void close() => _snapshot.close();
}
