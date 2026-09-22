# conatus_search

conatus 的搜索能力缝：

- `SearchService` + 可插拔 `SearchProvider`，按名字顺序装配、逐个回退：
  内置 `tavily` / `exa` / `brave` / `duckduckgo`（DuckDuckGo 免 Key），
  缺凭据的源自动跳过
- 凭据统一经 `conatus_credentials`（`TAVILY_API_KEY` / `EXA_API_KEY` /
  `BRAVE_API_KEY`），**不直接读环境变量**
- `WebSearchTool` / `FetchUrlTool` 与 `provideWebTools`（注册 `web_search` /
  `fetch_url`）；`fetch_url` 缺省裸 http，配了 `FIRECRAWL_API_KEY` 时改走
  Firecrawl（返回 markdown）

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

搜索全失败时 `web_search` 返回 `SEARCH_UNAVAILABLE`，文案以「无法联网：所有搜索源
都不可用。」开头，并列出没配好的源（如 `exa（缺少 EXA_API_KEY）`）。
