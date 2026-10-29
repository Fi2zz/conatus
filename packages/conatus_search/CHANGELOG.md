# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

- 新增 Tavily / Brave 两个 HTTP 搜索源；`SearchService` 暴露 `statuses`
  （装配期哪些源可用、哪些被跳过及原因）。
- 新增名字驱动的装配：`SearchProviderSpec` / `kSearchProviderSpecs` /
  `buildSearchProviders` / `kDefaultSearchOrder`；凭据统一经
  `conatus_credentials` 解析。
- 新增 `WebFetcher` 接缝：`HttpFetcher`（默认，stripHtml 迁入此文件）与
  `FirecrawlFetcher`（配 `FIRECRAWL_API_KEY` 时启用，返回 markdown）。
- `web_search` 全失败时返回 `SEARCH_UNAVAILABLE` 并给出明确「无法联网」文案与
  未配置源清单；`fetch_url` 失败文案同口径。
- 新增 `deepseek` 搜索源（`POST /v1/tools/search`，复用 `DEEPSEEK_API_KEY`）与
  `DeepSeekFetcher` 抓取后端（`POST /v1/tools/fetch`，只产出 markdown）；
  `FetchBackend` 枚举 + `resolveFetcher` 负责按后端挑选抓取器，显式指定的后端
  缺 Key 时装配期抛 `ArgumentError`。
- **破坏性**：`provideSearch` 移除 `exaApiKey`，改为 `order` + `credentials`
  （缺省取上下文的 `'credentials'` 服务）；`provideWebTools` 新增可选
  `fetcher` / `credentials` / `backend`。

## [0.15.0] — 2026-09-15

- 从 `conatus` 单体仓库拆分为独立包（pub workspace monorepo），
  承载 `SearchService`、DuckDuckGo / Exa provider 与 web 工具。
