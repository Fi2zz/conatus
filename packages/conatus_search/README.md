# conatus_search

conatus 的搜索能力缝：

- `SearchService` + 可插拔 `SearchProvider`，按名字顺序装配、逐个回退：
  内置 `tavily` / `exa` / `brave` / `deepseek` / `kimi` / `parallel` / `exa-mcp` /
  `duckduckgo`，缺凭据的源自动跳过
- **免 Key 的源有三个**：`parallel`、`exa-mcp`（厂商托管的远程 MCP 端点）与
  `duckduckgo`（HTML 端点）。前两个不需要账号也不读任何凭据，未提供凭据服务
  时也能用
- 凭据统一经 `conatus_credentials`（`TAVILY_API_KEY` / `EXA_API_KEY` /
  `BRAVE_API_KEY` / `DEEPSEEK_API_KEY` / `MOONSHOT_API_KEY`），**不直接读环境变量**
- `WebSearchTool` / `FetchUrlTool` 与 `provideWebTools`（注册 `websearch` /
  `webfetch`）；`webfetch` 缺省裸 http，配了 `FIRECRAWL_API_KEY` 时改走
  Firecrawl（返回 markdown），也可显式指定 `FetchBackend.deepseek` /
  `FetchBackend.kimi`

```dart
import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_search/conatus_search.dart';

final Credentials credentials = provideCredentials(app);   // 缺省 EnvCredentials
provideSearch(app, credentials: credentials);               // 按 kDefaultSearchOrder
provideWebTools(app, credentials: credentials);

// 只要某几家、并改顺序：
provideSearch(app,
    order: <String>['brave', 'duckduckgo'], credentials: credentials);
```

搜索全失败时 `websearch` 返回 `SEARCH_UNAVAILABLE`，文案以「无法联网：所有搜索源
都不可用。」开头，并列出没配好的源（如 `exa（缺少 EXA_API_KEY）`）。

## 内置搜索源

| 名字 | 凭据键 | 说明 |
|------|--------|------|
| `tavily` | `TAVILY_API_KEY` | Tavily 官方 API |
| `exa` | `EXA_API_KEY` | Exa 官方 API |
| `brave` | `BRAVE_API_KEY` | Brave Search API |
| `deepseek` | `DEEPSEEK_API_KEY` | `POST /v1/tools/search`，与 DeepSeek 模型接口共用 Key；优先用 600~800 字符的 `summary`，逐条截断到 600 字符 |
| `kimi` | `MOONSHOT_API_KEY` | `POST /v1/tools/search`（Basic），与 Kimi 模型接口共用 Key；`text_query` + `limit`(1..20)，优先用 `snippet`，为空回退 `text`，逐条截断到 600 字符；**成功且非空才计费** |
| `parallel` | 免 Key | `https://mcp.parallel.ai/mcp` 的 `web_search`，返回 `structuredContent`，解析最稳 |
| `exa-mcp` | 免 Key | `https://mcp.exa.ai/mcp` 的 `web_search_exa`，结果只有文本，按 `Title:` / `URL:` 切块 |
| `duckduckgo` | 免 Key | 抓 HTML 端点，上游结构变动时可能解析不到 |

缺省顺序把带 Key 的源排在前面（配额充足时质量更好），免 Key 的源随后兜底。
`deepseek` / `kimi` 都按成功请求计费，且复用已有的模型 Key，所以排在其它带 Key
源之后。

两个 MCP 源走 `McpSearchProvider`：**无状态调用**，每次搜索直接 POST 一条
`tools/call`，不做 `initialize` 握手，也不持有长活连接（`SearchProvider`
没有 dispose 生命周期，长开会漏 socket）。

远端约束：请求必须带 `accept: application/json, text/event-stream`（只发
`application/json` 会被 406 拒绝）；响应可能是 SSE 也可能是一段纯 JSON，
`decodeMcpResponseBody` 两种都吃。

## 只想要免 Key 搜索

不提供 `'credentials'` 服务即可，装配期只会注册免 Key 的源：

```dart
final SearchService search = provideSearch(app);
// providers: [parallel, exa-mcp, duckduckgo]
```

也可以显式收窄：`provideSearch(app, order: <String>['parallel'])`。

装配期被跳过的源及原因从 `search.statuses` 读（如 `未提供凭据服务`、
`缺少 TAVILY_API_KEY`），运行期冷却状态见 `search.allStatuses()`。

## 抓取后端

`webfetch` 的后端由 `provideWebTools` 的 `backend` 决定：

| `backend` | 行为 |
|-----------|------|
| `FetchBackend.auto`（缺省） | 有 `FIRECRAWL_API_KEY` 走 Firecrawl，否则裸 HTTP |
| `FetchBackend.http` | 强制裸 HTTP + 本地去标签 |
| `FetchBackend.firecrawl` | 强制 Firecrawl，缺 Key 抛 `ArgumentError` |
| `FetchBackend.deepseek` | 强制 DeepSeek `POST /v1/tools/fetch`，缺 Key 抛 `ArgumentError` |
| `FetchBackend.kimi` | 强制 Kimi `POST /v1/tools/fetch`，缺 Key 抛 `ArgumentError` |

显式指定的后端缺 Key 时装配期直接失败——静默换回裸 HTTP 会让人以为自己在用付费
后端。`DeepSeekFetcher` / `KimiFetcher` 只产出 markdown，请求 `text` / `html` 时
`FetchedPage.format` 仍标注为 `markdown`，不谎报成调用方请求的格式。Kimi 的正文放
在 `markdown` 字段（DeepSeek 放 `content`），403 `security_risk`（风控拒绝）与 404
`markdown_not_found`（取不到正文）的 `error.message` 会拼进错误文案。

## 自定义源

实现 `SearchProvider`（`name` + `search`）后注册：

```dart
app.effect(() => app.search.register(MyProvider()));
```

需要在装配期就参与顺序回退时，用
`provideSearch(app, providers: <SearchProvider>[...])`——此时 `order` 被忽略，
`statuses` 为空。
