import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

class _EchoTool extends Tool {
  const _EchoTool();

  @override
  String get name => 'echo';

  @override
  String get description => '回显输入';

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final String text = ctx.string('text') ?? '';
    return ToolResult.success(text, value: text);
  }
}

class _CountingTool extends Tool {
  _CountingTool();
  int runs = 0;

  @override
  String get name => 'count';

  @override
  String get description => '';

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    runs++;
    return ToolResult.success('x');
  }
}

class _BoomTool extends Tool {
  const _BoomTool();

  @override
  String get name => 'boom';

  @override
  String get description => '';

  @override
  Future<ToolResult> call(ToolContext ctx) async => throw StateError('炸了');
}

class _GreetTool extends Tool {
  int runs = 0;

  @override
  String get name => 'greet';

  @override
  String get description => '打招呼';

  @override
  List<ParamSpec> get params =>
      <ParamSpec>[ParamSpec.string('who', required: true)];

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    runs++;
    return ToolResult.success('hi ${ctx.str('who')}');
  }
}

class _SlowTool extends Tool {
  const _SlowTool();

  @override
  String get name => 'slow';

  @override
  String get description => '';

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return ToolResult.success('done');
  }
}

/// 自声明超时的慢工具：默认 20ms，长于注册表默认超时。
class _SelfTimedTool extends Tool {
  const _SelfTimedTool();

  @override
  String get name => 'self-timed';

  @override
  String get description => '';

  @override
  Duration? get timeout => const Duration(milliseconds: 20);

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return ToolResult.success('done');
  }
}

void main() {
  group('Tool / ToolResult', () {
    test('默认风险等级为 low、不分组，toSchema 只含白名单字段', () {
      const Tool tool = _EchoTool();

      expect(tool.riskLevel, ToolRisk.low);
      expect(tool.group, isNull);
      expect(
          tool.toSchema().keys, <String>['name', 'description', 'parameters']);
      expect((tool.toSchema()['parameters']! as Map<String, Object?>)['type'],
          'object');
    });
  });

  group('ToolContext', () {
    test('optional / require / has / operator[]', () {
      const ToolContext ctx = ToolContext(
        ToolCall(
          name: 'echo',
          callId: 'c1',
          arguments: <String, Object?>{'text': 'hi', 'n': 3, 'flag': true},
        ),
      );

      expect(ctx.callId, 'c1');
      expect(ctx.has('text'), isTrue);
      expect(ctx.has('missing'), isFalse);
      expect(ctx['n'], 3);
      expect(ctx.string('text'), 'hi');
      expect(ctx.integer('n'), 3);
      expect(ctx.boolean('flag'), isTrue);
      expect(ctx.string('missing'), isNull);
    });

    test('类型化取参与 number 归一', () {
      const ToolContext ctx = ToolContext(
        ToolCall(name: 't', arguments: <String, Object?>{
          'ratio': 2,
          'items': <Object?>[1, 2]
        }),
      );

      expect(ctx.number('ratio'), 2.0);
      expect(ctx.array('items'), <Object?>[1, 2]);
    });

    test('required 缺失/类型不符抛 ToolArgumentException', () {
      const ToolContext ctx = ToolContext(
        ToolCall(name: 't', arguments: <String, Object?>{'n': 'not-int'}),
      );

      expect(() => ctx.require<String>('missing'),
          throwsA(isA<ToolArgumentException>()));
      expect(
          () => ctx.require<int>('n'), throwsA(isA<ToolArgumentException>()));
    });
  });

  group('ToolRegistry — 注册与 schema', () {
    test('register / get / names；执行体不外泄', () {
      final ToolRegistry tools = ToolRegistry();

      final Disposer off = tools.register(const _EchoTool());

      expect(tools.get('echo'), isNotNull);
      expect(tools.names, <String>['echo']);
      expect(tools.describe(), hasLength(1));
      expect(tools.describe().single['name'], 'echo');

      off();
      expect(tools.get('echo'), isNull);
      off(); // 幂等
      expect(tools.length, 0);
    });

    test('同名重复注册抛 StateError', () {
      final ToolRegistry tools = ToolRegistry()..register(const _EchoTool());
      expect(() => tools.register(const _EchoTool()), throwsStateError);
    });

    test('onChange 在注册与撤销时各触发一次', () {
      final ToolRegistry tools = ToolRegistry();
      var changes = 0;
      final Disposer watch = tools.onChange(() => changes++);

      final Disposer off = tools.register(const _EchoTool());
      expect(changes, 1);
      off();
      expect(changes, 2);

      watch();
      tools.register(const _EchoTool());
      expect(changes, 2);
    });
  });

  group('ToolRegistry — 执行管线', () {
    test('成功执行：参数进入工具，结果广播给 onResult', () async {
      final ToolRegistry tools = ToolRegistry()..register(const _EchoTool());
      final List<ToolResult> seen = <ToolResult>[];
      tools.onResult((ToolCall call, ToolResult result) => seen.add(result));

      final ToolResult result = await tools.call(
        const ToolCall(
            name: 'echo', arguments: <String, Object?>{'text': 'hi'}),
      );

      expect(result.isError, isFalse);
      expect(result.content, 'hi');
      expect(result.value, 'hi');
      expect(seen, hasLength(1));
    });

    test('未知工具返回 UNKNOWN_TOOL，不抛异常', () async {
      final ToolRegistry tools = ToolRegistry();
      final ToolResult result = await tools.call(const ToolCall(name: 'nope'));
      expect(result.isError, isTrue);
      expect(result.error!.code, 'UNKNOWN_TOOL');
    });

    test('守护拒绝：执行体不运行，结果为 TOOL_DENIED', () async {
      final _CountingTool counter = _CountingTool();
      final ToolRegistry tools = ToolRegistry()..register(counter);
      tools.guard((ToolCall call) => call.name == 'count' ? '不允许' : null);

      final ToolResult result = await tools.call(const ToolCall(name: 'count'));

      expect(counter.runs, 0);
      expect(result.isError, isTrue);
      expect(result.error!.code, 'TOOL_DENIED');
      expect(result.content, '不允许');
    });

    test('中间件按后进先出包裹，可改写结果', () async {
      final ToolRegistry tools = ToolRegistry()..register(const _EchoTool());
      final List<String> order = <String>[];
      tools.use((ToolCall call, Future<ToolResult> Function() next) async {
        order.add('outer-before');
        final ToolResult inner = await next();
        order.add('outer-after');
        return ToolResult.success('[${inner.content}]');
      });
      tools.use((ToolCall call, Future<ToolResult> Function() next) async {
        order.add('inner');
        return next();
      });

      final ToolResult result = await tools.call(
        const ToolCall(
            name: 'echo', arguments: <String, Object?>{'text': 'hi'}),
      );

      expect(order, <String>['outer-before', 'inner', 'outer-after']);
      expect(result.content, '[hi]');
    });

    test('执行体抛异常被收敛为 TOOL_ERROR', () async {
      final ToolRegistry tools = ToolRegistry()..register(const _BoomTool());

      final ToolResult result = await tools.call(const ToolCall(name: 'boom'));

      expect(result.isError, isTrue);
      expect(result.error!.code, 'TOOL_ERROR');
    });
  });

  group('ToolRegistry — 参数校验', () {
    test('缺失必填参数 → INVALID_ARGS，执行体不运行', () async {
      final _GreetTool greet = _GreetTool();
      final ToolRegistry tools = ToolRegistry()..register(greet);

      final ToolResult result = await tools.call(const ToolCall(name: 'greet'));

      expect(greet.runs, 0);
      expect(result.isError, isTrue);
      expect(result.error!.code, 'INVALID_ARGS');
    });

    test('类型不符 → INVALID_ARGS', () async {
      final ToolRegistry tools = ToolRegistry()..register(_GreetTool());

      final ToolResult result = await tools.call(
        const ToolCall(name: 'greet', arguments: <String, Object?>{'who': 1}),
      );

      expect(result.error!.code, 'INVALID_ARGS');
    });

    test('合法参数通过校验并执行', () async {
      final ToolRegistry tools = ToolRegistry()..register(_GreetTool());

      final ToolResult result = await tools.call(
        const ToolCall(
            name: 'greet', arguments: <String, Object?>{'who': '助手'}),
      );

      expect(result.content, 'hi 助手');
    });
  });

  group('ToolRegistry — 超时与描述', () {
    test('超时返回 TOOL_TIMEOUT', () async {
      final ToolRegistry tools = ToolRegistry()..register(const _SlowTool());

      final ToolResult result = await tools.call(
        const ToolCall(name: 'slow'),
        timeout: const Duration(milliseconds: 20),
      );

      expect(result.isError, isTrue);
      expect(result.error!.code, 'TOOL_TIMEOUT');
    });

    test('defaultTimeout 生效', () async {
      final ToolRegistry tools = ToolRegistry(
        defaultTimeout: const Duration(milliseconds: 20),
      )..register(const _SlowTool());

      final ToolResult result = await tools.call(const ToolCall(name: 'slow'));

      expect(result.error!.code, 'TOOL_TIMEOUT');
    });

    test('工具自声明 timeout 覆盖 defaultTimeout，调用参数又覆盖它', () async {
      final ToolRegistry tools = ToolRegistry(
        defaultTimeout: const Duration(milliseconds: 500),
      )..register(const _SelfTimedTool());

      expect(
        (await tools.call(const ToolCall(name: 'self-timed'))).error!.code,
        'TOOL_TIMEOUT',
      );
      expect(
        (await tools.call(
          const ToolCall(name: 'self-timed'),
          timeout: const Duration(seconds: 5),
        ))
            .isError,
        isFalse,
      );
    });

    test('describeOne 未注册返回 null', () {
      final ToolRegistry tools = ToolRegistry()..register(_GreetTool());

      expect(tools.describeOne('greet'), isNotNull);
      expect(tools.describeOne('nope'), isNull);
    });
  });

  group('provideTools / ctx.tools', () {
    test('作为 tools 服务提供，随上下文释放撤销登记', () {
      final Context ctx = Context.root();
      final ToolRegistry tools = provideTools(ctx);

      ctx.effect(() => tools.register(const _EchoTool()));
      expect(ctx.tools.get('echo'), isNotNull);

      ctx.dispose();
      expect(tools.get('echo'), isNull);
    });

    test('未提供时 ctx.tools 抛 StateError', () {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      expect(() => ctx.tools, throwsStateError);
    });
  });
}
