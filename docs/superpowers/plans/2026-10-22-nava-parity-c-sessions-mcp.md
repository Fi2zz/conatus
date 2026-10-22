# nava 日常体验对齐 OpenCode V2 — C 组（会话与生态）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现会话 title/rename/delete/tabs，以及 MCP 的 resources/prompts/OAuth/CLI 补全。

**Architecture:** 会话标题用 append-only 的 `session/title` 事件，不改持久化端口；picker 与 tab 都从事件派生。Tabs 是视图态单活：只切换会话与滚动位置，不并发跑多个 AgentLoop。MCP 先补协议与注册表，再补 OAuth 与 CLI；所有 token 与配置只写 `~/.nava`。

**Tech Stack:** Dart 3.11+、`package:test`、`nocterm`、`dart:io` HttpServer（OAuth 回调）、现有 `http` 包（经 `conatus_mcp`）。

**Spec:** `docs/superpowers/specs/2026-10-22-nava-opencode-daily-parity-design.md`

## Global Constraints

- `.opencode` / `~/.config/opencode` **严格只读**；MCP 的 `add/auth/logout` 只写 `~/.nava/config.toml` 与 `~/.nava/oauth/`。
- 会话/checkpoint/story-log 只写项目数据目录；不写 OpenCode 目录。
- 所有新增配置可选；缺省行为与当前一致。
- 单文件 ≤ 200 行、单 class ≤ 150 行、函数体 ≤ 40 行、参数 ≤ 4 个。
- 每个任务跑目标测试 + `dart analyze --fatal-infos`；提交用 Conventional Commits。
- OAuth 日志只输出键名，不输出 token/secret。

## Review Focus

1. **旧会话文件没有 title**：必须惰性派生（首条用户消息前 40 字符），不能报错、不能回写旧文件。
2. **删除会话的副作用**：删 JSONL + checkpoint；story-log 存在时一并删；当前会话拒绝删除。
3. **tabs 切换时 busy**：必须提示并拒绝切换，不能丢掉正在跑的轮次。
4. **MCP server 不支持 resources/prompts**：能力协商后静默跳过，不能把整个 server 标记失败。
5. **OAuth 失败/超时/用户取消**：必须回到 `needs_auth` 状态，不阻塞其他 MCP server，不泄露 token。

---

### Task 1: 会话标题事件与 API

**Files:**
- Modify: `packages/conatus_foundation/lib/src/session_types.dart`
- Modify: `packages/conatus_foundation/lib/src/session.dart`
- Modify: `packages/conatus_foundation/lib/conatus_foundation.dart`（导出常量）
- Test: `packages/conatus_foundation/test/session_title_test.dart`

**Interfaces:**
- `const String kSessionTitleEvent = 'session/title';`
- `String? get Session.title`：取最后一个 `session/title` 事件的 `data['title']`；没有返回 `null`。
- `void Session.rename(String title)`：trim、截断 80 字符、空串抛 `ArgumentError`；`append(kSessionTitleEvent, data: {'title': value})`。
- 旧会话无事件 → `title == null`，不写回。

- [ ] **Step 1: Write the failing test**

```dart
test('rename appends a title event and getter returns latest', () {
  final session = Session(id: 's1');
  expect(session.title, isNull);
  session.rename('Auth cleanup');
  expect(session.title, 'Auth cleanup');
  session.rename('Second title');
  expect(session.title, 'Second title');
  expect(session.events.where((e) => e.type == kSessionTitleEvent).length, 2);
});

test('empty title is rejected and long title is truncated', () {
  final session = Session(id: 's1');
  expect(() => session.rename('  '), throwsArgumentError);
  session.rename('x' * 100);
  expect(session.title!.length, 80);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd packages/conatus_foundation && dart test test/session_title_test.dart`
Expected: FAIL — `kSessionTitleEvent` / `Session.title` not defined.

- [ ] **Step 3: Implement**

在 `session_types.dart` 加常量；在 `Session` 加 getter 与 `rename`。标题事件参与 `events` / `ownEvents` / fork 前缀；`SessionStore` 无需改动（append-only 已持久化）。

- [ ] **Step 4: Run test to verify it passes**

Run: `cd packages/conatus_foundation && dart test test/session_title_test.dart test/session_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_foundation/lib/src/session_types.dart packages/conatus_foundation/lib/src/session.dart packages/conatus_foundation/lib/conatus_foundation.dart packages/conatus_foundation/test/session_title_test.dart
git commit -m "feat(foundation): 会话支持 append-only 标题事件"
```

---

### Task 2: `/rename`、picker 标题与删除

**Files:**
- Create: `packages/conatus_code/lib/src/tui/tui_rename_view.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_session_picker.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_session_picker_view.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_controller.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_commands.dart`
- Modify: `packages/conatus_code/lib/src/checkpoint/checkpoint_manager.dart`（`clearSession`）
- Modify: `packages/conatus_foundation/lib/src/session_log.dart`（`remove`）
- Test: `packages/conatus_code/test/tui/tui_rename_delete_test.dart`
- Test: `packages/conatus_code/test/tui/tui_session_picker_test.dart`

**Interfaces:**
- `class TuiRenamePrompt { bool open; String? targetId; String text; void show(String id, String? current); void close(); }`
- `TuiSessionInfo` 增加 `String? title`；无 title 时派生首条 `user/message` 前 40 字符。
- 控制器：`Future<bool> renameSession(String id, String title)`、`Future<bool> deleteSession(String id)`。
- `CheckpointManager.clearSession(String sessionId)` → `store.clearSession`（经 `_chain`）。
- `SessionLog.remove(String sessionId)`（存在才删，返回 bool）。

- [ ] **Step 1: Write the failing tests**

```dart
test('/rename updates current session title', () async {
  await controller.handleLine('/rename Auth cleanup');
  expect(controller.transcript.messages.last.text, contains('Auth cleanup'));
  expect(controller.session!.title, 'Auth cleanup');
});

test('delete removes session jsonl and checkpoints but refuses current', () async {
  expect(await controller.deleteSession(controller.sessionId), isFalse);
  expect(await controller.deleteSession(otherId), isTrue);
  expect(File('$sessionsDir/$otherId.jsonl').existsSync(), isFalse);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/conatus_code && dart test test/tui/tui_rename_delete_test.dart`
Expected: FAIL — `/rename` unknown / `deleteSession` not defined.

- [ ] **Step 3: Implement**

- `/rename [title]`：无参数且当前会话有 title 时，打开 `TuiRenamePrompt` 预填；有参数直接改。
- picker：`r` 打开 rename prompt，`d` 用 `TuiChoicePrompt` 二次确认后删除；列表显示 title + 短 id + 更新时间。
- `deleteSession`：当前会话拒绝；`_sessions.remove(id)`；`checkpointManager.clearSession(id)`；若 story-log 启用，`SessionLog.remove(id)`；删除后刷新 picker。
- 旧会话无 title：picker 读取时用 `SessionStore.open(id)`（不 attach 持久化）派生首条用户消息；不写回。
- `.opencode` 不参与。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_code && dart test test/tui/tui_rename_delete_test.dart test/tui/tui_session_picker_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_code/lib/src/tui packages/conatus_code/lib/src/checkpoint/checkpoint_manager.dart packages/conatus_foundation/lib/src/session_log.dart packages/conatus_code/test/tui/tui_rename_delete_test.dart packages/conatus_code/test/tui/tui_session_picker_test.dart
git commit -m "feat(code): 会话重命名、删除与标题展示"
```

---

### Task 3: 会话 tabs（视图态单活）

**Files:**
- Create: `packages/conatus_code/lib/src/tabs/tab_manager.dart`
- Create: `packages/conatus_code/lib/src/tabs/tab_bar.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_controller.dart`
- Test: `packages/conatus_code/test/tabs/tab_manager_test.dart`
- Test: `packages/conatus_code/test/tui/tui_tabs_test.dart`

**Interfaces:**
- Consumes: C Task 2 会话标题/删除；B Task 8 `Keymap` 的 `tab.next` / `tab.previous`。
- `class SessionTab { final String sessionId; String title; double scrollOffset; }`
- `class TabManager { List<SessionTab> get tabs; int get active; bool get canAdd; void open(String sessionId, {String? title}); void close(int index); void activate(int index); void saveScroll(double offset); double restoreScroll(); }`
- 控制器 `Future<bool> switchSession(String id)`（返回 false 表示 busy）。
- `TabBar` 渲染 title、active 标记、`+` 提示；最多 8 个。

- [ ] **Step 1: Write the failing test**

```dart
test('tabs keep scroll offsets per session', () {
  final tabs = TabManager();
  tabs.open('s1'); tabs.saveScroll(120);
  tabs.open('s2'); tabs.saveScroll(40);
  tabs.activate(0);
  expect(tabs.restoreScroll(), 120);
});

test('busy session refuses tab switch', () async {
  controller.busy = true;
  expect(await controller.switchSession('s2'), isFalse);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/conatus_code && dart test test/tabs test/tui/tui_tabs_test.dart`
Expected: FAIL — `TabManager` not defined.

- [ ] **Step 3: Implement**

- `switchSession` 加 busy 检查；返回 `bool`；更新 `_sessionId`、`_bind`、`onChanged`。
- `TabManager` 只保存 `sessionId/title/scrollOffset`；`AgentTui` 在切换前 `_scroll.offset` 存入当前 tab，切换成功后 `jumpTo` 目标 offset。
- `tab.close` 只移出 tab，不删会话；`tab.reopen` 最近关闭的会话（stretch：先不做）。
- 快捷键走 B 组 Keymap：`tab.next` / `tab.previous`；默认 `ctrl+tab` / `ctrl+shift+tab`。
- 新建 tab 用 `/new` 或 `+` 提示，不自动切换正在跑的会话。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_code && dart test test/tabs test/tui/tui_tabs_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_code/lib/src/tabs packages/conatus_code/lib/src/tui packages/conatus_code/test/tabs packages/conatus_code/test/tui/tui_tabs_test.dart
git commit -m "feat(code): 增加会话 tabs 与滚动位置恢复"
```

---

### Task 4: MCP 协议层 resources / prompts

**Files:**
- Create: `packages/conatus_mcp/lib/src/mcp_resource_types.dart`
- Create: `packages/conatus_mcp/lib/src/mcp_prompt_types.dart`
- Modify: `packages/conatus_mcp/lib/src/mcp_types.dart`（capabilities 解析）
- Modify: `packages/conatus_mcp/lib/src/mcp_protocol.dart`
- Modify: `packages/conatus_mcp/lib/src/mcp_client.dart`
- Modify: `packages/conatus_mcp/lib/conatus_mcp.dart`
- Test: `packages/conatus_mcp/test/mcp_resources_test.dart`
- Test: `packages/conatus_mcp/test/mcp_prompts_test.dart`

**Interfaces:**
- `class McpCapabilities { final bool tools, resources, prompts; }`
- `class McpResource { final String uri, name; final String? description, mimeType; }`
- `class McpResourceTemplate { final String uriTemplate, name; final String? description, mimeType; }`
- `class McpResourceContents { final String uri; final String? mimeType, text, blob; }`
- `class McpPrompt { final String name; final String? description; final List<McpPromptArgument> arguments; }`
- `class McpPromptArgument { final String name; final String? description; final bool required; }`
- `class McpPromptMessage { final String role; final String text; }`
- `McpClient`:
  - `Future<List<McpResource>> listResources()`
  - `Future<List<McpResourceTemplate>> listResourceTemplates()`
  - `Future<List<McpResourceContents>> readResource(String uri)`
  - `Future<List<McpPrompt>> listPrompts()`
  - `Future<List<McpPromptMessage>> getPrompt(String name, {Map<String, String> arguments = const {}})`

- [ ] **Step 1: Write the failing tests**

```dart
test('lists paginated resources', () async {
  transport.autoRespond = (request) => switch (request.method) {
    'resources/list' => {'resources': [
      {'uri': 'file:///a', 'name': 'a'},
    ]},
    _ => null,
  };
  expect((await client.listResources()).single.uri, 'file:///a');
});

test('gets prompt with arguments', () async {
  transport.autoRespond = (request) => switch (request.method) {
    'prompts/get' => {'messages': [
      {'role': 'user', 'content': {'type': 'text', 'text': 'Review a'}},
    ]},
    _ => null,
  };
  final messages = await client.getPrompt('review', arguments: {'path': 'a'});
  expect(messages.single.role, 'user');
  expect(messages.single.text, 'Review a');
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/conatus_mcp && dart test test/mcp_resources_test.dart test/mcp_prompts_test.dart`
Expected: FAIL — methods not defined.

- [ ] **Step 3: Implement**

- 复用 `tools/list` 的 cursor 分页（max 20 页）；新增 `resources/list`、`resources/templates/list`、`resources/read`、`prompts/list`、`prompts/get`。
- `McpServerInfo.capabilities` 解析成 `McpCapabilities`；未知/缺失按 false。
- content 支持 `text` / `blob`；prompt messages 的 content 只取 text，非 text 渲染为 `[mimeType]`。
- 服务端不支持某方法（JSON-RPC `-32601`）时返回空列表，不抛断连。
- 更新 `mcp_test_support.dart` 的 `fakeServerReply` 覆盖新方法。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_mcp && dart test -x integration`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_mcp/lib/src packages/conatus_mcp/lib/conatus_mcp.dart packages/conatus_mcp/test
git commit -m "feat(mcp): 支持 resources 与 prompts 协议"
```

---

### Task 5: MCP 注册表、内置工具与 prompt 命令

**Files:**
- Modify: `packages/conatus_mcp/lib/src/mcp_registry.dart`
- Create: `packages/conatus_mcp/lib/src/mcp_resource_tools.dart`
- Create: `packages/conatus_code/lib/src/mcp/mcp_prompt_commands.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_app.dart`
- Test: `packages/conatus_mcp/test/mcp_registry_resources_test.dart`
- Test: `packages/conatus_code/test/mcp/mcp_prompt_commands_test.dart`

**Interfaces:**
- Consumes: C Task 4 MCP client；B Task 2 `CommandDefinition.executor`。
- `McpRegistry`:
  - `Future<List<McpResource>> listResources({String? server})`
  - `Future<List<McpResourceContents>> readResource({required String server, required String uri})`
  - `Future<List<McpPrompt>> listPrompts({String? server})`
  - `Future<List<McpPromptMessage>> getPrompt({required String server, required String name, Map<String, String> arguments = const {}})`
- 工具：`list_mcp_resources`（可选 `server`）、`read_mcp_resource`（`server` + `uri`），`ToolRisk.low`。
- prompt 命令：`/<server>:<prompt>`，`CommandDefinition.executor` 调 `getPrompt` 并把 messages 拼成文本提交。

- [ ] **Step 1: Write the failing tests**

```dart
test('registry aggregates resources across servers', () async {
  final resources = await registry.listResources();
  expect(resources.map((r) => r.uri), containsAll(['file:///a', 'file:///b']));
});

test('prompt command maps to /server:name', () async {
  final commands = await loadMcpPromptCommands(registry);
  expect(commands.any((c) => c.name == 'docs:review'), isTrue);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/conatus_mcp && dart test test/mcp_registry_resources_test.dart`
Run: `cd packages/conatus_code && dart test test/mcp/mcp_prompt_commands_test.dart`
Expected: FAIL — methods not defined.

- [ ] **Step 3: Implement**

- registry 对每个 server 调对应 client；单台失败返回空并不影响其他 server。
- 工具注册在 `provideMcpResourceTools`；`read_mcp_resource` 的结果按 MIME 输出文本或 `[binary N bytes]`，单条上限 64 KiB。
- prompt 命令在装配时从 `listPrompts` 生成 `CommandDefinition(name: '<server>:<prompt>', executor: ...)`；参数按顺序从 `$1..` 填，缺省为空；messages 渲染为 `role: text` 段落。
- `.opencode` 不参与。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_mcp && dart test -x integration`
Run: `cd packages/conatus_code && dart test test/mcp`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_mcp/lib/src packages/conatus_code/lib/src/mcp packages/conatus_code/lib/src/tui/tui_app.dart packages/conatus_mcp/test packages/conatus_code/test/mcp
git commit -m "feat(mcp): 资源工具与 prompt 命令"
```

---

### Task 6: MCP OAuth 发现、PKCE 与动态注册

**Files:**
- Create: `packages/conatus_mcp/lib/src/mcp_oauth_types.dart`
- Create: `packages/conatus_mcp/lib/src/mcp_oauth_discovery.dart`
- Create: `packages/conatus_mcp/lib/src/mcp_oauth_pkce.dart`
- Modify: `packages/conatus_mcp/pubspec.yaml`（新增 `crypto`，SHA-256）
- Modify: `packages/conatus_code/lib/src/config/config_schema.dart`
- Modify: `packages/conatus_code/lib/src/config/config_parser.dart`
- Test: `packages/conatus_mcp/test/mcp_oauth_discovery_test.dart`
- Test: `packages/conatus_mcp/test/mcp_oauth_pkce_test.dart`

**Interfaces:**
- `class McpOAuthConfig { final bool enabled; final String? clientId, clientSecret, scope; final int? callbackPort; }`；`McpServerSpec.oauth`
- `class McpAuthServerMetadata { final Uri authorizationEndpoint, tokenEndpoint; final Uri? registrationEndpoint; final List<String> scopesSupported; }`
- `Future<McpAuthServerMetadata> discoverAuthServer(Uri serverUrl, {http.Client? client})`
- `class PkcePair { final String verifier, challenge; }` + `PkcePair generatePkce()`
- `Future<String> registerOAuthClient(McpAuthServerMetadata meta, Uri redirectUri, {http.Client? client})`

- [ ] **Step 1: Write the failing tests**

```dart
test('discovers protected resource and auth server metadata', () async {
  final server = await _fakeAs();
  final meta = await discoverAuthServer(Uri.parse('http://127.0.0.1:${server.port}/mcp'));
  expect(meta.tokenEndpoint.path, '/token');
});

test('pkce challenge is S256 of verifier', () {
  final pair = generatePkce();
  expect(pair.challenge, base64Url.encode(sha256.convert(utf8.encode(pair.verifier)).bytes).replaceAll('=', ''));
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/conatus_mcp && dart test test/mcp_oauth_discovery_test.dart test/mcp_oauth_pkce_test.dart`
Expected: FAIL — `discoverAuthServer` not defined.

- [ ] **Step 3: Implement**

- 发现：`<origin>/.well-known/oauth-protected-resource` → `authorization_servers[0]` → `.well-known/oauth-authorization-server`；失败再读 401 `WWW-Authenticate` 的 `resource_metadata`。
- PKCE：`Random.secure()` 32 字节 verifier；challenge = base64url(sha256(verifier)) 去 `=`。
- DCR：`registration_endpoint` 非空时 POST，`token_endpoint_auth_method: none`，`grant_types: [authorization_code, refresh_token]`，`redirect_uris: [redirectUri]`；返回 `client_id`。为空时必须由配置提供 `client_id`，否则报 `oauth-no-client`。
- 配置：`oauth = false` 关闭；`[mcp.servers.x.oauth]` 表支持 `client_id/client_secret/scope/callback_port`。
- 测试用本地 `HttpServer` 假 AS，不访问外网。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_mcp && dart test test/mcp_oauth_discovery_test.dart test/mcp_oauth_pkce_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_mcp/lib/src packages/conatus_code/lib/src/config packages/conatus_mcp/test
git commit -m "feat(mcp): OAuth 发现、PKCE 与动态客户端注册"
```

---

### Task 7: OAuth token 存储、回调与传输鉴权

**Files:**
- Create: `packages/conatus_mcp/lib/src/mcp_oauth_store.dart`
- Create: `packages/conatus_mcp/lib/src/mcp_oauth_session.dart`
- Modify: `packages/conatus_mcp/lib/src/mcp_transport_base.dart`
- Modify: `packages/conatus_code/lib/src/mcp/mcp_assembly.dart`
- Test: `packages/conatus_mcp/test/mcp_oauth_store_test.dart`
- Test: `packages/conatus_mcp/test/mcp_oauth_session_test.dart`

**Interfaces:**
- `class McpOAuthToken { final String accessToken; final String? refreshToken; final DateTime? expiresAt; final String? scope; }`
- `class McpOAuthStore { McpOAuthStore(String dir); Future<McpOAuthToken?> load(String server); Future<void> save(String server, McpOAuthToken token); Future<void> remove(String server); }`
- `class McpOAuthSession { Future<McpOAuthToken> authorize({required Uri serverUrl, required McpOAuthConfig config}); Future<McpOAuthToken> refresh(McpOAuthToken token); }`
- `HttpTransport` 新增 `Future<Map<String,String>> Function()? authHeaders`；401 时刷新一次并重试。

- [ ] **Step 1: Write the failing tests**

```dart
test('token store writes 0600 and round-trips', () async {
  await store.save('docs', const McpOAuthToken(accessToken: 'a', refreshToken: 'r'));
  final token = await store.load('docs');
  expect(token!.accessToken, 'a');
  expect(File('${dir.path}/docs.json').statSync().mode & 0x1FF, 0x180);
});

test('401 triggers one refresh and retry', () async {
  // fake 401 then 200; assert Authorization header changed
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/conatus_mcp && dart test test/mcp_oauth_store_test.dart test/mcp_oauth_session_test.dart`
Expected: FAIL — `McpOAuthStore` not defined.

- [ ] **Step 3: Implement**

- 授权：loopback `HttpServer.bind(127.0.0.1, 0)`；构造 `redirect_uri`；打印/打开授权 URL（注入 `openUrl` 便于测试）；回调取 `code`/`state`；POST token 端点。
- 刷新：`grant_type=refresh_token`；过期前 60 秒主动刷新；失败标 `needs_auth`。
- 存储：`~/.nava/oauth/<server 安全化>.json`，0600，原子写；保存 access/refresh/expiry。
- 传输：`authHeaders` 合并 `Authorization: Bearer ...`；401 时刷新一次，仍失败返回 `needs_auth`。
- 日志只输出 server 名与错误码。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_mcp && dart test test/mcp_oauth_store_test.dart test/mcp_oauth_session_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_mcp/lib/src packages/conatus_code/lib/src/mcp packages/conatus_mcp/test
git commit -m "feat(mcp): OAuth token 存储、回调与传输鉴权"
```

---

### Task 8: `nava mcp` CLI 与原子配置写入

**Files:**
- Create: `packages/conatus_code/lib/src/mcp/mcp_cli.dart`
- Modify: `packages/conatus_code/bin/conatus_code.dart`
- Modify: `packages/conatus_code/lib/src/config/config_writer.dart`
- Test: `packages/conatus_code/test/mcp/mcp_cli_test.dart`
- Test: `packages/conatus_code/test/config/config_writer_atomic_test.dart`

**Interfaces:**
- `Future<int> runMcpCli(List<String> args, {String? configPath});`
- `void writeFileAtomic(String path, String content, {int mode = 0o600});`
- `String appendMcpServerSection(String toml, {required String name, String? url, List<String>? command, List<String>? args, bool? oauth});`

- [ ] **Step 1: Write the failing tests**

```dart
test('mcp add writes a new server section to nava config', () async {
  final code = await runMcpCli(['add', 'docs', '--url', 'https://mcp.example.com/mcp'], configPath: path);
  expect(code, 0);
  expect(File(path).readAsStringSync(), contains('[mcp.servers.docs]'));
  expect(File(path).readAsStringSync(), contains('https://mcp.example.com/mcp'));
});

test('atomic write leaves no temp file', () {
  writeFileAtomic(path, 'x');
  expect(File('$path.tmp').existsSync(), isFalse);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd packages/conatus_code && dart test test/mcp/mcp_cli_test.dart test/config/config_writer_atomic_test.dart`
Expected: FAIL — `runMcpCli` / `writeFileAtomic` not defined.

- [ ] **Step 3: Implement**

- `bin` 在 `TuiOptions.parse` 前识别 `mcp` 子命令；失败退出码 2，成功 0。
- `add`：`--url` 或 `-- <command...>`；`--global` 写 `~/.nava/config.toml`（当前只有全局）；拒绝写 `.opencode`。
- `list`：只读 config，打印 name/type/url 或 command，不连接 server。
- `auth`：调 `McpOAuthSession.authorize`，token 落 `~/.nava/oauth`；`logout` 删除 token。
- `writeFileAtomic`：同目录临时文件 + rename + chmod；`appendMcpServerSection` 用现有 `appendProviderSection` 的 TOML 转义风格。
- 更新 `kDefaultConfigToml` 注释示例（MCP oauth）。

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd packages/conatus_code && dart test test/mcp test/config`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/conatus_code/lib/src/mcp packages/conatus_code/bin/conatus_code.dart packages/conatus_code/lib/src/config packages/conatus_code/test/mcp packages/conatus_code/test/config
git commit -m "feat(code): nava mcp CLI 与原子配置写入"
```

---

## 完成标准

- 会话可重命名、删除、tab 切换；旧会话无 title 时正常派生。
- MCP server 支持 resources/prompts 时可用工具与 `/<server>:<prompt>`；不支持时静默跳过。
- OAuth 可完成授权、刷新、登出；token 0600 且不泄露。
- `nava mcp add/list/auth/logout` 只写 `~/.nava`。
- `cd packages/conatus_foundation && dart test`、`cd packages/conatus_mcp && dart test -x integration`、`cd packages/conatus_code && dart test`、`dart analyze --fatal-infos` 全绿。
