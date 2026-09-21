/// conatus 的模型提供商管理：`ProviderProfile` 注册表、JSON 持久化、
/// 自定义 registry 导入，以及按 profile 构造 OpenAI 兼容 [LlmProvider]。
///
/// **实验性**：API 可能在没有 major 版本变更的情况下调整，勿在生产环境依赖。
library;

export 'src/provider_defaults.dart' show kDefaultProviders;
export 'src/provider_import.dart'
    show ProviderImportResult, fetchProviderRegistry, parseProviderRegistry;
export 'src/provider_profile.dart' show ProviderProfile;
export 'src/provider_registry.dart' show ProviderRegistry;
export 'src/provider_store.dart' show ProviderSnapshot, ProviderStore;
export 'src/providers_provider.dart' show ProvidersContext, provideProviders;
