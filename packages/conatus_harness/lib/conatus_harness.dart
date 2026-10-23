/// conatus_harness：可版本化的 harness 制品（实验性）。
///
/// 一份 manifest 描述执行档位、指令段与工具边界；[applyHarness] 把它装成一棵
/// 可回滚的 Context 子树，[diffHarness] 给出人可读差异。
library;

export 'src/apply_harness.dart' show applyHarness, harnessToolBoundary;
export 'src/diff_harness.dart' show diffHarness;
export 'src/manifest.dart' show HarnessManifest, PromptSectionSpec;
