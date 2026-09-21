/// `/provider` 命令、provider 浮层与表单浮层。
library;

import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_providers/conatus_providers.dart';
import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

/// 固定回复的假 provider。
class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this._name);

  final String _name;

  @override
  String get name => _name;

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      LlmResult(content: 'ok', provider: _name, model: 'm');

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

ProviderProfile _profile(String name) => ProviderProfile(
      name: name,
      baseUrl: 'https://$name.example/v1',
      credentialKey: '${name.toUpperCase()}_API_KEY',
      models: <String>['$name-small', '$name-large'],
    );

Future<(ConatusTuiController, Context, Directory)> _build({
  bool withProviders = true,
}) async {
  final Directory dir = Directory.systemTemp.createTempSync('tui-provider-');
  final Context app = Context.root();
  provideTools(app);
  provideLlm(app, llm: FallbackLlm(<LlmProvider>[_ScriptedProvider('initial')]));
  provideMemory(app);
  if (withProviders) {
    final ProviderRegistry registry = provideProviders(
      app,
      store: ProviderStore(path: '${dir.path}/providers.json'),
      builtin: <ProviderProfile>[_profile('a'), _profile('b')],
    );
    await registry.load();
  }
  final SessionStore sessions = provideSessions(app);
  final ConatusTuiController controller = ConatusTuiController(
    app: app,
    sessions: sessions,
    name: 'test',
    initialSession: 's1',
    modelLabel: 'initial',
    onExit: () {},
  );
  await controller.start();
  return (controller, app, dir);
}

void main() {
  test('未装配注册表时 /provider 提示未装配', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build(withProviders: false);

    await controller.handleLine('/provider');

    expect(controller.transcript.messages.single.text, contains('未装配'));
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('/provider 打开浮层：列出提供商 + 新增入口，默认选中当前项', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build();

    await controller.handleLine('/provider');

    expect(controller.providerPrompt.open, isTrue);
    expect(
      controller.providerPrompt.items.map((TuiProviderItem i) => i.label),
      <String>['a', 'b', '[ Add New Platform ]'],
    );
    expect(controller.providerPrompt.selected?.name, 'a');
    expect(controller.providerPrompt.selected?.current, isTrue);
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('/provider <名字> 切换：换 LLM 服务、更新标签、重绑', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build();
    final List<String> swapped = <String>[];
    controller.switchLlm =
        (FallbackLlm llm) => swapped.add(llm.providers.first.name);

    await controller.handleLine('/provider b');

    expect(swapped, <String>['b']);
    expect(controller.modelLabel, 'b-small');
    expect(app.providers!.currentName, 'b');
    expect(controller.transcript.messages.last.text, contains('已切换到 b'));
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('浮层 D 删除选中项并刷新列表', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build();
    await controller.handleLine('/provider');

    await controller.deleteSelectedProvider();

    expect(app.providers!.byName('a'), isNull);
    expect(
      controller.providerPrompt.items.map((TuiProviderItem i) => i.label),
      <String>['b', '[ Add New Platform ]'],
    );
    expect(controller.transcript.messages.last.text, contains('已删除提供商：a'));
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('/model 用当前提供商的模型清单', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build();
    final List<String> swapped = <String>[];
    controller.switchLlm = (FallbackLlm llm) =>
        swapped.add(llm.providers.first.name);

    await controller.handleLine('/model');
    expect(controller.transcript.messages.last.text, contains('a-small'));

    await controller.handleLine('/model a-large');
    expect(swapped, <String>['a']);
    expect(controller.modelLabel, 'a-large');

    await controller.handleLine('/model nope');
    expect(controller.transcript.messages.last.text, contains('未知模型'));
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('provider 浮层：默认选中当前项，移动越界钳制', () {
    final TuiProviderPrompt prompt = TuiProviderPrompt();
    prompt.show(<TuiProviderItem>[
      const TuiProviderItem(name: 'a', baseUrl: 'u1', current: false),
      const TuiProviderItem(name: 'b', baseUrl: 'u2', current: true),
      const TuiProviderItem(name: '', baseUrl: '', current: false, isAdd: true),
    ]);

    expect(prompt.index, 1);
    prompt.move(99);
    expect(prompt.index, 2);
    prompt.move(-99);
    expect(prompt.index, 0);
  });

  test('表单：Enter 逐字段前进，末字段提交', () async {
    final TuiFormPrompt form = TuiFormPrompt();
    final Future<Map<String, String>?> pending = form.ask(TuiFormRequest(
      title: 't',
      hint: 'h',
      fields: <TuiFormField>[
        TuiFormField(label: 'A'),
        TuiFormField(label: 'B', obscure: true),
      ],
    ));
    expect(form.open, isTrue);

    form.request!.fields[0].controller.text = 'v1';
    form.next();
    expect(form.index, 1);
    form.request!.fields[1].controller.text = ' v2 ';
    form.next();

    expect(await pending, <String, String>{'A': 'v1', 'B': 'v2'});
    expect(form.open, isFalse);
  });

  test('表单：Esc 取消返回 null', () async {
    final TuiFormPrompt form = TuiFormPrompt();
    final Future<Map<String, String>?> pending = form.ask(TuiFormRequest(
      title: 't',
      hint: 'h',
      fields: <TuiFormField>[TuiFormField(label: 'A')],
    ));

    form.cancel();

    expect(await pending, isNull);
    expect(form.open, isFalse);
  });
}
