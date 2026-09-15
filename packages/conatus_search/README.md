# conatus_search

conatus 的搜索能力缝：

- `SearchService` + 可插拔 `SearchProvider`，默认 DuckDuckGo（无需 Key），
  传入 `exaApiKey` 时 Exa 优先，多个 provider 顺序回退
- `WebSearchTool` / `FetchUrlTool` 与 `provideWebTools`（注册 `web_search` / `fetch_url`）

```dart
import 'package:conatus_search/conatus_search.dart';

provideSearch(app, exaApiKey: Platform.environment['EXA_API_KEY']);
provideWebTools(app);
```
