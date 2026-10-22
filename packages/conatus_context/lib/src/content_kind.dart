/// 可压缩/可识别的内容类型。
///
/// [sourceCode] 与 [passthrough] 只用于识别，压缩器不会处理它们：
/// 源码改写风险高，`git status` 等结构化文本必须逐字保留。
library;

enum ContentKind {
  jsonArray,
  buildLog,
  searchResults,
  diff,
  tabular,
  text,
  sourceCode,
  passthrough,
}
