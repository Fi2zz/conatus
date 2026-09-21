/// 提供商注册表：增删改查、当前选中、持久化与 LlmProvider 构造。
library;

import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:http/http.dart' as http;

import 'provider_import.dart';
import 'provider_profile.dart';
import 'provider_store.dart';

/// 模型提供商注册表。
class ProviderRegistry {
  ProviderRegistry({
    required ProviderStore store,
    List<ProviderProfile> builtin = const <ProviderProfile>[],
    Credentials? credentials,
  })  : _store = store,
        _builtin = builtin,
        _credentials = credentials;

  final ProviderStore _store;
  final List<ProviderProfile> _builtin;

  /// Key 的唯一来源（缺省不注入时构造出的提供商没有 Key）。
  final Credentials? _credentials;

  final List<ProviderProfile> _profiles = <ProviderProfile>[];
  String? _current;

  /// 全部提供商（只读视图）。
  List<ProviderProfile> get profiles =>
      List<ProviderProfile>.unmodifiable(_profiles);

  /// 当前选中的提供商名。
  String? get currentName => _current;

  /// 当前选中的提供商。
  ProviderProfile? get current => byName(_current);

  /// 按名查找；不存在返回 `null`。
  ProviderProfile? byName(String? name) {
    if (name == null) {
      return null;
    }
    for (final ProviderProfile profile in _profiles) {
      if (profile.name == name) {
        return profile;
      }
    }
    return null;
  }

  /// 读盘；无文件（或空列表）时用内置默认，并落盘。
  Future<void> load() async {
    final ProviderSnapshot snapshot = _store.load();
    _profiles
      ..clear()
      ..addAll(snapshot.providers.isEmpty ? _builtin : snapshot.providers);
    _current = byName(snapshot.current) != null
        ? snapshot.current
        : (_profiles.isEmpty ? null : _profiles.first.name);
    _persist();
  }

  /// 新增或覆盖同名提供商；[select] 为 true（或尚无当前项）时一并切过去。
  Future<void> add(ProviderProfile profile, {bool select = false}) async {
    final int index =
        _profiles.indexWhere((ProviderProfile p) => p.name == profile.name);
    if (index < 0) {
      _profiles.add(profile);
    } else {
      _profiles[index] = profile;
    }
    if (select || _current == null) {
      _current = profile.name;
    }
    _persist();
  }

  /// 删除；当前项被删时切到剩余首个（全删则无当前项）。
  Future<void> remove(String name) async {
    _profiles.removeWhere((ProviderProfile p) => p.name == name);
    if (_current == name) {
      _current = _profiles.isEmpty ? null : _profiles.first.name;
    }
    _persist();
  }

  /// 切换当前提供商；不存在返回 `false`。
  Future<bool> select(String name) async {
    if (byName(name) == null) {
      return false;
    }
    _current = name;
    _persist();
    return true;
  }

  /// 导入 registry 并合并（同名覆盖）；返回导入结果。
  ///
  /// [client] 供测试注入；缺省用一次性 [http.Client]。
  Future<ProviderImportResult> importRegistry({
    required String url,
    required String token,
    http.Client? client,
  }) async {
    final ProviderImportResult result =
        await fetchProviderRegistry(url: url, token: token, client: client);
    if (!result.isSuccess) {
      return result;
    }
    for (final ProviderProfile profile in result.providers) {
      await add(profile);
    }
    return result;
  }

  /// 按名构造 OpenAI 兼容提供商；无此 provider 或没有模型名时返回 `null`。
  ///
  /// Key 经注册表持有的 [Credentials] 解析（不直接读环境变量）。
  LlmProvider? buildLlm(String name, {String? model}) {
    final ProviderProfile? profile = byName(name);
    final String resolvedModel = model ?? profile?.defaultModel ?? '';
    if (profile == null || resolvedModel.isEmpty) {
      return null;
    }
    return OpenAiCompatibleProvider(
      name: profile.name,
      baseUrl: profile.baseUrl,
      model: resolvedModel,
      credentialKey: profile.credentialKey,
      apiStyle: profile.apiStyle,
      userAgent: profile.userAgent.isEmpty ? kDefaultLlmUserAgent : profile.userAgent,
      credentials: _credentials,
    );
  }

  void _persist() =>
      _store.save(ProviderSnapshot(providers: _profiles, current: _current));
}
