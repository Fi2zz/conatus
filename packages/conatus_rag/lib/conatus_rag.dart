/// conatus 的原始 RAG 能力：会话原文切分、嵌入索引与带可见性过滤的稠密检索。
library;

export 'src/chunker.dart';
export 'src/cosine.dart';
export 'src/embedder.dart';
export 'src/json_backend.dart';
export 'src/rag_backend.dart';
export 'src/rag_index.dart';
export 'src/rag_types.dart';
export 'src/reranker.dart';
export 'src/retriever.dart';
export 'src/vector_index.dart';
export 'src/visibility.dart';
