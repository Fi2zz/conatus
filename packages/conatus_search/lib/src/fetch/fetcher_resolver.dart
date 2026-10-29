/// 抓取后端的装配：按 [FetchBackend] 与凭据挑一个 [WebFetcher]。
library;

import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:http/http.dart' as http;
import '../deepseek_shared.dart';
import 'deepseek_fetcher.dart';
import 'fetcher.dart';
import 'firecrawl_fetcher.dart';
import 'http_fetcher.dart';

/// 按 [backend] 构造抓取器。
///
/// [FetchBackend.auto] 沿用历史行为：有 `FIRECRAWL_API_KEY` 走 Firecrawl，
/// 否则裸 HTTP。显式指定 `firecrawl` / `deepseek` 却缺对应 Key 时抛
/// [ArgumentError]——静默换回裸 HTTP 会让人以为自己在用付费后端。
WebFetcher resolveFetcher(
  Credentials? credentials,
  http.Client? client,
  FetchBackend backend,
) {
  final Credential? firecrawl = credentials?.get(kFirecrawlCredentialKey);
  if (backend == FetchBackend.auto) {
    if (firecrawl == null) return HttpFetcher(client: client);
    return FirecrawlFetcher(apiKey: firecrawl.value, client: client);
  }
  if (backend == FetchBackend.http) return HttpFetcher(client: client);
  final bool wantsDeepSeek = backend == FetchBackend.deepseek;
  final String keyName =
      wantsDeepSeek ? kDeepSeekCredentialKey : kFirecrawlCredentialKey;
  final Credential? key =
      wantsDeepSeek ? credentials?.get(kDeepSeekCredentialKey) : firecrawl;
  if (key == null) {
    throw ArgumentError('抓取后端 ${backend.name} 需要凭据 $keyName');
  }
  return wantsDeepSeek
      ? DeepSeekFetcher(apiKey: key.value, client: client)
      : FirecrawlFetcher(apiKey: key.value, client: client);
}
