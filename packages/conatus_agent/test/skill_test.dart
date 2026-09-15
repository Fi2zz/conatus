import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

ToolRegistry _envTools({bool withAir = true}) {
  final ToolRegistry tools = ToolRegistry();
  tools.fn(
    'get_weather',
    handler: (ToolContext c) async => ToolResult.success('${c.str('city')}: 晴'),
  );
  if (withAir) {
    tools.fn(
      'get_air',
      handler: (ToolContext c) async =>
          ToolResult.success('${c.str('city')}: 优'),
    );
  }
  return tools;
}

SkillMeta _meta(String name, String description) =>
    SkillMeta(name: name, description: description);

void main() {
  group('SkillTool', () {
    test('按序执行步骤并替换占位符，返回末步结果', () async {
      final ToolRegistry tools = _envTools();
      final SkillTool skill = SkillTool(
        name: 'check_env',
        description: '查环境',
        steps: const <SkillStep>[
          SkillStep(
              toolName: 'get_weather',
              arguments: <String, Object?>{'city': '{{city}}'}),
          SkillStep(
              toolName: 'get_air',
              arguments: <String, Object?>{'city': '{{city}}'}),
        ],
        tools: tools,
      );

      expect(skill.params.map((ParamSpec p) => p.name), <String>['city']);
      expect(skill.riskLevel, ToolRisk.medium);

      final ToolResult result = await skill.call(const ToolContext(
        ToolCall(name: 'check_env', arguments: <String, Object?>{'city': '北京'}),
      ));

      expect(result.isError, isFalse);
      expect(result.content, '北京: 优');
      expect(result.value, <Object?>['北京: 晴', '北京: 优']);
    });

    test('步骤失败即中止并回传错误', () async {
      final ToolRegistry tools = ToolRegistry();
      tools.fn('boom',
          handler: (ToolContext c) async => ToolResult.failure('炸了'));
      final SkillTool skill = SkillTool(
        name: 's',
        description: '',
        steps: const <SkillStep>[SkillStep(toolName: 'boom')],
        tools: tools,
      );

      final ToolResult result =
          await skill.call(const ToolContext(ToolCall(name: 's')));
      expect(result.isError, isTrue);
      expect(result.content, contains('炸了'));
    });
  });

  group('skill 命名与序列化', () {
    test('skillNameFrom / deterministicSkillNamer', () async {
      expect(
          skillNameFrom('Check City Environment!'), 'check_city_environment');
      final SkillMeta meta = await deterministicSkillNamer(
          '任务', <String>['get_weather', 'get_air']);
      expect(meta.name, 'skill_get_weather_get_air');
      expect(meta.description, contains('get_weather'));
    });

    test('parseSkillMeta 解析 JSON，失败回退', () {
      final SkillMeta parsed = parseSkillMeta(
          '{"name":"Check Env","description":"查环境"}', <String>['a']);
      expect(parsed.name, 'check_env');
      expect(parsed.description, '查环境');
      expect(parseSkillMeta('随便说说', <String>['a']).name, 'skill_a');
    });

    test('SkillTool JSON 往返', () {
      final ToolRegistry tools = _envTools();
      final SkillTool skill = SkillTool(
        name: 's',
        description: 'd',
        steps: const <SkillStep>[
          SkillStep(
              toolName: 'get_weather',
              arguments: <String, Object?>{'city': '{{city}}'}),
        ],
        tools: tools,
      );
      final SkillTool restored = SkillTool.fromJson(skill.toJson(), tools);
      expect(restored.name, 's');
      expect(restored.steps.single.toolName, 'get_weather');
      expect(restored.toJson()['description'], 'd');
    });
  });

  group('SkillLibrary', () {
    test('未达阈值不提取，达到后命名并注册', () async {
      final ToolRegistry tools = _envTools();
      final SkillLibrary library = SkillLibrary();
      final List<String> tasks = <String>[];

      void record() => library.record('查环境', const <SkillStep>[
            SkillStep(
                toolName: 'get_weather',
                arguments: <String, Object?>{'city': '{{city}}'}),
            SkillStep(
                toolName: 'get_air',
                arguments: <String, Object?>{'city': '{{city}}'}),
          ]);

      record();
      record();
      expect(
        await library.maybeExtract(
            tools: tools,
            namer: (String t, List<String> s) async {
              tasks.add(t);
              return _meta('check_env', '查城市环境');
            }),
        isNull,
      );

      record();
      final SkillTool? skill = await library.maybeExtract(
        tools: tools,
        namer: (String t, List<String> s) async {
          tasks.add(t);
          return _meta('check_env', '查城市环境');
        },
      );

      expect(skill, isNotNull);
      expect(skill!.name, 'check_env');
      expect(tools.get('check_env'), isNotNull);
      expect(tasks.single, '查环境');
      expect(library.skills, hasLength(1));
    });

    test('含 high 风险步骤不沉淀', () async {
      final ToolRegistry tools = _envTools();
      tools.fn('rm',
          riskLevel: ToolRisk.high,
          handler: (ToolContext c) async => ToolResult.success(''));
      final SkillLibrary library = SkillLibrary(threshold: 1)
        ..record('删文件', const <SkillStep>[SkillStep(toolName: 'rm')]);

      final SkillTool? skill = await library.maybeExtract(
        tools: tools,
        namer: (String t, List<String> s) async => _meta('danger', ''),
      );

      expect(skill, isNull);
      expect(tools.get('danger'), isNull);
    });

    test('审批拒绝则不启用', () async {
      final ToolRegistry tools = _envTools();
      final SkillLibrary library = SkillLibrary(
        threshold: 1,
        approval: AutoApproval(false),
      )..record('查环境', const <SkillStep>[
          SkillStep(toolName: 'get_weather'),
        ]);

      final SkillTool? skill = await library.maybeExtract(
        tools: tools,
        namer: (String t, List<String> s) async => _meta('check_env', ''),
      );

      expect(skill, isNull);
      expect(tools.get('check_env'), isNull);
    });

    test('持久化到 Memory 后可由新库恢复', () async {
      final MemoryStore memory = MemoryStore();
      final ToolRegistry tools = _envTools();
      final SkillLibrary library = SkillLibrary(
        threshold: 1,
        memory: memory,
      )..record('查环境', const <SkillStep>[
          SkillStep(
              toolName: 'get_weather',
              arguments: <String, Object?>{'city': '{{city}}'}),
        ]);

      await library.maybeExtract(
        tools: tools,
        namer: (String t, List<String> s) async => _meta('check_env', '查城市环境'),
      );

      final ToolRegistry restoredTools = _envTools();
      final SkillLibrary restored = SkillLibrary(memory: memory);
      final int count = await restored.restore(tools: restoredTools);

      expect(count, 1);
      expect(restoredTools.get('check_env'), isNotNull);
      final ToolResult result = await restoredTools.call(const ToolCall(
        name: 'check_env',
        arguments: <String, Object?>{'city': '上海'},
      ));
      expect(result.content, '上海: 晴');
    });

    test('threshold 非法抛 ArgumentError', () {
      expect(() => SkillLibrary(threshold: 0), throwsArgumentError);
    });
  });

  group('provideSkillLibrary', () {
    test('提供 skill 服务，命名器回退确定性', () {
      final Context ctx = Context.root();
      final ToolRegistry tools = provideTools(ctx);
      tools.fn('t', handler: (ToolContext c) async => ToolResult.success(''));

      final SkillLibrary library = provideSkillLibrary(ctx, tools: tools);

      expect(identical(ctx.skills, library), isTrue);
      expect(library.namer, isA<SkillNamer>());
      ctx.dispose();
    });
  });
}
