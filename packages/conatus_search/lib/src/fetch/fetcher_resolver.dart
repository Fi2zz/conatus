/// 抓取后端的装配：按 [FetchBackend] 与凭据挑一个 [WebFetcher]。
library;

import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:http/http.dart' as http;
import '../deepseek_shared.dart';
import '../kimi_shared.dart';
import 'deepseek_fetcher.dart';
import 'fetcher.dart';
import 'firecrawl_fetcher.dart';
import 'http_fetcher.dart';
import 'kimi_fetcher.dart';

/// 按 [backend] 构造抓取器。
///
/// [FetchBackend.auto] 沿用历史行为：有 `FIRECRAWL_API_KEY` 走 Firecrawl，
/// 否则裸 HTTP。显式指定 `firecrawl` / `deepseek` / `kimi` 却缺对应 Key 时抛
/// [ArgumentError]——静默换回裸 HTTP 会让人以为自己在用付费后端。
WebFetcher resolveFetcher(
  Credentials? credentials,
  http.Client? client,
  FetchBackend backend,
) {
  if (backend == FetchBackend.http) return HttpFetcher(client: client);
  if (backend == FetchBackend.auto) return _autoFetcher(credentials, client);
  final (String keyName, WebFetcher Function(String apiKey) create) =
      _explicitBackend(backend, client);
  final Credential? key = credentials?.get(keyName);
  if (key == null) {
    throw ArgumentError('抓取后端 ${backend.name} 需要凭据 $keyName');
  }
  return create(key.value);
}

/// 缺省行为：Firecrawl 优先，没有 Key 就退回裸 HTTP。
WebFetcher _autoFetcher(Credentials? credentials, http.Client? client) {
  final Credential? firecrawl = credentials?.get(kFirecrawlCredentialKey);
  if (firecrawl == null) return HttpFetcher(client: client);
  return FirecrawlFetcher(apiKey: firecrawl.value, client: client);
}

/// 显式后端 →（凭据键, 构造器）。
(String, WebFetcher Function(String apiKey)) _explicitBackend(
  FetchBackend backend,
  http.Client? client,
) =>
    switch (backend) {
      FetchBackend.firecrawl => (
          kFirecrawlCredentialKey,
          (String apiKey) => FirecrawlFetcher(apiKey: apiKey, client: client),
        ),
      FetchBackend.deepseek => (
          kDeepSeekCredentialKey,
          (String apiKey) => DeepSeekFetcher(apiKey: apiKey, client: client),
        ),
      FetchBackend.kimi => (
          kKimiCredentialKey,
          (String apiKey) => KimiFetcher(apiKey: apiKey, client: client),
        ),
      // 上游已在开头分流；穷尽 switch 要求列出全部取值。
      FetchBackend.auto || FetchBackend.http => throw ArgumentError(
          '抓取后端 ${backend.name} 不需要凭据，应由调用方提前处理'),
    };
