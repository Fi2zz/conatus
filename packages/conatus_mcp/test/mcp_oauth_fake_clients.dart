/// OAuth 测试用的异常 HTTP client（超时 / 传输失败）。
library;

import 'dart:async';

import 'package:http/http.dart' as http;

/// 接受请求但永不响应，用于验证显式超时。
class HangingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
}

/// 每次发送都抛 [error]，用于验证传输失败映射。
class FailingClient extends http.BaseClient {
  /// 构造。
  FailingClient(this.error);

  /// 发送时抛出的异常。
  final Object error;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      throw error;
}
