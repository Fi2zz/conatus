/// 装配：把 [ProviderRegistry] 作为 `'providers'` 服务提供到上下文。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_credentials/conatus_credentials.dart';

import 'provider_defaults.dart';
import 'provider_profile.dart';
import 'provider_registry.dart';
import 'provider_store.dart';

/// `ctx.providers`：当前上下文可见的注册表。
extension ProvidersContext on Context {
  /// 取注册表；未提供返回 `null`。
  ProviderRegistry? get providers => get<ProviderRegistry>('providers');
}

/// 提供注册表为 `'providers'` 服务；调用方负责 [ProviderRegistry.load]。
///
/// [credentials] 是 Key 的唯一来源（通常传 `provideCredentials(ctx)` 的结果）；
/// 不注入时构造出的提供商没有 Key。
ProviderRegistry provideProviders(
  Context ctx, {
  required ProviderStore store,
  List<ProviderProfile> builtin = kDefaultProviders,
  Credentials? credentials,
}) {
  final ProviderRegistry registry = ProviderRegistry(
    store: store,
    builtin: builtin,
    credentials: credentials,
  );
  ctx.provide('providers', registry);
  return registry;
}
