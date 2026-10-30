# conatus_fs_tools

conatus 的**文件工具包**：`read` / `write` / `edit` / `list` / `glob` 五个默认工具、
条件注册的 `grep`（有 runner 与 ripgrep 二进制时）、可选的 `apply_patch` 与审批差异
预览，以及 `provideFsTools` 装配入口。工具走宿主提供的 `FileSystem` 能力缝，因此同一
套实现可跑在本地磁盘、只读闸门或远程沙箱之上。

> ⚠️ **实验性**：API 可能在没有 major 版本变更的情况下破坏性调整，勿在生产依赖。

从 nava（`packages/conatus_code`）的 `lib/fs_tools.dart` 迁出；`.nava` / `.opencode`
路径策略、fs jail、审批链、TUI 与编码工具仍留在 `conatus_code`，**不在本包**。

## 安装

```yaml
dependencies:
  conatus_fs_tools:
    git:
      url: https://github.com/Fi2zz/conatus.git
      ref: master
      path: packages/conatus_fs_tools
```

生产使用请把 `ref` pin 到包含 `packages/conatus_fs_tools` 的具体 commit SHA 或 tag。
或经伞包 `import 'package:conatus/conatus.dart';`（随全部模块包一并导出）。

## 工具表

| 工具 | 参数 | 说明 |
|------|------|------|
| `read` | `path`、`offset`、`limit`、`with_line_numbers` | 读文本（分页 + 行号，单行超 2000 字符截断）；目录返回非递归列举；图片 / PDF 作为附件返回 |
| `write` | `path`、`content`、`mode`、`expected_version` | `create` 要求文件不存在，`overwrite` 覆盖，`append` 追加；结果带 unified diff |
| `edit` | `path`、`old_string`、`new_string`、`replace_all`、`expected_version` | 默认要求唯一匹配，多处匹配返回 `FS_AMBIGUOUS_EDIT` |
| `list` | `path`、`depth`、`limit` | 按深度展开目录，目录以 `/` 结尾 |
| `glob` | `pattern`、`path`、`limit` | 按 glob 模式发现文件，不跟随符号链接目录 |
| `grep` | `pattern`、`path`、`type`、`context`、`limit`、`files_only` | 调用原生 ripgrep；`pattern` / `path` 总在 `--` 之后，不会被当成 flag。需要 `FsToolOptions.runner`（或 `shell`）与 ripgrep 二进制 |
| `apply_patch` | `patch` | 应用 unified diff 或 OpenCode / Codex `***` 补丁；默认**不注册**，经 `FsToolOptions.enablePatch: true` 开启；高风险（`ToolRisk.high`）工具，审批由宿主决定 |

`read` 的图片 / PDF 附件上限为 **20 MiB**：先 `stat` 读元数据，超限直接返回
`FS_TOO_LARGE`，不会把整文件读进内存。

`glob` / `list` 默认跳过 `kDefaultSkipDirs`（`.git` / `node_modules` / `.dart_tool` /
`build`），宿主可经 `skipDirs` 追加自己的目录。

## 装配

```dart
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';

void main() {
  final Context ctx = Context.root();
  provideFileSystemLocal(ctx);      // 提供 'fs' 服务
  provideTools(ctx);                // 提供 'tools' 服务
  provideFsTools(ctx);              // 注册 read / write / edit / list / glob
}
```

`provideFsTools` 返回已注册的工具列表；所有注册都是上下文效应，`ctx.dispose()`
后注册表为空。未提供 `'fs'` / `'tools'` 服务时抛错，除非在选项里显式注入。

### `FsToolOptions`

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `fs` / `tools` | `null` | 覆盖 `'fs'` / `'tools'` 服务（子上下文或测试注入） |
| `shell` | `null` | 子进程执行接缝；提供时缺省用它构造 `ShellRipgrepRunner` |
| `ripgrep` | `null` | ripgrep 二进制；缺省调用 `RipgrepBinary.discover()` 探测系统 / 打包 rg |
| `runner` | `null` | ripgrep 执行接缝；桌面端 / Windows 注入 `ProcessRipgrepRunner`（不经 shell 引号） |
| `eviction` | `null` | 大结果落盘策略；`grep` 结果超上限时使用 |
| `defaultReadLimit` | `2000` | `read` 默认读取行数 |
| `maxReadChars` | `200000` | `read` 返回文本的最大字符数 |
| `rgLimit` | `50` | 搜索类工具默认结果数上限 |
| `enableSearch` | `true` | 是否注册 `glob`（以及条件满足时的 `grep`） |
| `enableList` | `true` | 是否注册 `list` |
| `enablePatch` | `false` | 是否注册 `apply_patch`（高风险补丁工具，由宿主显式开启） |
| `skipDirs` | `kDefaultSkipDirs` | 遍历 / 列举跳过的目录（按 basename） |

```dart
provideFsTools(
  ctx,
  options: FsToolOptions(
    defaultReadLimit: 500,
    skipDirs: <String>{...kDefaultSkipDirs, '.my-cache'},
  ),
);
```

## 宿主职责

本包只提供工具本身，**不携带任何产品策略**：

- **只读路径**：需要保护配置目录时，把 `ReadOnlyPathGuard` 包在 `LocalFileSystem`
  外面再交给 `provideFileSystemLocal`（闸门在 `conatus_foundation`）。
- **结果溢出**：大结果落盘由宿主的 `ToolResultEviction` 中间件负责；`read` 可直接
  读回落盘文件。
- **审批**：`write` / `edit` 风险等级为 `medium`，`apply_patch` 为 `high`（默认不
  注册，开启与否由宿主决定）；是否要求人工审批由宿主的 `ctx.tools.guardRisk(...)`
  与审批链决定。审批浮层可用 `buildApprovalPreview` 按工具参数实时计算差异预览。
- **产品目录**：`.nava` / `.opencode` 这类私有目录的跳过与只读规则由产品自己追加，
  本包不内置。

### 桌面端接入（`products/*`）

产品层只依赖伞包 `conatus`，不直接依赖本包：

```yaml
# products/conatus_work/pubspec.yaml（独立形态）
dependencies:
  conatus:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: <conatus-sha>}
```

```dart
import 'dart:io';

import 'package:conatus/conatus.dart';

void main() {
  final Context ctx = Context.root();
  provideFileSystemLocal(
    ctx,
    fs: ReadOnlyPathGuard(
      inner: LocalFileSystem(cwd: Directory.current.path),
      protectedRoots: <String>[/* 产品自己的配置目录 */],
    ),
  );
  provideTools(ctx);
  provideFsTools(ctx);
}
```
