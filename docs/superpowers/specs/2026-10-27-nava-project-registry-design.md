# nava 项目注册表与工作区存储设计

## 背景

nava 当前把项目数据放在：

```text
~/.nava/projects/<URL 编码的规范工作区路径>/
```

会话、记忆、检查点、权限和导出文件都在这个目录下。这个方案可逆、无碰撞，但目录名非常难读，且测试曾把临时工作区写进真实 `~/.nava/projects`，留下大量一次性目录。

OpenCode v2 的做法是把项目元数据收进 SQLite，项目 ID 由 git remote / root commit / 路径哈希稳定生成，显示名是独立字段，磁盘上不再用编码路径命名。

本设计采用「项目层对齐 OpenCode，会话文件继续留在文件系统」的折中：

- 项目注册表进 SQLite；
- 同一 git 仓库的多个 clone / worktree 共享一个项目；
- 每个 worktree 的会话、记忆、检查点等仍独立存放；
- 数据目录改为可读的 `basename + 短哈希`，不再使用 URL 编码路径。

## 目标

1. `~/.nava/projects/` 不再作为默认数据目录，也不再读取其中的旧数据。
2. 新增 `~/.nava/projects.db`，保存项目和工作区元数据。
3. 新增 `~/.nava/workspaces/<basename>-<短哈希>/`，保存每个 worktree 的运行数据。
4. 同一 git remote 的多个 clone / worktree 共享项目记录，但各自有独立数据目录。
5. 项目默认显示名为工作区 basename；支持 `/project rename <名字>`。
6. 首次启动自动建库、登记当前工作区并创建目录；旧数据不迁移。
7. 不改变会话 JSONL、记忆、检查点、权限、导出文件的内部格式。

## 非目标

- 不把会话、消息、检查点内容迁移进 SQLite。
- 不迁移旧的 `~/.nava/projects/` 数据。
- 不实现跨设备同步、项目归档、项目列表 UI 或远程项目拉取。
- 不创建、删除、切换 git worktree；`worktree` 表只登记已有 checkout。
- 不改变 `.opencode` 只读约束。
- 第一阶段不保证 Windows 上系统 SQLite 的可用性；nava 的 Windows 命令执行本来就禁用，后续可补 `sqlite3.dll` 分发。

## 目录布局

```text
~/.nava/
├── config.toml
├── projects.db
└── workspaces/
    ├── lifts-3f9a2c1b7d4e/
    │   ├── sessions/
    │   ├── memory.json
    │   ├── checkpoints/
    │   ├── permissions.json
    │   └── exports/
    └── conatus-8a1c0e5f2b93/
```

`NAVA_HOME` 仍覆盖 `~/.nava`，因此：

- DB：`$NAVA_HOME/projects.db`
- 工作区根：`$NAVA_HOME/workspaces`

旧 `$NAVA_HOME/projects/` 不参与解析。启动时若检测到旧目录，只提示一次「旧 projects 目录已不再使用，可删除」，不读取、不迁移、不删除。

## 项目身份

### 规范路径

`workdir` 先做真实路径解析（`resolveSymbolicLinksSync`，失败回退绝对路径），得到 `canonicalPath`。

如果 `workdir` 在 git 仓库内：

- worktree 根取 `git rev-parse --show-toplevel`；
- 数据目录和 `worktree_id` 基于 worktree 根，而不是启动时的子目录；
- 在仓库子目录启动时，与在仓库根启动落到同一项目/worktree。

非 git 目录的 worktree 根就是 `canonicalPath`。

### project_id

按以下顺序生成 40 位 SHA-1：

1. git remote 存在：`sha1("git-remote:" + normalizedRemote)`
   - `normalizedRemote = "<host>/<path>"`；
   - host 转小写；
   - 去掉协议、用户名、`.git` 后缀和尾部 `/`；
   - 支持 `https://host/path`、`ssh://...`、`git@host:path`。
2. 无 remote：`sha1("git-root:" + rootCommit)`
   - `rootCommit` 取 `git rev-list --max-parents=0 HEAD` 的第一个结果。
3. 非 git：`sha1("directory:" + canonicalPath)`。

同一 remote 的多个 clone/worktree 因此共享 `project_id`；非 git 目录按路径区分。

### 与 OpenCode Worktree 的边界

OpenCode v2 的 `Worktree` 服务会真正执行 `git worktree add`，在
`~/.local/share/opencode/worktree/<project-id 前 6 位>/` 下创建可切换的 checkout，并支持
create / remove / list / refresh；其 `worktree` 表带 `strategy` 字段。

本设计不包含这部分管理能力。nava 的 `worktree` 表只登记：

- 用户已有的主 checkout；
- 用户通过 git 自行创建的 linked worktree；
- 不创建目录、不执行 `git worktree add/remove`、不提供 worktree 切换命令。

这样仍能实现「同仓库共享项目、不同 checkout 数据隔离」，但不会把 nava 变成 git
worktree 管理器。未来若要补齐，可在现有表上加 `strategy` 字段并增加命令，不影响当前
项目/目录模型。

### worktree_id

`sha1("worktree:" + worktreePath)`，40 位十六进制。

### 目录名

```text
<slug>-<worktree_id 前 12 位>
```

- `slug` 取 worktree 根 basename；
- 保留 Unicode 字母、数字、`.`、`_`、`-`；
- 其他字符替换为 `-`，连续 `-` 合并，首尾 `-` 去掉；
- 空 slug 回退为 `workspace`；
- slug 最长 32 个字符（按 Unicode 字符截断）；
- 如果生成的目录名已被另一个 worktree 占用，依次把哈希长度扩到 16、20、40 位，直到唯一；
- 目录名只分配一次，写入 DB 后不再变化；`/project rename` 不改目录名。

示例：

```text
lifts-3f9a2c1b7d4e
conatus-8a1c0e5f2b93
工作区-1a2b3c4d5e6f
```

## SQLite 模型

数据库使用 `package:sqlite3` 2.x（系统 SQLite）。不使用 3.x 的 build hook，因为仓库的 `dart compile exe` 不支持 build hooks。

启动时执行：

```sql
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;
```

schema 版本通过 `PRAGMA user_version` 管理，当前为 `1`。

```sql
CREATE TABLE project (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  vcs TEXT,
  remote TEXT,
  time_created INTEGER NOT NULL,
  time_updated INTEGER NOT NULL
);

CREATE TABLE worktree (
  id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
  path TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  dir_name TEXT NOT NULL UNIQUE,
  time_created INTEGER NOT NULL,
  time_updated INTEGER NOT NULL
);

CREATE INDEX worktree_project_idx ON worktree(project_id);
```

约束：

- `project.name` 允许重名；显示名不是身份。
- `worktree.path` 唯一，保证同一路径只登记一次。
- `worktree.dir_name` 唯一，避免目录冲突。
- 数据库文件及其 `-wal` / `-shm` 创建后收紧为 `0600`；`workspaces/` 创建为 `0700`（POSIX；Windows 忽略 chmod）。
- 注册表与工作区路径命中 `.opencode` 只读面时拒绝启动；不在受保护目录创建 DB 或工作区。
- 数据库缺失时自动创建；文件存在但不是合法 SQLite、`user_version` 不认识、或 schema 损坏时，启动失败并打印 DB 路径，不静默重建或丢项目。

## resolve 流程

`ProjectRegistry.resolve(workdir)`：

1. 解析 canonical path 和 worktree path。
2. 推导 `project_id`、`worktree_id`。
3. 在一个 SQLite 事务内：
   - `project` 不存在则插入，`name` 默认 worktree basename；
   - `project` 已存在则更新 `remote`、`vcs`、`time_updated`，不覆盖用户改过的 `name`；
   - `worktree` 不存在则插入，分配 `dir_name`；
   - `worktree` 已存在则更新 `project_id`（remote 改变时）和 `time_updated`；
   - 创建 `workspaces/<dir_name>/`（已存在则复用）。
4. 返回：

```dart
class WorkspaceInfo {
  final String projectId;
  final String projectName;
  final String worktreeId;
  final String worktreePath;
  final String dataDir;
}
```

同一路径重复 resolve 必须幂等，不生成新目录、不改变已有目录名。

## 启动集成

`ConatusTuiRuntime.create` 的解析顺序：

1. 显式 `baseDir`：直接使用，完全绕过项目注册表（测试和嵌入式调用）。
2. 显式 `[agent] project_dir`：使用该目录，但仍登记项目/worktree（保持旧配置语义）。
3. 其他情况：调用 `ProjectRegistry.resolve(workdir)`，使用返回的 `dataDir`。

为测试注入，`ConatusTuiRuntime.create` 增加可选 `ProjectRegistry? projectRegistry`；为 null 时按 `NAVA_HOME` 打开默认 DB。

runtime 向上下文提供：

```dart
app.provide('projectDataDir', resolvedBaseDir);
app.provide('projectInfo', workspaceInfo);
```

`ConatusTuiController` 的 `/export` 改为读取 `projectDataDir`，不再用 `workdir + project_dir` 重新推导。

`sessionDir`、`memoryFile` 等显式参数优先级保持不变。

## 命令

### `/project`

输出当前项目信息：

```text
项目：lifts
ID：3f9a2c1b
worktree：/Users/fitz/REPO/lifts
数据目录：~/.nava/workspaces/lifts-3f9a2c1b7d4e
```

显式 `baseDir` 或 registry 未启用时，提示「项目注册表未启用」。

### `/project rename <名字>`

- 去掉首尾空白，长度 1–80；
- 拒绝换行和控制字符；
- 更新当前 `project.name`；
- 不修改目录名、不修改会话标题；
- 成功提示新名字；失败提示原因。

项目名当前通过 `/project` 展示，供后续项目列表/选择器复用；本阶段不改变状态栏和标签栏布局。

## 兼容与弃用

- `resolveProjectDataDir` / `defaultProjectDataDir` 保留导出，但标记为 legacy，只服务显式 `project_dir` 和旧调用方；runtime 不再使用默认编码路径。
- 旧 `projects/` 数据不自动迁移；用户可自行删除。
- `project_data_dir_test` 中针对编码路径默认值的断言改为测试 legacy helper 或删除；新增 registry/path 测试。

## 错误处理

- SQLite 打不开、DB 损坏、schema 版本未知：启动失败，错误包含 DB 路径和建议（备份后删除 DB 重建）。
- 数据目录创建失败：启动失败，错误包含目标路径。
- `dir_name` 分配冲突：扩展哈希重试；40 位仍冲突则抛错，不覆盖已有目录。
- 多个 nava 进程同时启动：WAL + busy_timeout；唯一约束兜底，冲突时重新读取既有记录。
- `project_dir` 指向 `.opencode` 的只读保护保持现有行为。

## 测试

新增：

- `project_identity_test`：remote / root commit / 非 git 三种 project id；同 remote 不同路径共享；同路径 worktree id 稳定。
- `project_workspace_path_test`：Unicode slug、非法字符、空 basename、12/16/20/40 位冲突扩展。
- `project_registry_test`：自动建库、幂等 resolve、同项目多 worktree、rename、DB schema 版本、损坏 DB 报错。
- `tui_project_command_test`：`/project` 输出、`/project rename` 成功/非法输入、registry 未启用提示。
- `tui_app_project_resolve_test`：临时 registry 下 runtime 使用新 dataDir；显式 baseDir 绕过 DB；显式 project_dir 仍登记项目。

更新：

- `/export` 测试改用临时 `projectDataDir`/registry，不能写真实 `~/.nava`。
- 所有新增测试使用临时目录，不污染真实 home。

验证：

```bash
cd packages/conatus_code
dart analyze
dart test
bash tool/build_binary.sh
```

## 风险

1. **sqlite3 2.x 依赖系统库**：macOS/Linux 通常自带；Windows 需要额外分发 `sqlite3.dll`。本阶段接受 macOS/Linux，README 明确说明。
2. **DB 成为单点**：数据目录里仍有真实会话文件；DB 丢失会失去项目映射。第一阶段不实现自动扫描恢复，错误信息提示备份/重建。
3. **git 命令开销**：每次启动执行少量 `git rev-parse`；只有启动一次，可接受。remote/root commit 失败时回退路径哈希，不阻塞启动。
4. **同 remote 的项目共享显示名**：这是 OpenCode 语义；不同 clone 的用户改的是同一个项目名。worktree 数据仍隔离。

## 验收标准

- 新目录 `~/.nava/projects/` 不再被读取或创建。
- 首次启动生成 `projects.db` 和 `workspaces/<basename>-<hash>/`。
- 同一 remote 的两个 worktree：`project` 一行、`worktree` 两行、两个数据目录。
- 非 git 目录：一个 project、一个 worktree。
- `/project rename` 持久化，重启后仍生效，目录名不变。
- 显式 `baseDir` 不写默认 DB；测试不污染真实 home。
- `dart analyze`、全量测试、`dart compile exe` 构建均通过。
