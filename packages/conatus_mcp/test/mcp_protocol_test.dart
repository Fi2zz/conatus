import 'dart:convert';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('McpMessage', () {
    test('请求三态判定与往返', () {
      final McpMessage request = McpMessage.request(
        id: 7,
        method: 'tools/call',
        params: <String, Object?>{'name': 'echo'},
      );

      expect(request.request, isTrue);
      expect(request.notification, isFalse);
      expect(request.response, isFalse);

      final Map<String, Object?> json = request.toJson();
      expect(json['jsonrpc'], '2.0');
      expect(json['method'], 'tools/call');
      expect(json['id'], 7);
      expect(json['params'], <String, Object?>{'name': 'echo'});

      final McpMessage back = McpMessage.fromJson(json);
      expect(back.request, isTrue);
      expect(back.id, 7);
      expect(back.method, 'tools/call');
      expect(back.params, <String, Object?>{'name': 'echo'});
    });

    test('通知无 id', () {
      final McpMessage note =
          McpMessage.notification(method: 'notifications/initialized');

      expect(note.notification, isTrue);
      expect(note.request, isFalse);
      expect(note.id, isNull);
      expect(note.toJson().containsKey('id'), isFalse);

      final McpMessage back = McpMessage.fromJson(note.toJson());
      expect(back.notification, isTrue);
    });

    test('响应往返（成功与失败）', () {
      final McpMessage ok = McpMessage.fromJson(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'result': <String, Object?>{'tools': <Object?>[]},
      });
      expect(ok.response, isTrue);
      expect(ok.error, isNull);
      expect(ok.toJson()['result'], <String, Object?>{'tools': <Object?>[]});

      final McpMessage bad = McpMessage.fromJson(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 2,
        'error': <String, Object?>{
          'code': -32601,
          'message': '未知方法',
          'data': 42,
        },
      });
      expect(bad.response, isTrue);
      expect(bad.error?.code, -32601);
      expect(bad.error?.message, '未知方法');
      expect(bad.error?.data, 42);
      expect(bad.toJson().containsKey('result'), isFalse);
    });

    test('宽松解析：畸形字段不抛错', () {
      final McpMessage odd = McpMessage.fromJson(<String, Object?>{
        'id': 'abc',
        'method': 12,
        'params': 'nope',
        'error': 'nope',
      });
      expect(odd.method, isNull);
      expect(odd.params, isNull);
      expect(odd.error, isNull);
      expect(odd.id, 'abc');
    });

    test('jsonDecode 的 Map 可直接喂给 fromJson', () {
      final Object? decoded = jsonDecode(
        '{"jsonrpc":"2.0","id":9,"result":{"tools":[]}}',
      );
      final McpMessage message =
          McpMessage.fromJson(decoded! as Map<String, Object?>);
      expect(message.id, 9);
      expect(message.response, isTrue);
    });
  });

  group('McpError', () {
    test('往返与缺省', () {
      final McpError error = McpError.fromJson(<String, Object?>{
        'code': -32602,
        'message': '参数不合法',
        'data': <String, Object?>{'field': 'name'},
      });
      expect(error.code, -32602);
      expect(error.toJson()['data'], <String, Object?>{'field': 'name'});

      final McpError empty = McpError.fromJson(<String, Object?>{});
      expect(empty.code, 0);
      expect(empty.message, '');
      expect(empty.toJson().containsKey('data'), isFalse);
    });
  });

  group('McpServerInfo', () {
    test('解析 serverInfo 嵌套形态；版本照收', () {
      final McpServerInfo info = McpServerInfo.fromJson(<String, Object?>{
        'protocolVersion': '2024-11-05',
        'capabilities': <String, Object?>{
          'tools': <String, Object?>{},
        },
        'serverInfo': <String, Object?>{'name': 'fs', 'version': '1.2.3'},
        'instructions': '只能用相对路径',
      });
      expect(info.protocolVersion, '2024-11-05');
      expect(info.name, 'fs');
      expect(info.version, '1.2.3');
      expect(info.instructions, '只能用相对路径');
      expect(info.capabilities.containsKey('tools'), isTrue);
    });

    test('顶层 name / version 也接受；缺版本时用本客户端声明', () {
      final McpServerInfo info = McpServerInfo.fromJson(
        <String, Object?>{'name': 'echo', 'version': '0.0.1'},
      );
      expect(info.name, 'echo');
      expect(info.version, '0.0.1');
      expect(info.protocolVersion, kMcpProtocolVersion);
      expect(info.capabilities, isEmpty);
    });
  });
}
