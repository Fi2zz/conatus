/// 内置资源工具：列举 / 读取、文本与二进制渲染、64 KiB 截断。
library;

import 'dart:convert';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';

import 'mcp_resource_test_support.dart';

void main() {
  late Context ctx;
  late ToolRegistry tools;

  setUp(() {
    ctx = Context.root();
    tools = provideTools(ctx);
  });

  tearDown(() {
    if (!ctx.disposed) ctx.dispose();
  });

  test('注册两个只读工具', () async {
    await bootToolRegistry(ctx);
    expect(tools.get('list_mcp_resources')?.riskLevel, ToolRisk.low);
    expect(tools.get('read_mcp_resource')?.riskLevel, ToolRisk.low);
    expect(
        tools.names,
        containsAll(<String>[
          'list_mcp_resources',
          'read_mcp_resource',
        ]));
  });

  test('list_mcp_resources 汇总并按 server 过滤', () async {
    await bootToolRegistry(ctx);
    final ToolResult all = await tools.call(
      const ToolCall(name: 'list_mcp_resources'),
    );
    expect(all.isError, isFalse);
    expect(all.content, contains('alpha'));
    expect(all.content, contains('file:///a'));
    expect(all.content, contains('file:///b'));

    final ToolResult beta = await tools.call(
      const ToolCall(
        name: 'list_mcp_resources',
        arguments: <String, Object?>{'server': 'beta'},
      ),
    );
    expect(beta.content, contains('file:///b'));
    expect(beta.content, isNot(contains('file:///a')));

    final ToolResult missing = await tools.call(
      const ToolCall(
        name: 'list_mcp_resources',
        arguments: <String, Object?>{'server': 'missing'},
      ),
    );
    expect(missing.isError, isTrue);
  });

  test('read_mcp_resource 渲染文本 / 二进制并截断', () async {
    await bootToolRegistry(ctx);

    final ToolResult text = await tools.call(
      const ToolCall(name: 'read_mcp_resource', arguments: <String, Object?>{
        'server': 'alpha',
        'uri': 'file:///a',
      }),
    );
    expect(text.content, 'alpha text');

    final ToolResult binary = await tools.call(
      const ToolCall(name: 'read_mcp_resource', arguments: <String, Object?>{
        'server': 'alpha',
        'uri': 'file:///bin',
      }),
    );
    expect(binary.content, '[binary 3 bytes]');

    final ToolResult big = await tools.call(
      const ToolCall(name: 'read_mcp_resource', arguments: <String, Object?>{
        'server': 'alpha',
        'uri': 'file:///big',
      }),
    );
    expect(big.content, endsWith('（已截断）'));
    expect(
      utf8.encode(big.content).length,
      lessThan(kMcpResourceContentLimit + 64),
    );

    final ToolResult missing = await tools.call(
      const ToolCall(name: 'read_mcp_resource', arguments: <String, Object?>{
        'server': 'missing',
        'uri': 'file:///a',
      }),
    );
    expect(missing.isError, isTrue);
  });
}
