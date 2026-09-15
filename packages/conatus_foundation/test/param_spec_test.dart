import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

class _SearchTool extends Tool {
  @override
  String get name => 'search';

  @override
  String get description => '搜索';

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('query', required: true, description: '查询词'),
        ParamSpec.integer('limit', description: '条数'),
      ];

  @override
  Future<ToolResult> call(ToolContext ctx) async => ToolResult.success('');
}

void main() {
  group('ParamSpec.toJson', () {
    test('标量类型与说明', () {
      expect(
        ParamSpec.string('s', required: true, description: 'd').toJson(),
        <String, Object?>{'type': 'string', 'description': 'd'},
      );
      expect(ParamSpec.integer('i').toJson()['type'], 'integer');
      expect(ParamSpec.number('n').toJson()['type'], 'number');
      expect(ParamSpec.boolean('b').toJson()['type'], 'boolean');
    });

    test('默认值作为 schema 注解', () {
      expect(ParamSpec.integer('i', defaultValue: 3).toJson()['default'], 3);
    });

    test('枚举取值编译为 string + enum', () {
      final Map<String, Object?> json =
          ParamSpec.enumeration('e', <String>['a', 'b']).toJson();
      expect(json['type'], 'string');
      expect(json['enum'], <String>['a', 'b']);
    });

    test('枚举空取值抛 ArgumentError', () {
      expect(() => ParamSpec.enumeration('e', <String>[]), throwsArgumentError);
    });

    test('数组编译 items（丢弃 items 的名字/必填）', () {
      final Map<String, Object?> json =
          ParamSpec.array('a', items: ParamSpec.string('item')).toJson();
      expect(json['type'], 'array');
      expect((json['items']! as Map<String, Object?>)['type'], 'string');
    });

    test('嵌套对象聚合子级 required', () {
      final Map<String, Object?> json = ParamSpec.object(
        'o',
        properties: <String, ParamSpec>{
          'x': ParamSpec.string('x', required: true),
          'y': ParamSpec.integer('y'),
        },
      ).toJson();

      expect(json['type'], 'object');
      expect(json['required'], <String>['x']);
      expect(
        (json['properties']! as Map<String, Object?>).keys,
        <String>['x', 'y'],
      );
    });
  });

  group('parameterSchema', () {
    test('聚合顶层 required', () {
      final Map<String, Object?> schema = parameterSchema(<ParamSpec>[
        ParamSpec.string('q', required: true),
        ParamSpec.integer('limit'),
      ]);

      expect(schema['type'], 'object');
      expect(schema['required'], <String>['q']);
      expect((schema['properties']! as Map<String, Object?>).keys,
          <String>['q', 'limit']);
    });

    test('无必填时不带 required 字段', () {
      expect(
        parameterSchema(<ParamSpec>[ParamSpec.string('q')])
            .containsKey('required'),
        isFalse,
      );
    });
  });

  group('Tool.toSchema', () {
    test('由 params 生成 parameters', () {
      final Map<String, Object?> schema = _SearchTool().toSchema();
      final Map<String, Object?> parameters =
          schema['parameters']! as Map<String, Object?>;

      expect(schema.keys, <String>['name', 'description', 'parameters']);
      expect(parameters['required'], <String>['query']);
      expect((parameters['properties']! as Map<String, Object?>).keys,
          <String>['query', 'limit']);
    });
  });
}
