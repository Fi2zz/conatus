# nava Project Registry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace encoded-path `~/.nava/projects/*` storage with a SQLite project registry plus short, readable per-worktree directories under `~/.nava/workspaces/`.

**Architecture:** A deterministic identity layer derives `project_id` and `worktree_id` from git remote/root commit/canonical path. A synchronous SQLite registry stores project/worktree metadata, allocates `basename-shorthash` directory names, and returns a `WorkspaceInfo` used by the runtime for all per-worktree files. Sessions, memory, checkpoints, permissions, and exports stay on the filesystem; only project/worktree metadata moves into SQLite.

**Tech Stack:** Dart 3.11 workspace, `package:sqlite3` 2.x with system SQLite, `package:crypto` (already present), `package:test`.

**Spec:** `docs/superpowers/specs/2026-10-27-nava-project-registry-design.md`

## Global Constraints

- New data root: `$NAVA_HOME/workspaces/<basename>-<worktree_id first 12 hex>/`.
- New registry: `$NAVA_HOME/projects.db`.
- Never read or create the legacy `~/.nava/projects/` default; explicit `[agent] project_dir` remains supported.
- Same git remote shares `project_id`; every checkout has its own `worktree_id` and data directory.
- Do not create, remove, or switch git worktrees.
- `sqlite3` must be `^2.9.0`; do not use 3.x build hooks because `dart compile exe` rejects them.
- DB file mode `0600`; workspaces root mode `0700` on POSIX.
- Project name length 1–80, no control characters; default is worktree basename.
- No migration from legacy `projects/`.
- Keep `project_data_dir.dart` exported for legacy callers, but runtime must not use its default encoded path.
- Tests must use temporary directories and must not write under the real `$HOME/.nava`.

## Review Focus

- Launching from a git subdirectory must resolve to the repository root, not create a second project/worktree.
- Two clones/worktrees of one remote must share one `project` row but get two distinct data directories.
- A basename with spaces, Unicode, or a 12-hex collision must still produce a safe unique directory and never overwrite an existing one.
- A missing, corrupt, or unknown-schema `projects.db` must fail with the DB path, not silently recreate or lose project mapping.
- Explicit `baseDir`/`projectDir` and every test must not touch the real `$HOME/.nava` registry.

---

### Task 1: Project identity

**Files:**
- Create: `packages/conatus_code/lib/src/project/project_identity.dart`
- Create: `packages/conatus_code/test/project/project_identity_test.dart`

**Interfaces:**
- Produces:
```dart
class ProjectIdentity {
  const ProjectIdentity({
    required this.projectId,
    required this.worktreeId,
    required this.worktreePath,
    required this.name,
    this.vcs,
    this.remote,
  });

  final String projectId;      // 40 lowercase hex
  final String worktreeId;     // 40 lowercase hex
  final String worktreePath;   // canonical git top-level or canonical cwd
  final String name;           // basename of worktreePath
  final String? vcs;           // "git" or null
  final String? remote;        // normalized remote or null
}

ProjectIdentity resolveProjectIdentity(String workdir);
```

- [ ] **Step 1: Write failing identity tests**

Create `project_identity_test.dart` with helpers that create temp dirs and run git via `Process.runSync('git', args, workingDirectory: repo.path)`. Cover:
- non-git dir: `vcs == null`, both IDs are 40 hex, repeated calls are stable, `worktreePath` is canonical.
- git with remote: `name == basename(repo)`, `vcs == "git"`, `remote == "github.com/acme/lifts"`.
- two clones with the same remote: same `projectId`, different `worktreeId`, different `worktreePath`.
- git without remote: same root commit across a clone gives the same `projectId`.
- launching from `repo/subdir`: `worktreePath == repo.path`, not `subdir`.

Use exact assertions, for example:

```dart
expect(first.projectId, matches(RegExp(r'^[0-9a-f]{40}$')));
expect(a.projectId, b.projectId);
expect(a.worktreeId, isNot(b.worktreeId));
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd packages/conatus_code
dart test test/project/project_identity_test.dart
```

Expected: FAIL with `project_identity.dart` not found / `resolveProjectIdentity` undefined.

- [ ] **Step 3: Implement identity resolution**

Create `project_identity.dart`:
- canonicalize with `Directory(path).resolveSymbolicLinksSync()`, falling back to `Directory(path).absolute.path`.
- run git with argument lists, never a shell string:
  - `git -C <canonical> rev-parse --show-toplevel`
  - `git -C <root> config --get remote.origin.url`
  - `git -C <root> rev-list --max-parents=0 HEAD`
- normalize remote:
  - `https://host/path.git` → `host/path`
  - `ssh://git@host/path.git` → `host/path`
  - `git@host:path.git` → `host/path`
  - lowercase host, strip leading/trailing `/` and `.git`.
- derive:
  - remote present: `sha1("git-remote:$remote")`
  - no remote but root commit: `sha1("git-root:$rootCommit")`
  - otherwise: `sha1("directory:$canonical")`
- `worktreeId = sha1("worktree:$worktreePath")` using `crypto`'s `sha1`.
- if a git command fails or returns empty, fall through to the next identity source; never throw for non-git directories.
- `name = Directory(worktreePath).uri.pathSegments.last` (use `dart:io`; do not add a `path` dependency).

- [ ] **Step 4: Run tests to verify they pass**

```bash
dart test test/project/project_identity_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_code/lib/src/project/project_identity.dart \
        packages/conatus_code/test/project/project_identity_test.dart
git commit -m "feat(code): 项目身份哈希"
```

---

### Task 2: Workspace directory naming

**Files:**
- Create: `packages/conatus_code/lib/src/project/project_paths.dart`
- Create: `packages/conatus_code/test/project/project_paths_test.dart`

**Interfaces:**
- Produces:
```dart
String workspaceSlug(String basename);
String workspaceDirName(String basename, String worktreeId, {int hashLength = 12});
String workspacesRoot({Map<String, String>? env});
```
- `workspacesRoot` returns `"$NAVA_HOME/workspaces"` via the existing `resolveConfigDir(env: env)`.
- `workspaceDirName` always appends `-` and the first `hashLength` hex characters.

- [ ] **Step 1: Write failing path tests**

Cover:
- `workspaceSlug('lifts') == 'lifts'`
- `workspaceSlug('my project') == 'my-project'`
- Unicode is preserved: `workspaceSlug('工作区') == '工作区'`
- unsafe characters collapse: `workspaceSlug('a/b:c*') == 'a-b-c'`
- empty/only punctuation falls back to `workspace`
- slug is capped at 32 characters
- `workspaceDirName('lifts', '3f9a2c1b7d4e0000') == 'lifts-3f9a2c1b7d4e'`
- `hashLength: 16` uses 16 characters
- `workspacesRoot(env: {'HOME': temp})` ends with `/.nava/workspaces`

- [ ] **Step 2: Run tests to verify they fail**

```bash
dart test test/project/project_paths_test.dart
```

Expected: FAIL with missing `project_paths.dart`.

- [ ] **Step 3: Implement path helpers**

Use a Unicode-aware regex:

```dart
RegExp(r'[^\p{L}\p{N}._-]+', unicode: true)
```

Collapse repeated `-`, trim `-`, cap by runes to 32, and fall back to `workspace`. Do not lower-case Unicode names; preserve the user's basename.

- [ ] **Step 4: Run tests to verify they pass**

```bash
dart test test/project/project_paths_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_code/lib/src/project/project_paths.dart \
        packages/conatus_code/test/project/project_paths_test.dart
git commit -m "feat(code): 工作区目录命名"
```

---

### Task 3: SQLite project database

**Files:**
- Modify: `packages/conatus_code/pubspec.yaml`
- Create: `packages/conatus_code/lib/src/project/project_database.dart`
- Create: `packages/conatus_code/test/project/project_database_test.dart`

**Interfaces:**
- Produces:
```dart
class ProjectRecord {
  final String id;
  final String name;
  final String? vcs;
  final String? remote;
}

class WorktreeRecord {
  final String id;
  final String projectId;
  final String path;
  final String name;
  final String dirName;
}

class ProjectDatabase {
  ProjectDatabase.open(String path);
  ProjectRecord? project(String id);
  WorktreeRecord? worktree(String id);
  WorktreeRecord? worktreeAt(String path);
  WorktreeRecord? worktreeByDirName(String dirName);
  void saveProject({required String id, required String name, String? vcs, String? remote});
  void saveWorktree({required String id, required String projectId, required String path, required String name, required String dirName});
  void renameProject(String id, String name);
  void close();
}
```

- [ ] **Step 1: Add dependency**

```bash
cd packages/conatus_code
dart pub add sqlite3:^2.9.0
```

- [ ] **Step 2: Write failing database tests**

Use a temp DB path. Cover:
- opening a missing path creates the `project` and `worktree` tables and sets `PRAGMA user_version = 1`
- save/read round-trips project and worktree records
- duplicate `worktree.path` / `dir_name` keeps uniqueness (second insert/upsert updates rather than duplicates)
- `renameProject` changes only `name`
- reopening the same DB preserves records
- a file containing `not a database` throws an exception whose message contains the DB path
- closing is idempotent

Exact assertions include:

```dart
expect(db.project('p1')!.name, 'lifts');
expect(db.worktreeAt('/tmp/lifts')!.dirName, 'lifts-3f9a2c1b7d4e');
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
dart test test/project/project_database_test.dart
```

- [ ] **Step 4: Implement schema and accessors**

Use `sqlite3.open(path)`, then:

```sql
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 5000;
```

Create schema version 1 exactly as the spec. If `user_version` is `0` and `sqlite_master` is empty, create tables and set `1`; if it is any other value, throw `StateError` containing the DB path. `PRAGMA journal_mode` may return a row; ignore it.

Use `Process.runSync('chmod', ['600', path])` on non-Windows after creation, ignoring failure. Wrap inserts/upserts in `BEGIN IMMEDIATE` / `COMMIT`; on conflict update the `time_updated` field and preserve `project.name` unless the caller explicitly renames.

- [ ] **Step 5: Run tests and compile smoke test**

```bash
dart test test/project/project_database_test.dart
dart compile exe bin/conatus_code.dart -o /tmp/nava-sqlite-smoke
```

Expected: tests pass; compilation succeeds with system SQLite. Delete `/tmp/nava-sqlite-smoke` afterward.

- [ ] **Step 6: Commit**

```bash
git add packages/conatus_code/pubspec.yaml packages/conatus_code/pubspec.lock \
        packages/conatus_code/lib/src/project/project_database.dart \
        packages/conatus_code/test/project/project_database_test.dart
git commit -m "feat(code): SQLite 项目注册表"
```

Note: if the workspace resolves `pubspec.lock` at the repository root instead, stage the actual lockfile changed by `dart pub add`.

---

### Task 4: Registry resolve and rename

**Files:**
- Create: `packages/conatus_code/lib/src/project/project_registry.dart`
- Create: `packages/conatus_code/test/project/project_registry_test.dart`

**Interfaces:**
- Consumes: `resolveProjectIdentity`, `workspaceSlug`, `workspaceDirName`, `ProjectDatabase`.
- Produces:
```dart
class WorkspaceInfo {
  const WorkspaceInfo({
    required this.projectId,
    required this.projectName,
    required this.worktreeId,
    required this.worktreePath,
    required this.dataDir,
  });

  final String projectId;
  final String projectName;
  final String worktreeId;
  final String worktreePath;
  final String dataDir;

  String get projectShortId => projectId.substring(0, 8);
}

class ProjectRegistry {
  ProjectRegistry({required ProjectDatabase database, required String workspacesDir});
  factory ProjectRegistry.open({String? dbPath, String? workspacesDir, Map<String, String>? env});
  WorkspaceInfo resolve(String workdir, {String? dataDirOverride});
  WorkspaceInfo? info(String projectId);
  void rename(String projectId, String name);
  void close();
}
```

- `ProjectRegistry.open` defaults `dbPath` to `$NAVA_HOME/projects.db` and `workspacesDir` to `$NAVA_HOME/workspaces`.
- `resolve` is synchronous and idempotent.

- [ ] **Step 1: Write failing registry tests**

Cover:
- non-git temp dir: resolve creates DB, one project row, one worktree row, and `workspaces/<slug>-<hash>`.
- resolve the same dir twice: same `dataDir`, one row, directory not recreated.
- two worktrees with same remote: same `projectId`, different `worktreeId`, different `dataDir`; both directory names exist.
- a second worktree with the same basename still gets a distinct directory (hash suffix).
- `rename` persists and survives a registry close/reopen; resolving again does not overwrite the custom name.
- `dataDirOverride` returns that exact directory while still creating the worktree row.
- a pre-existing row with a 12-hex `dir_name` forces the next collision to a 16-hex name.
- invalid/corrupt DB bubbles an error containing the path.

Use a temporary `NAVA_HOME` for `ProjectRegistry.open` tests; pass explicit `dbPath`/`workspacesDir` where simpler.

- [ ] **Step 2: Run tests to verify they fail**

```bash
dart test test/project/project_registry_test.dart
```

- [ ] **Step 3: Implement registry**

Resolve flow:
1. `resolveProjectIdentity(workdir)`.
2. Look up worktree by path.
3. If existing, reuse `dirName`; else allocate `workspaceDirName(name, worktreeId, hashLength: 12)` and extend to 16/20/40 while `database.worktreeByDirName(candidate) != null`.
4. Save project with default name only when absent; update `vcs`/`remote` on every resolve.
5. Save worktree with `path`, `name`, `dirName`.
6. `dataDir = dataDirOverride ?? '$workspacesDir/$dirName'`.
7. Create `dataDir` recursively and chmod `0700` on non-Windows.
8. Return `WorkspaceInfo` with the stored project name.

`rename` trims, rejects empty, longer than 80, or control characters (`RegExp(r'[\x00-\x1F\x7F]')`), then updates the row.

- [ ] **Step 4: Run tests to verify they pass**

```bash
dart test test/project/project_registry_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_code/lib/src/project/project_registry.dart \
        packages/conatus_code/test/project/project_registry_test.dart
git commit -m "feat(code): 项目注册表解析与重命名"
```

---

### Task 5: Runtime and CLI integration

**Files:**
- Modify: `packages/conatus_code/lib/src/tui/tui_app.dart:142-240, 725-770`
- Modify: `packages/conatus_code/bin/conatus_code.dart:90-160`
- Modify: `packages/conatus_code/lib/src/tui/tui_controller.dart:2517-2528`
- Modify: `packages/conatus_code/lib/conatus_code.dart` (export new project APIs)
- Create: `packages/conatus_code/test/tui/tui_app_project_test.dart`
- Modify: `packages/conatus_code/test/tui/export_command_test.dart`

**Interfaces:**
- `ConatusTuiRuntime.create` gains:
```dart
ProjectRegistry? projectRegistry,
String? projectDir,
```
- Runtime provides:
```dart
app.provide('projectDataDir', resolvedBaseDir);
app.provide('projectInfo', workspaceInfo);       // WorkspaceInfo? only when registry used
app.provide('projectRegistry', registry);        // ProjectRegistry? only when registry used
```
- `ProjectRegistry` owns its DB and is closed via `app.onDispose`.

- [ ] **Step 1: Write failing runtime tests**

`tui_app_project_test.dart`:
- create a temp `ProjectRegistry` and temp workdir; call `ConatusTuiRuntime.create(projectRegistry: registry, workdir: workdir, interactive: false)`; assert `app.get<String>('projectDataDir')` equals `registry.resolve(workdir).dataDir` and `app.get<WorkspaceInfo>('projectInfo')!.projectName` is the basename.
- call with `baseDir: tempDir`; assert no DB was created in the temp registry and `projectInfo` is null.
- call with `projectDir: tempData` plus registry; assert data goes to override and registry contains the worktree.

Update `export_command_test.dart` so its `newApp` uses `baseDir: dir.path` or an injected temp registry; after running, assert no new entries under a sentinel real-home-like directory.

- [ ] **Step 2: Run tests to verify they fail**

```bash
dart test test/tui/tui_app_project_test.dart test/tui/export_command_test.dart
```

Expected: FAIL because `projectRegistry`/`projectDir` parameters and services do not exist.

- [ ] **Step 3: Integrate runtime resolution**

In `ConatusTuiRuntime.create`:
- keep `baseDir` as the explicit bypass;
- if `baseDir != null`: use it, no registry;
- else: `registry = projectRegistry ?? ProjectRegistry.open()`;
  `info = registry.resolve(resolvedWorkdir, dataDirOverride: projectDir)`;
  `resolvedBaseDir = info.dataDir`;
- provide services after `app.provide('workdir', ...)`;
- add `app.onDispose(registry.close)` when a registry is used.
- update the constructor doc comment to describe the new default.
- update `_projectDataDir()` in the controller to prefer `app.get<String>('projectDataDir')`, then fall back to the old resolver for callers that do not provide it.

- [ ] **Step 4: Integrate the CLI**

In `bin/conatus_code.dart`:
- open a `ProjectRegistry` once before `--continue` resolution;
- resolve `(workdir, dataDirOverride: config.agent.projectDir)` to get `projectDataDir`;
- keep the existing `.opencode` protection warning;
- pass `projectRegistry` and `projectDir: config.agent.projectDir` to `ConatusTuiRuntime.create`;
- do not pass `baseDir` in the normal path;
- on registry errors, print the path/message and exit 2.

- [ ] **Step 5: Run tests and analyze**

```bash
dart test test/tui/tui_app_project_test.dart test/tui/export_command_test.dart
dart analyze
```

- [ ] **Step 6: Commit**

```bash
git add packages/conatus_code/bin/conatus_code.dart \
        packages/conatus_code/lib/src/tui/tui_app.dart \
        packages/conatus_code/lib/src/tui/tui_controller.dart \
        packages/conatus_code/lib/conatus_code.dart \
        packages/conatus_code/test/tui/tui_app_project_test.dart \
        packages/conatus_code/test/tui/export_command_test.dart
git commit -m "feat(code): 启动时解析项目注册表"
```

---

### Task 6: `/project` command

**Files:**
- Modify: `packages/conatus_code/lib/src/tui/tui_commands.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_controller.dart`
- Create: `packages/conatus_code/test/tui/tui_project_command_test.dart`

**Interfaces:**
- Consumes `WorkspaceInfo` and `ProjectRegistry` services from Task 5.
- Adds command `project` with description `查看/重命名当前项目`.
- `/project` prints:
```text
项目：<name>
ID：<projectShortId>
worktree：<worktreePath>
数据目录：<dataDir>
```
- `/project rename <名字>` validates through `ProjectRegistry.rename` and prints the new name.
- Without a registry: `项目注册表未启用。`

- [ ] **Step 1: Write failing command tests**

Build a controller test app with:
- `app.provide('projectInfo', WorkspaceInfo(...))`
- `app.provide('projectRegistry', fake/real registry)`
- `app.provide('projectDataDir', temp)`

Cover:
- `/project` output contains name, short id, worktree, data dir.
- `/project rename 新名字` updates the registry and prints success.
- empty name, 81-character name, and name containing `\n` are rejected with a message; registry unchanged.
- `/project` without services prints `项目注册表未启用。`.

- [ ] **Step 2: Run tests to verify they fail**

```bash
dart test test/tui/tui_project_command_test.dart
```

- [ ] **Step 3: Add command and dispatch**

Add the `TuiCommand` entry. In `_handleCommand`, add `case 'project':` and call a helper:
```dart
Future<void> _handleProjectCommand(String arg) async
```
Parse `rename` as the first word; the remainder is the new name. Use `_app.get<WorkspaceInfo>('projectInfo')` and `_app.get<ProjectRegistry>('projectRegistry')`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
dart test test/tui/tui_project_command_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_code/lib/src/tui/tui_commands.dart \
        packages/conatus_code/lib/src/tui/tui_controller.dart \
        packages/conatus_code/test/tui/tui_project_command_test.dart
git commit -m "feat(code): /project 查看与重命名"
```

---

### Task 7: Documentation, legacy cleanup, full verification

**Files:**
- Modify: `packages/conatus_code/README.md`
- Modify: `packages/conatus_code/CHANGELOG.md`
- Modify: `packages/conatus_code/test/config/project_data_dir_test.dart` (adjust legacy expectations/comments)
- Modify: `packages/conatus_code/test/tui/session_exporter_test.dart` comments if they still mention encoded defaults

- [ ] **Step 1: Update docs**

README:
- replace default `~/.nava/projects/<编码工作区路径>` references with `~/.nava/workspaces/<basename>-<hash>/`;
- document `~/.nava/projects.db`, `workspaces/`, `/project`, `/project rename`;
- document that old `projects/` is not migrated and can be deleted;
- document SQLite system-library requirement and the Windows caveat.

CHANGELOG: add a `[未发布]` bullet for the new registry/layout and no-migration policy.

- [ ] **Step 2: Update legacy tests/comments**

Keep `resolveProjectDataDir` tests as legacy-helper tests, or rename them to make clear they do not describe runtime defaults. Remove comments claiming the runtime uses the encoded path.

- [ ] **Step 3: Run full verification**

```bash
cd /Users/fitz/REPO/conatus/packages/conatus_code
dart analyze
dart test
bash tool/build_binary.sh
```

Expected: analyze clean, all tests pass, binary rebuilt.

- [ ] **Step 4: Manual smoke test**

In a temp git repo with a temp `NAVA_HOME`, start `nava` headless or interactive once, then verify:
- `$NAVA_HOME/projects.db` exists and has one project/worktree row;
- `$NAVA_HOME/workspaces/<name>-<hash>/sessions` exists;
- `$NAVA_HOME/projects/` was not created;
- `/project` shows the name and `/project rename` persists.

- [ ] **Step 5: Commit and push**

```bash
git add packages/conatus_code/README.md packages/conatus_code/CHANGELOG.md \
        packages/conatus_code/test/config/project_data_dir_test.dart \
        packages/conatus_code/test/tui/session_exporter_test.dart
git commit -m "docs(code): 项目注册表与工作区目录"
git push origin master
```

Then update the parent repo gitlink and push:
```bash
cd /Users/fitz/REPO/conatus
git add packages/conatus_code
git commit -m "chore(code): 同步子模块 gitlink（项目注册表）"
git push origin master
```

---

## Final Verification

- [ ] `dart analyze` in `packages/conatus_code` is clean.
- [ ] `dart test` in `packages/conatus_code` passes.
- [ ] Root `dart analyze` and root `dart test` still pass.
- [ ] `bash tool/build_binary.sh` succeeds with `sqlite3` 2.x.
- [ ] A temp `NAVA_HOME` run creates `projects.db` and `workspaces/<slug>-<hash>/`, and never creates `projects/`.
- [ ] Two worktrees of one remote share a project row and have distinct data directories.
- [ ] `/project rename` survives a restart and does not rename the directory.
