/// 装配：把 [ProviderRegistry] 作为 `'providers'` 服务提供到上下文。
library;

import 'package:conatus_core/conatus_core.dart';

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
ProviderRegistry provideProviders(
  Context ctx, {
  required ProviderStore store,
  List<ProviderProfile> builtin = kDefaultProviders,
}) {
  final ProviderRegistry registry =
      ProviderRegistry(store: store, builtin: builtin);
  ctx.provide('providers', registry);
  return registry;
}
