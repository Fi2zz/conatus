/// conatus 的文件工具包：`read` / `write` / `edit` / `list` / `glob`、可选的
/// `apply_patch` 与审批差异预览，以及 `provideFsTools` 装配。
///
/// **实验性**：API 可能在没有 major 版本变更的情况下调整，勿在生产环境依赖。
library;

export 'src/apply_patch.dart' show ApplyPatchTool;
export 'src/edit_file.dart' show EditFileTool;
export 'src/fs_tools.dart' show FsToolOptions, kDefaultSkipDirs, provideFsTools;
export 'src/glob_tool.dart' show GlobTool;
export 'src/list_files.dart' show ListFilesTool, ListLimits;
export 'src/preview.dart' show buildApprovalPreview, kPreviewMaxChars;
export 'src/read_file.dart' show ReadFileTool;
export 'src/ripgrep_binary.dart' show RipgrepBinary, RipgrepSource;
export 'src/ripgrep_runner.dart'
    show
        ProcessRipgrepRunner,
        RipgrepRunResult,
        RipgrepRunner,
        ShellRipgrepRunner;
export 'src/ripgrep_tool.dart' show RipgrepLimits, RipgrepTool;
export 'src/write_file.dart' show WriteFileTool, WriteMode;
