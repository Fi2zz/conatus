/// conatus 的意图路由：用正则和向量做本地意图匹配，命中则直接执行动作，
/// 不命中才走完整 Agent Loop。
///
/// 正则确定性高、零延迟，永远先跑；正则未命中再跑向量；都未命中返回
/// [RouteResult.missed]，由调用方落回 Agent Loop。
///
/// ```dart
/// final IntentRouter router = provideIntentRouter(app);
/// router.register(Intent(
///   name: 'light_on',
///   description: '开灯',
///   patterns: <Pattern>[RegExp(r'^(开灯|把灯打开)')],
///   action: DirectAction((RouteContext ctx) async => device.turnOn('light')),
/// ));
/// ```
///
/// 要把命中接进 Agent Loop，用 [provideIntentRouter] 的 `fastPath`（缺省开启）——
/// 它把路由器接到 `conatus_agent` 已有的确定性快路径上，**必须在
/// `provideAgentLoop` 之前装配**。命中信息经 `IntentRouter.changes`、遥测与
/// `intent/routed` 会话事件外露。
///
/// ⚠️ **实验性**：API 可能在没有 major 版本号变更的情况下发生破坏性改动。
library;

export 'src/action.dart'
    show
        DelegateAction,
        DirectAction,
        RoutedAction,
        ToolAction,
        interpolateArgs;
export 'src/bridges/intent_spec.dart'
    show
        IntentSpec,
        decodeJsonIn,
        kDefaultIntentSpecPrompt,
        parseIntentSpec,
        stringsOf,
        textOf,
        tryCompilePattern;
export 'src/bridges/skill_intent_bridge.dart' show SkillIntentBridge;
export 'src/bridges/tool_intent_generator.dart' show ToolIntentGenerator;
export 'src/candidate.dart' show IntentCandidate;
export 'src/embedding/cosine.dart' show cosineSimilarity;
export 'src/embedding/embedding_provider.dart'
    show EmbeddingLlm, EmbeddingProvider;
export 'src/embedding/llm_embedding.dart' show LlmEmbeddingProvider;
export 'src/embedding/local_embedding.dart'
    show LocalEmbeddingProvider, charGrams, normalizeForEmbedding;
export 'src/errors.dart' show IntentException;
export 'src/events.dart'
    show
        IntentEvent,
        IntentMatched,
        IntentMissed,
        IntentRegistered,
        IntentUnregistered;
export 'src/intent.dart' show Intent;
export 'src/learner.dart' show IntentLearner, kDefaultLearnerPrompt;
export 'src/loader.dart' show IntentHandler, IntentLoader;
export 'src/matcher/priority.dart' show orderByPriority;
export 'src/matcher/regex_matcher.dart' show RegexMatcher;
export 'src/matcher/vector_matcher.dart' show EmbeddingResolver, VectorMatcher;
export 'src/provider.dart'
    show
        IntentContext,
        IntentRouterAdapter,
        kSkillLoadToolName,
        provideIntentRouter;
export 'src/route.dart' show RouteContext, RouteResult, RouteSource;
export 'src/router.dart' show IntentRouter;
export 'src/router_impl.dart' show DefaultIntentRouter, SessionLookup;
