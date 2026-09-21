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
    modelLabel: 'a-small',
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

  test('/model 打开模型浮层，Enter 切换选中模型', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build();
    final List<String> swapped = <String>[];
    controller.switchLlm =
        (FallbackLlm llm) => swapped.add(llm.providers.first.name);

    await controller.handleLine('/model');

    expect(controller.modelPrompt.open, isTrue);
    expect(
      controller.modelPrompt.matches.map((TuiModelItem m) => m.model),
      <String>['a-small', 'a-large', 'b-small', 'b-large'],
    );
    expect(controller.modelPrompt.selected?.current, isTrue);

    controller.modelPrompt.move(1);
    await controller.confirmModelItem();

    expect(swapped, <String>['a']);
    expect(controller.modelLabel, 'a-large');
    expect(controller.modelPrompt.open, isFalse);
    expect(controller.transcript.messages.last.text, contains('已切换到 a'));
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('模型浮层：搜索过滤与 Tab 切提供商', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build();
    await controller.handleLine('/model');
    final TuiModelPrompt prompt = controller.modelPrompt;

    prompt.setQuery('b-');
    expect(
      prompt.matches.map((TuiModelItem m) => m.model),
      <String>['b-small', 'b-large'],
    );

    prompt.setQuery('');
    prompt.toggleProvider();
    expect(prompt.providerFilter, 'a');
    expect(
      prompt.matches.map((TuiModelItem m) => m.model),
      <String>['a-small', 'a-large'],
    );
    prompt.toggleProvider();
    expect(prompt.providerFilter, 'b');
    prompt.toggleProvider();
    expect(prompt.providerFilter, isNull);
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('模型浮层：窗口滚动跟随选中', () {
    final TuiModelPrompt prompt = TuiModelPrompt();
    prompt.show(<TuiModelItem>[
      for (int i = 0; i < 20; i++)
        TuiModelItem(provider: 'p', model: 'm$i'),
    ]);

    expect(prompt.windowStart, 0);
    prompt.move(15);
    expect(prompt.index, 15);
    expect(prompt.windowStart, 11);
  });

  test('/model <名字> 直接切换（免浮层）', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build();
    final List<String> swapped = <String>[];
    controller.switchLlm =
        (FallbackLlm llm) => swapped.add(llm.providers.first.name);

    await controller.handleLine('/model a-large');

    expect(swapped, <String>['a']);
    expect(controller.modelLabel, 'a-large');
    expect(controller.modelPrompt.open, isFalse);

    await controller.handleLine('/model nope');
    expect(controller.transcript.messages.last.text, contains('未知模型'));
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('/model 与 /provider 是无参命令：菜单 Enter 直接打开浮层', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build();

    final TuiCommand model = controller.commands
        .firstWhere((TuiCommand c) => c.name == 'model');
    final TuiCommand provider = controller.commands
        .firstWhere((TuiCommand c) => c.name == 'provider');
    expect(model.takesArgs, isFalse);
    expect(provider.takesArgs, isFalse);

    await controller.handleLine(model.token);
    expect(controller.modelPrompt.open, isTrue);
    controller.modelPrompt.close();

    await controller.handleLine(provider.token);
    expect(controller.providerPrompt.open, isTrue);
    app.dispose();
    dir.deleteSync(recursive: true);
  });

  test('/plan 打开面板，面板 Enter 切换状态', () async {
    final (ConatusTuiController controller, Context app, Directory dir) =
        await _build();

    await controller.handleLine('/plan');
    expect(controller.planPrompt.open, isTrue);
    expect(controller.planPrompt.active, isFalse);

    await controller.confirmPlanPanel();
    expect(controller.planPrompt.active, isTrue);
    expect(
      controller.transcript.messages.last.text,
      contains('已进入 Plan Mode'),
    );

    await controller.confirmPlanPanel();
    expect(controller.planPrompt.active, isFalse);
    controller.planPrompt.close();
    expect(controller.planPrompt.open, isFalse);
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
