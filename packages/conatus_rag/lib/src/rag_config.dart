import 'embedder.dart';
import 'reranker.dart';
import 'visibility.dart';

/// RAG 服务配置：嵌入、重排、切片尺寸、检索参数与可见性策略。
class RagConfig {
  const RagConfig({
    required this.embedder,
    this.reranker = const NoopReranker(),
    this.chunkChars = 700,
    this.overlapChars = 90,
    this.maxChunkChars = 1200,
    this.candidates = 128,
    this.topK = 15,
    this.injectLimit = 5,
    this.tokenBudget = 2000,
    this.indexVersion = 1,
    this.visibility = const TenantTagPolicy(),
  });

  /// 唯一嵌入器；由宿主装配时注入。
  final Embedder embedder;

  /// 可选重排器；缺省为 [NoopReranker]。
  final Reranker reranker;

  /// 切片目标字符数。
  final int chunkChars;

  /// 相邻切片重叠字符数。
  final int overlapChars;

  /// 单块字符上限，防止超长事件撑爆上下文。
  final int maxChunkChars;

  /// 候选命中数，传给后端搜索。
  final int candidates;

  /// 最终返回的 topK。
  final int topK;

  /// 注入上下文的 topK（通常比 [topK] 小）。
  final int injectLimit;

  /// token 预算上限。
  final int tokenBudget;

  /// 索引版本；与嵌入模型、维度一起校验一致性。
  final int indexVersion;

  /// 可见性策略；缺省为 [TenantTagPolicy]。
  final VisibilityPolicy visibility;
}
