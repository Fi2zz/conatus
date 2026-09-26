/// 场景四：失败重试。
///
/// 链路：alerting → reflection → goal。
/// 工具失败触发 [Reflector] 反思：先 `retry` 重试一次，再 `replan` 换方向；
/// 连续失败经 `tool.failed` 事件触发 alerting 的 tool-failures 告警，告警走
/// [ConsoleNotifier] 打到终端。
library;

import 'package:conatus/conatus.dart';
import 'package:test/test.dart';

import 'helpers/fake_search.dart';
import 'helpers/scripted_llm.dart';
import 'helpers/test_harness.dart';

void main() {
  test('失败重试：retry → replan → 换词成功，触发 tool-failures 告警', () async {
    final TestHarness h = await TestHarness.create(
      llmScript: <LlmResult>[
        callTool('c1', 'web_search', <String, Object?>{'query': '不存在的 API'}),
        text('{"decision":"retry"}'),
        text('{"decision":"replan"}'),
        callTool('c3', 'web_search',
            <String, Object?>{'query': 'conatus 集成测试'}),
        text('这个任务试了几次都不行，要换个方法吗？'),
        text('好的，换个方向重新查'),
      ],
      reflectionMaxRetries: 2,
    );
    addTearDown(h.dispose);

    // 外部 IO：搜索（'不存在的 API' 失败，换词成功）+ 工具失败埋点。
    final FakeSearchProvider search = FakeSearchProvider(
      results: <String, List<SearchResult>>{
        'conatus 集成测试': <SearchResult>[
          searchResult('Conatus 集成测试指南', 'https://example.com/conatus'),
        ],
      },
    );
    search.failingQueries.add('不存在的 API');
    provideSearch(h.app, providers: <SearchProvider>[search]);
    provideWebTools(h.app);
    instrumentTools(h.app, telemetry: h.telemetry);

    // 告警：自定义 tool-failures 规则，1 次失败即触发，走终端输出。
    provideAlerting(
      h.app,
      rules: <AlertRule>[
        const AlertRule(
          name: 'tool-failures',
          severity: AlertSeverity.warning,
          condition: _isToolFailure,
          description: '工具连续失败',
        ),
      ],
      notifier: ConsoleNotifier(writer: h.output),
      telemetry: h.telemetry,
    );

    final AgentTurn turn = await h.run('帮我查一下某个不存在的 API');
    final AgentTurn follow = await h.run('换一个');

    // 1) 第一次失败 → retry → 重试又失败 → replan → 换词成功。
    expect(search.queries, <String>[
      '不存在的 API',
      '不存在的 API',
      'conatus 集成测试',
    ]);

    // 2) Reflection 驱动了重试：原始调用 + 换词调用进 steps（重试在反射器
    //    内部完成，不重复记录），搜索实际执行 3 次。
    expect(turn.steps.where((AgentStep s) => s.call.name == 'web_search'),
        hasLength(2));

    // 3) 连续失败触发 tool-failures 告警，终端输出 [WARN]。
    h.expectEvent('tool.failed');
    expect(h.app.alerting.history.map((Alert a) => a.rule),
        contains('tool-failures'));
    h.output.expectContains('[WARN]');
    h.output.expectContains('tool-failures');

    // 4) 第一轮回复提示换方法，用户响应后换方向。
    expect(turn.reply, contains('换个方法'));
    expect(follow.reply, contains('换个方向'));
  }, timeout: const Timeout(Duration(seconds: 30)));
}

/// 工具失败事件即触发。
bool _isToolFailure(TelemetryEvent event, AlertContext _) =>
    event.name == 'tool.failed';
