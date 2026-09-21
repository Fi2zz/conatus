part of 'tui_controller.dart';

/// `/provider` 与 `/model` 的提供商 / 模型切换实现。
///
/// 拆成 part 是为了让 `tui_controller.dart` 只保留命令分派：这里集中注册表
/// 读写、浮层数据与 LLM 服务替换。
extension _ProviderCommands on ConatusTuiController {
  /// `/provider [子命令]`：管理模型提供商。
  ///
  /// `list`（默认）打开浮层；`add` 打开导入表单；`remove <名字>` 删除；其余按
  /// 提供商名切换。
  Future<void> _handleProvider(String arg) async {
    final ProviderRegistry? registry = _app.providers;
    if (registry == null) {
      transcript.add(TuiRole.system, '提供商管理未装配：运行时未启用 providers。');
      return;
    }
    final int space = arg.indexOf(' ');
    final String sub = space < 0 ? arg.trim() : arg.substring(0, space).trim();
    final String rest = space < 0 ? '' : arg.substring(space + 1).trim();
    switch (sub) {
      case '' || 'list':
        providerPrompt.show(providerItems(registry));
      case 'add':
        await _importProviders(registry);
      case 'remove' || 'delete':
        await _removeProvider(registry, rest);
      default:
        await _selectProvider(registry, sub);
    }
  }

  /// `/model [名字]`：查看 / 切换当前提供商的模型。
  ///
  /// 装配了注册表时用它的模型清单；否则委托宿主的 [onModelCommand] 钩子。
  Future<void> _handleModel(String arg) async {
    final ProviderRegistry? registry = _app.providers;
    if (registry?.current != null) {
      await _handleModelOf(registry!, arg);
      return;
    }
    final Future<String?> Function(String)? hook = onModelCommand;
    if (hook == null) {
      transcript.add(TuiRole.system, '模型切换未装配：宿主未注入 /model 钩子。');
      return;
    }
    final String? message = await hook(arg);
    if (message != null) {
      transcript.add(TuiRole.system, message);
    }
  }

  Future<void> _handleModelOf(ProviderRegistry registry, String arg) async {
    final ProviderProfile provider = registry.current!;
    if (arg.isEmpty) {
      transcript.add(TuiRole.system, '当前提供商：${provider.name}\n'
          '可用模型：${_modelListText(provider)}\n切换：/model <名字>');
      return;
    }
    if (!provider.models.contains(arg)) {
      transcript.add(
          TuiRole.system, '未知模型：$arg\n可用模型：${_modelListText(provider)}');
      return;
    }
    transcript.add(
        TuiRole.system, await _applyLlm(registry, provider.name, model: arg));
  }

  /// 浮层列表项（末项为新增入口）。
  List<TuiProviderItem> providerItems(ProviderRegistry registry) =>
      <TuiProviderItem>[
        for (final ProviderProfile profile in registry.profiles)
          TuiProviderItem(
            name: profile.name,
            baseUrl: profile.baseUrl,
            current: profile.name == registry.currentName,
          ),
        const TuiProviderItem(name: '', baseUrl: '', current: false, isAdd: true),
      ];

  /// 确认浮层选中项：新增入口 → 导入表单；其余 → 切换提供商。
  Future<void> _confirmProviderItem() async {
    final ProviderRegistry? registry = _app.providers;
    final TuiProviderItem? item = providerPrompt.selected;
    if (registry == null || item == null) {
      return;
    }
    if (item.isAdd) {
      await _importProviders(registry);
      return;
    }
    providerPrompt.close();
    await _selectProvider(registry, item.name);
  }

  /// 删除浮层选中项（新增入口无操作）。
  Future<void> _deleteSelectedProvider() async {
    final ProviderRegistry? registry = _app.providers;
    final TuiProviderItem? item = providerPrompt.selected;
    if (registry == null || item == null || item.isAdd) {
      return;
    }
    await _removeProvider(registry, item.name);
  }

  Future<void> _selectProvider(ProviderRegistry registry, String name) async {
    if (registry.byName(name) == null) {
      transcript.add(TuiRole.system, '未知提供商：$name（/provider 查看列表）');
      return;
    }
    await registry.select(name);
    transcript.add(TuiRole.system, await _applyLlm(registry, name));
  }

  Future<void> _removeProvider(ProviderRegistry registry, String name) async {
    if (registry.byName(name) == null) {
      transcript.add(TuiRole.system, '未知提供商：$name（/provider 查看列表）');
      return;
    }
    await registry.remove(name);
    providerPrompt.refresh(providerItems(registry));
    transcript.add(TuiRole.system, '已删除提供商：$name');
  }

  /// 按 provider（可指定模型）替换 LLM 服务并重绑；返回提示文本。
  Future<String> _applyLlm(
    ProviderRegistry registry,
    String provider, {
    String? model,
  }) async {
    final void Function(FallbackLlm)? swap = switchLlm;
    final LlmProvider? llm = registry.buildLlm(provider, model: model);
    if (swap == null || llm == null) {
      return '无法切换到 $provider：'
          '${swap == null ? '未注入 LLM 替换钩子' : '没有可用模型'}';
    }
    final String label =
        model ?? registry.byName(provider)?.defaultModel ?? provider;
    swap(FallbackLlm(<LlmProvider>[llm]));
    modelLabel = label;
    final bool rebound = await rebind();
    return '已切换到 $provider · $label${rebound ? '' : '（有在途轮次，稍后生效）'}';
  }

  /// 打开导入表单并执行导入。
  Future<void> _importProviders(ProviderRegistry registry) async {
    final Map<String, String>? values = await formPrompt.ask(TuiFormRequest(
      title: 'Import custom provider registry',
      hint: '粘贴 api.json 的 URL 与 Bearer token。',
      fields: <TuiFormField>[
        TuiFormField(label: 'Registry URL', placeholder: 'https://…/api.json'),
        TuiFormField(label: 'Bearer token', obscure: true),
      ],
    ));
    if (values == null) {
      transcript.add(TuiRole.system, '已取消导入。');
      return;
    }
    final String url = values['Registry URL'] ?? '';
    if (url.isEmpty) {
      transcript.add(TuiRole.system, 'Registry URL 不能为空。');
      return;
    }
    final ProviderImportResult result = await registry.importRegistry(
      url: url,
      token: values['Bearer token'] ?? '',
    );
    transcript.add(
      TuiRole.system,
      result.isSuccess
          ? '已导入 ${result.providers.length} 个提供商：'
              '${result.providers.map((ProviderProfile p) => p.name).join('、')}'
          : '导入失败：${result.error}',
    );
    providerPrompt.refresh(providerItems(registry));
  }

  String _modelListText(ProviderProfile provider) =>
      provider.models.isEmpty ? '（未配置）' : provider.models.join('、');
}
