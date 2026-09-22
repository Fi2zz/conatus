/// provider 共用的 HTTP 细节：把请求超时归一成 [SearchException]。
library;

import 'dart:async';
import 'package:http/http.dart' as http;
import 'search_types.dart';

/// 等待 [future]，超过 [timeout] 抛 [SearchException]。
///
/// 各 provider 的 HTTP 客户端不直接暴露超时，统一在这里转换，使
/// `SearchService` 的聚合错误文案保持一致的形状（`'<provider>: <原因>'`）。
Future<http.Response> sendWithTimeout(
  Future<http.Response> future, {
  required Duration timeout,
  required String provider,
}) async {
  try {
    return await future.timeout(timeout);
  } on TimeoutException {
    throw SearchException('$provider 请求超时（${timeout.inSeconds}s）');
  }
}
