/// MCP 传输抽象：连接、双向消息与诊断。
library;

import 'mcp_protocol.dart';

/// 一条 MCP 连接的传输层。
///
/// 实现负责把 [McpMessage] 搬到对端（子进程管道、HTTP POST 或 SSE 长连接），
/// 并把对端来的数据还原成消息。传输层的错误有两种归宿：
///
/// * [messages] 上的 `addError` —— 连接级故障（进程退出、SSE 结束），
///   上层据此判定断连；
/// * `send` 抛出 —— 单次发送失败（HTTP 非 200），只影响这一次请求。
abstract class McpTransport {
  /// 建立连接；已连接时重复调用应无害。
  Future<void> connect();

  /// 断开连接并释放资源；幂等。
  ///
  /// 由调用方传入的 `http.Client` 不由传输层关闭（见各实现的 dartdoc）。
  Future<void> disconnect();

  /// 自对端流入的消息；实现为单订阅流，错误经 `addError` 送达。
  Stream<McpMessage> get messages;

  /// 诊断文本（stderr、坏行、状态变化）；默认空。
  Stream<String> get diagnostics => const Stream<String>.empty();

  /// 发送一条消息。
  ///
  /// 单次发送失败抛 [McpException]，不污染 [messages]。
  Future<void> send(McpMessage message);
}
