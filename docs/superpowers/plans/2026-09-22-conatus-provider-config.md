# conatus provider 配置收敛 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 conatus 的模型提供商定义（含 Key）统一收敛到 `~/.nava/config.toml` 的 `[providers.<名字>]` 表，废弃 `providers.json` 注册表与模型 Key 的 `[credentials]`/环境变量来源。

**Architecture:** config 层新增 `[providers.*]` 解析（`ProviderConfig`：`name`/`baseUrl`/`apiKey`/`type`/`oauthKey`）与 `[llm] default_model = "provider/model"`；`ProviderRegistry` 保留为运行时抽象但数据源换成 config（去掉 `ProviderStore` 持久化）；`/provider` 退化为只读展示。所有改动集中在 `packages/conatus_code` 子模块。

**Tech Stack:** Dart 3.10+、`toml` 0.18、`conatus_llm`（`LlmApiStyle`）、`conatus_credentials`。

**Spec:** `docs/superpowers/specs/2026-09-22-conatus-provider-config-design.md`

## Global Constraints

- 仓库 AGENTS.md 硬约束：函数体 ≤40 行、class ≤150 行、单文件 ≤200 行（测试文件不受限）、函数参数 ≤4（超限必须加 `// REASON:`）、每函数 if/else/switch ≤3（按语句级控制流计）、嵌套 ≤2。
- 仓库未强制 `dart format`——不要跑它；风格对齐周围代码（单引号、`library;` 指令、中文文档注释）。
- `packages/conatus_code` 是独立 git 子模块（remote `git@github.com:Fi2zz/conatus_code.git`）；**实现与提交都在子模块内**，根仓库只提交 gitlink（`git add packages/conatus_code && git commit -m "chore(code): 同步子模块 gitlink"`）。
- 破坏性变更（用户已确认）：`ConatusTuiRuntime.create` 的 `providers`（bool）/`providersFile` 形参移除，新增 `List<ProviderConfig>? providers`；`[llm] provider`/`model` 两字段被 `default_model` 替代；`/provider` 不再增删改；`providers.json` 不再读写。
- 每个任务末尾提交一次；测试命令在 `packages/conatus_code` 目录执行（`dart analyze` / `dart test`）。

## Review Focus

以下输入/失败模式 spec 没有逐条列测试，但用户会撞上；每条都在对应任务的测试里钉住：

1. **`[llm] default_model` 格式非法**（无 `/`、`/` 在开头或结尾）→ 启动报 `ConfigException`（Task 1 钉）。
2. **`default_model` 的 provider 名不在 `[providers]`** → 启动报「未知提供商：<name>」而不是去翻 providers.json（Task 4 钉）。
3. **provider 配了 `oauth` 且 `api_key` 为空** → 启动提示「OAuth 未实现」，该 provider 不可用但其余照常（Task 4 钉）。
4. **`[providers]` 空或没有 `default_model`** → 启动报「请在 config.toml 配置 [providers.xxx] 与 [llm] default_model」（Task 4 钉）。
5. **名字含 `.`/`:` 的 provider**（TOML 引号键，如 `"managed:kimi-code"`）→ 正确解析（Task 1 钉）。

---

## 文件结构

| 文件                                        | 职责                                                                                                      |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `lib/src/config/config_schema.dart`         | 新增 `ProviderType` / `ProviderConfig`；`LlmConfig` 改 `defaultModel`；`ConatusCodeConfig` 加 `providers` |
| `lib/src/config/config_parser.dart`         | 解析 `[providers.*]`（含引号键、type 映射、oauth 子表）与 `[llm] default_model`                           |
| `lib/src/providers/provider_registry.dart`  | 去掉 `ProviderStore`/增删改/导入，构造改为 `profiles`+`currentName`                                       |
| `lib/src/providers/providers_provider.dart` | `provideProviders` 改为接收 provider 列表                                                                 |
| `lib/src/providers/provider_store.dart`     | **删除**                                                                                                  |
| `lib/src/providers/provider_defaults.dart`  | **删除**                                                                                                  |
| `lib/src/providers/provider_import.dart`    | **删除**                                                                                                  |
| `lib/providers.dart`                        | barrel 收敛（去 store/import 导出）                                                                       |
| `lib/src/tui/tui_app.dart`                  | `create` 形参改造 + 装配 + oauth 提示 + 错误处理                                                          |
| `bin/conatus_code.dart`                     | `default_model` 拆分 + 传 `config.providers`                                                              |
| `lib/src/tui/tui_controller_provider.dart`  | `/provider` 只读展示 + `/model` 改模型名                                                                  |
| `lib/src/tui/tui_provider.dart`             | `TuiProviderItem` 去 `isAdd`                                                                              |
| `lib/src/tui/tui_provider_view.dart`        | 按键提示文案去掉「D 删除」                                                                                |
| `lib/src/tui/tui.dart`                      | `_onProviderKey` 去掉 D 删除分支                                                                          |
| `example/playground.dart`                   | 去掉 `ProviderStore` 用法                                                                                 |
| `README.md` / `CHANGELOG.md`                | 配置示例与变更记录                                                                                        |

---

## Task 1: config schema + parser（[providers.*] / default_model）

**Files:**

- Modify: `packages/conatus_code/lib/src/config/config_schema.dart`
- Modify: `packages/conatus_code/lib/src/config/config_parser.dart`
- Test: `packages/conatus_code/test/config/config_loader_test.dart`

**Interfaces:**

- Produces: `enum ProviderType { openai, kimi }`；`class ProviderConfig { final String name; final String baseUrl; final String apiKey; final ProviderType type; final String? oauthKey; }`；`LlmConfig({this.defaultModel})`；`ConatusCodeConfig.providers`（`List<ProviderConfig>`，按 TOML 书写顺序）。

- [ ] **Step 1: 写失败测试**

在 `test/config/config_loader_test.dart` 追加（文件头部已 import `package:conatus_code/conatus_code.dart`；`loadConfig` 的用法看该文件既有用例）：

```dart
  test('解析 [providers.*]：引号键、type 映射、oauth 子表', () {
    final ConatusCodeConfig config = loadConfigFromToml('''
[providers.arkcli-agent-plan]
api_key = "ark-1"
base_url = "https://ark.cn-beijing.volces.com/api/plan/v3"
type = "openai"

[providers."managed:kimi-code"]
api_key = ""
base_url = "https://api.kimi.com/coding/v1"
type = "kimi"
[providers."managed:kimi-code".oauth]
key = "oauth/kimi-code"
storage = "file"

[llm]
default_model = "arkcli-agent-plan/doubao-seed-2-0-lite-260215"
''');

    expect(config.providers, hasLength(2));
    final ProviderConfig ark = config.providers[0];
    expect(ark.name, 'arkcli-agent-plan');
    expect(ark.apiKey, 'ark-1');
    expect(ark.type, ProviderType.openai);

    final ProviderConfig kimi = config.providers[1];
    expect(kimi.name, 'managed:kimi-code');
    expect(kimi.apiKey, '');
    expect(kimi.type, ProviderType.kimi);
    expect(kimi.oauthKey, 'oauth/kimi-code');
    expect(config.llm.defaultModel, 'arkcli-agent-plan/doubao-seed-2-0-lite-260215');
  });

  test('default_model 格式非法抛 ConfigException', () {
    expect(
      () => loadConfigFromToml('[llm]\ndefault_model = "no-slash"'),
      throwsA(isA<ConfigException>()),
    );
    expect(
      () => loadConfigFromToml('[llm]\ndefault_model = "/model"'),
      throwsA(isA<ConfigException>()),
    );
  });

  test('未知 type 抛 ConfigException；base_url 缺失抛 ConfigException', () {
    expect(
      () => loadConfigFromToml('''
[providers.x]
base_url = "https://x"
type = "anthropic"
'''),
      throwsA(isA<ConfigException>()),
    );
    expect(
      () => loadConfigFromToml('[providers.x]\napi_key = "k"'),
      throwsA(isA<ConfigException>()),
    );
  });
```

`loadConfigFromToml` 需要你先看一眼 `config_loader_test.dart` 的既有 helper——如果已有「从字符串解析」的 helper（如 `_load(String)` 写临时文件后调 `loadConfig`），复用它的形态；没有就在文件里加一个（用 `Directory.systemTemp` 写临时文件，参考该文件既有 setUp/tearDown 风格）。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/fitz/REPO/conatus/packages/conatus_code && dart test test/config/config_loader_test.dart`
Expected: 编译失败 —— `ProviderConfig` / `ProviderType` 未定义

- [ ] **Step 3: 改 schema**

`lib/src/config/config_schema.dart`：把 `LlmConfig` 替换为：

```dart
/// LLM 选择：`provider/model` 同时定当前提供商与默认模型。
class LlmConfig {
  const LlmConfig({this.defaultModel});

  /// `provider/model`（如 `'arkcli-agent-plan/doubao-seed-2-0-lite-260215'`）；
  /// `null` 表示缺省取注册表首个提供商。
  final String? defaultModel;
}
```

在 `AgentConfig` 前新增：

```dart
/// provider 类型：决定请求形态（都走 OpenAI 兼容客户端）。
enum ProviderType {
  /// `chat/completions` 形态。
  openai,

  /// `responses` 形态。
  kimi,
}

/// 一个模型提供商的配置（对应 `[providers.<name>]` 表）。
class ProviderConfig {
  const ProviderConfig({
    required this.name,
    required this.baseUrl,
    this.apiKey = '',
    this.type = ProviderType.openai,
    this.oauthKey,
  });

  /// 提供商名（`[providers.<name>]` 的键，可含 `.` / `:`）。
  final String name;

  /// OpenAI 兼容端点根地址。
  final String baseUrl;

  /// API Key；空串表示无 Key。
  final String apiKey;

  /// 请求形态。
  final ProviderType type;

  /// `oauth` 子表的 `key`；保留但不实现 OAuth 调用。
  final String? oauthKey;
}
```

`ConatusCodeConfig` 构造加 `this.providers = const <ProviderConfig>[]`，字段加：

```dart
  /// `[providers.<name>]` 表，保持 TOML 书写顺序。
  final List<ProviderConfig> providers;
```

- [ ] **Step 4: 改 parser**

`lib/src/config/config_parser.dart` 的 `parse()` 加 `providers: _readProviders(),`（放在 `llm:` 之后），`_readLlm()` 替换为：

```dart
  LlmConfig _readLlm() {
    final Map<String, dynamic> table = readTable('llm');
    final String? defaultModel = readString(table, 'default_model');
    if (defaultModel != null && !_validDefaultModel(defaultModel)) {
      throw ConfigException('$source：llm.default_model 必须是 "provider/model" 形式。');
    }
    return LlmConfig(defaultModel: defaultModel);
  }

  bool _validDefaultModel(String value) {
    final int slash = value.indexOf('/');
    return slash > 0 && slash < value.length - 1;
  }

  List<ProviderConfig> _readProviders() {
    final Map<String, dynamic> table = readTable('providers');
    return <ProviderConfig>[
      for (final MapEntry<String, dynamic> entry in table.entries)
        _readProvider(entry.key, entry.value),
    ];
  }

  ProviderConfig _readProvider(String name, Object? raw) {
    if (raw is! Map) {
      throw ConfigException('$source：providers.$name 必须是表。');
    }
    final Map<String, dynamic> table = raw.cast<String, dynamic>();
    final String baseUrl = readString(table, 'base_url') ?? '';
    if (baseUrl.isEmpty) {
      throw ConfigException('$source：providers.$name.base_url 不能为空。');
    }
    return ProviderConfig(
      name: name,
      baseUrl: baseUrl,
      apiKey: readString(table, 'api_key') ?? '',
      type: _providerType(table, name),
      oauthKey: _readOauthKey(table, name),
    );
  }

  ProviderType _providerType(Map<String, dynamic> table, String name) {
    final String? value = readString(table, 'type');
    if (value == null) return ProviderType.openai;
    return switch (value) {
      'openai' => ProviderType.openai,
      'kimi' => ProviderType.kimi,
      _ => throw ConfigException('$source：providers.$name.type 取值 "$value" 不合法。'),
    };
  }

  String? _readOauthKey(Map<String, dynamic> table, String name) {
    final Object? oauth = table['oauth'];
    if (oauth == null) return null;
    if (oauth is! Map) {
      throw ConfigException('$source：providers.$name.oauth 必须是表。');
    }
    final Object? key = oauth['key'];
    if (key != null && key is! String) {
      throw ConfigException('$source：providers.$name.oauth.key 必须是字符串。');
    }
    return key as String?;
  }
```

注意 `_readProviders` / `_readProvider` / `_readOauthKey` 的行数都在 40 行内；`_readProvider` 有 2 个 if（语句级）。

- [ ] **Step 5: 跑测试确认通过**

Run: `cd /Users/fitz/REPO/conatus/packages/conatus_code && dart test test/config/config_loader_test.dart && dart analyze`
Expected: 全绿 + `No issues found!`

- [ ] **Step 6: 提交**

```bash
git add lib/src/config/config_schema.dart lib/src/config/config_parser.dart test/config/config_loader_test.dart
git commit -m "feat(config): 新增 [providers.*] 表解析与 [llm] default_model"
```

---

## Task 2: ProviderRegistry 去 store + provideProviders 改造

**Files:**

- Modify: `packages/conatus_code/lib/src/providers/provider_registry.dart`
- Modify: `packages/conatus_code/lib/src/providers/providers_provider.dart`
- Test: `packages/conatus_code/test/providers/provider_registry_test.dart`

**Interfaces:**

- Consumes: `ProviderProfile`（`name`/`baseUrl`/`apiKey`/`apiStyle`，`conatus_llm` 的 `LlmApiStyle`）；`Credentials`。
- Produces: `ProviderRegistry({List<ProviderProfile> profiles, String? currentName, Credentials? credentials})`（**不再有 `store`**；`load`/`add`/`remove`/`select`/`importRegistry` 全部移除）；`provideProviders(ctx, {required List<ProviderProfile> providers, String? currentName, Credentials? credentials})`。

- [ ] **Step 1: 重写 registry**

`lib/src/providers/provider_registry.dart` 整体替换为（去掉 `ProviderStore`、持久化与增删改/导入，`_current` 变为 final）：

```dart
/// 提供商注册表：只读视图、按名查找与 LlmProvider 构造。
library;

import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_llm/conatus_llm.dart';

import 'provider_profile.dart';

/// 模型提供商注册表（只读：数据源是 config.toml 的 `[providers.*]`）。
class ProviderRegistry {
  ProviderRegistry({
    List<ProviderProfile> profiles = const <ProviderProfile>[],
    String? currentName,
    Credentials? credentials,
  })  : _profiles = List<ProviderProfile>.of(profiles),
        _current = currentName,
        _credentials = credentials;

  final List<ProviderProfile> _profiles;

  /// Key 的来源（缺省不注入时配置内 `apiKey` 为空即无 Key）。
  final Credentials? _credentials;

  /// 当前选中的提供商名（装配期决定，运行期不变）。
  final String? _current;

  /// 全部提供商（只读视图）。
  List<ProviderProfile> get profiles =>
      List<ProviderProfile>.unmodifiable(_profiles);

  /// 当前选中的提供商名。
  String? get currentName => _current;

  /// 当前选中的提供商。
  ProviderProfile? get current => byName(_current);

  /// 按名查找；不存在返回 `null`。
  ProviderProfile? byName(String? name) {
    if (name == null) {
      return null;
    }
    for (final ProviderProfile profile in _profiles) {
      if (profile.name == name) {
        return profile;
      }
    }
    return null;
  }

  /// 按名构造 OpenAI 兼容提供商；无此 provider 或没有模型名时返回 `null`。
  ///
  /// Key 解析顺序：配置内 `apiKey` → 注入的 [Credentials]。
  LlmProvider? buildLlm(String name, {String? model}) {
    final ProviderProfile? profile = byName(name);
    final String resolvedModel = model ?? profile?.defaultModel ?? '';
    if (profile == null || resolvedModel.isEmpty) {
      return null;
    }
    return OpenAiCompatibleProvider(
      name: profile.name,
      baseUrl: profile.baseUrl,
      model: resolvedModel,
      credentialKey: profile.credentialKey,
      apiStyle: profile.apiStyle,
      userAgent: profile.userAgent.isEmpty ? kDefaultLlmUserAgent : profile.userAgent,
      apiKey: profile.apiKey.isEmpty ? null : profile.apiKey,
      credentials: _credentials,
    );
  }

  /// 该提供商是否已有可用 Key（配置内 `apiKey` 或凭据服务命中）。
  bool hasKey(String name) {
    final ProviderProfile? profile = byName(name);
    if (profile == null) {
      return false;
    }
    if (profile.apiKey.isNotEmpty) {
      return true;
    }
    return _credentials?.get(profile.credentialKey) != null;
  }
}
```

> 注意：本任务改完 `ProviderRegistry` 构造后，`tui_app.dart` 里传 `store:` 的调用会编译失败——这是**预期的中间状态**，Task 4 修复。本任务的验证只跑 `dart test test/providers/provider_registry_test.dart` 与 `dart analyze lib/src/providers`（整包 analyze 在 Task 4 前不做要求）。

- [ ] **Step 2: 改 provideProviders**

`lib/src/providers/providers_provider.dart` 替换为：

```dart
/// 装配：把 [ProviderRegistry] 作为 `'providers'` 服务提供到上下文。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_credentials/conatus_credentials.dart';

import 'provider_profile.dart';
import 'provider_registry.dart';

/// `ctx.providers`：当前上下文可见的注册表。
extension ProvidersContext on Context {
  /// 取注册表；未提供返回 `null`。
  ProviderRegistry? get providers => get<ProviderRegistry>('providers');
}

/// 提供注册表为 `'providers'` 服务（数据源是 config.toml 的 `[providers.*]`）。
///
/// [currentName] 缺省取列表首个；[credentials] 是 Key 的回退来源。
ProviderRegistry provideProviders(
  Context ctx, {
  required List<ProviderProfile> providers,
  String? currentName,
  Credentials? credentials,
}) {
  final ProviderRegistry registry = ProviderRegistry(
    profiles: providers,
    currentName:
        currentName ?? (providers.isEmpty ? null : providers.first.name),
    credentials: credentials,
  );
  ctx.provide('providers', registry);
  return registry;
}
```

- [ ] **Step 3: 更新 registry 测试**

`test/providers/provider_registry_test.dart`：把用 `ProviderStore` / `load()` / `add()` / `remove()` / `select()` / `importRegistry` 的用例**删除或改写**，保留并改写「构造 → byName / currentName / buildLlm / hasKey」的用例。最小形态（替换整个文件，`_FakeCredentials` 从 `conatus_credentials` 的 `InMemoryCredentials` 拿）：

```dart
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

ProviderProfile profile(String name, {String? model}) => ProviderProfile(
      name: name,
      baseUrl: 'https://$name.example/v1',
      apiKey: 'key-$name',
      models: <String>[model ?? '$name-model'],
    );

void main() {
  test('构造即定 profiles 与 currentName，缺省取首个', () {
    final ProviderRegistry registry = ProviderRegistry(
      profiles: <ProviderProfile>[profile('a'), profile('b')],
    );

    expect(registry.profiles.map((ProviderProfile p) => p.name),
        <String>['a', 'b']);
    expect(registry.currentName, 'a');
    expect(registry.current!.name, 'a');
    expect(registry.byName('b'), isNotNull);
    expect(registry.byName('nope'), isNull);
  });

  test('显式 currentName 覆盖首个', () {
    final ProviderRegistry registry = ProviderRegistry(
      profiles: <ProviderProfile>[profile('a'), profile('b')],
      currentName: 'b',
    );

    expect(registry.currentName, 'b');
  });

  test('buildLlm 按名构造；无 provider 或模型返回 null', () {
    final ProviderRegistry registry = ProviderRegistry(
      profiles: <ProviderProfile>[profile('a')],
      credentials: InMemoryCredentials(),
    );

    final LlmProvider? llm = registry.buildLlm('a');
    expect(llm, isNotNull);
    expect(llm!.name, 'a');
    expect(registry.buildLlm('a', model: 'x'), isNotNull);
    expect(registry.buildLlm('nope'), isNull);
    expect(
      registry.buildLlm('a', model: ''),
      isNull,
    );
  });

  test('hasKey：apiKey 非空即 true，否则看凭据服务', () {
    final ProviderRegistry registry = ProviderRegistry(
      profiles: <ProviderProfile>[profile('a')],
      credentials: InMemoryCredentials(
        initial: <String, String>{'OTHER': 'v'},
      ),
    );

    expect(registry.hasKey('a'), isTrue);
    expect(registry.hasKey('nope'), isFalse);
  });
}
```

（`profile('a')` 带 `apiKey`，所以 `hasKey('a')` 恒 true；若想测凭据回退，把 `apiKey` 置空并用带 `credentialKey` 的 profile——本文件只需覆盖基本路径。）

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /Users/fitz/REPO/conatus/packages/conatus_code && dart test test/providers/provider_registry_test.dart && dart analyze`
Expected: 全绿 + `No issues found!`

- [ ] **Step 5: 提交**

```bash
git add lib/src/providers/provider_registry.dart lib/src/providers/providers_provider.dart test/providers/provider_registry_test.dart
git commit -m "refactor(providers): 注册表去掉持久化与增删改，数据源改为装配期注入"
```

---

## Task 3: 删除 ProviderStore / provider_defaults / provider_import，收敛 barrel

**Files:**

- Delete: `packages/conatus_code/lib/src/providers/provider_store.dart`
- Delete: `packages/conatus_code/lib/src/providers/provider_defaults.dart`
- Delete: `packages/conatus_code/lib/src/providers/provider_import.dart`
- Modify: `packages/conatus_code/lib/providers.dart`

- [ ] **Step 1: 删除三个文件并更新 barrel**

```bash
cd /Users/fitz/REPO/conatus/packages/conatus_code
git rm lib/src/providers/provider_store.dart lib/src/providers/provider_defaults.dart lib/src/providers/provider_import.dart
```

`lib/providers.dart` 整体替换为：

```dart
/// conatus_code 的模型提供商管理：`ProviderProfile` 装配与只读注册表。
///
/// 数据源是 `~/.nava/config.toml` 的 `[providers.*]` 表（见
/// `lib/src/config/`）；本入口供 `/provider`（只读展示）与按 profile 构造
/// OpenAI 兼容 `LlmProvider`。
///
/// **实验性**：API 可能在没有 major 版本变更的情况下调整，勿在生产环境依赖。
library;

export 'src/providers/builtin_providers.dart'
    show DeepSeekProvider, DoubaoProvider;
export 'src/providers/provider_profile.dart' show ProviderProfile;
export 'src/providers/provider_registry.dart' show ProviderRegistry;
export 'src/providers/providers_provider.dart'
    show ProvidersContext, provideProviders;
```

- [ ] **Step 2: 跑整包测试与静态检查**

Run: `cd /Users/fitz/REPO/conatus/packages/conatus_code && dart analyze && dart test`
Expected: `dart analyze lib bin example` 零 issue；`dart test` 全绿（若 `test/tui/tui_provider_command_test.dart` / `test/tui/tui_model_view_test.dart` 因引用已删的 `ProviderStore` 而编译失败，属**预期中间状态**——Task 4 改装配测试、Task 5 重写 `/provider` 测试；可先做 Task 4、Task 5 再回跑本任务验证）。

- [ ] **Step 3: 提交**

```bash
git add -A
git commit -m "refactor(providers): 删除 ProviderStore 与内置默认清单，barrel 收敛"
```

---

## Task 4: tui_app 装配 + bin 接线 + 错误处理

**Files:**

- Modify: `packages/conatus_code/lib/src/tui/tui_app.dart`
- Modify: `packages/conatus_code/bin/conatus_code.dart`
- Test: `packages/conatus_code/test/tui/tui_model_view_test.dart`（装配相关用例适配）

**Interfaces:**

- Consumes: `ProviderConfig` / `ProviderType`（Task 1）；`provideProviders(ctx, {providers, currentName, credentials})`（Task 2）。
- Produces: `ConatusTuiRuntime.create({..., List<ProviderConfig>? providers, String? provider, String? model, ...})` —— `providers`（bool）与 `providersFile` 形参移除。

- [ ] **Step 1: 改 create 形参与装配**

`lib/src/tui/tui_app.dart`：

1. 形参区：把

```dart
    bool webTools = true,
    bool skills = true,
    bool providers = true,
    String? providersFile,
    String? provider,
    String? model,
```

替换为：

```dart
    bool webTools = true,
    bool skills = true,
    List<ProviderConfig>? providers,
    String? provider,
    String? model,
```

2. 装配段（当前 `if (providers) { registry = provideProviders(app, store: ...); await registry.load(); }`）替换为：

```dart
    ProviderRegistry? registry;
    if (providers != null) {
      registry = provideProviders(
        app,
        providers: <ProviderProfile>[
          for (final ProviderConfig config in providers)
            ProviderProfile(
              name: config.name,
              baseUrl: config.baseUrl,
              apiKey: config.apiKey,
              apiStyle: config.type == ProviderType.kimi
                  ? LlmApiStyle.responses
                  : LlmApiStyle.chat,
            ),
        ],
        currentName: provider,
        credentials: resolvedCredentials,
      );
      for (final ProviderConfig config in providers) {
        if (config.apiKey.isEmpty && config.oauthKey != null) {
          // REASON: 启动提示走 stdout，与其它装配警告一致（OAuth 未实现，
          // 该 provider 不可用但其余照常）。
          print('OAuth 未实现：请为 ${config.name} 配置 api_key。');
        }
      }
    }
    if (provider != null && registry?.byName(provider) == null) {
      throw StateError('未知提供商：$provider（config.toml [providers] 里没有）');
    }
```

3. `fromRegistry` 与错误文案（当前 `provider ?? registry.currentName ?? ''` 与 `StateError('未装配 LLM：请配置 providers.json 的当前提供商...')`）改为：

```dart
    final LlmProvider? fromRegistry = registry?.buildLlm(
      provider ?? registry.currentName ?? '',
      model: model,
    );
    // 预算护栏：包装 `'llm'` 服务（每轮墙钟 + 上下文 token 估算），并把首个
    // CostTracker 实现注册到 `'costTracker'`（供未来 autonomous runner 消费）。
    final CostTrackerImpl costTracker = CostTrackerImpl();
    app.provide('costTracker', costTracker);
    final TurnBudget resolvedBudget = turnBudget ?? const TurnBudget();
    if (llm == null && fromRegistry == null) {
      throw StateError(
          '未装配 LLM：请在 config.toml 配置 [providers.xxx] 与 [llm] default_model。');
    }
```

4. `// REASON:` 参数计数注释（`本参数已 16 个`）改成 17（形参：sessionDir、memoryFile、baseDir、webTools、skills、providers、provider、model、maxSteps、llm、turnBudget、modelLabel、fs、shell、credentials = 15 + 新增……数一遍：`providers`（列表）替换 bool，`providersFile` 删除，所以净 -0；实际数：sessionDir, memoryFile, baseDir, webTools, skills, providers, provider, model, maxSteps, llm, turnBudget, modelLabel, fs, shell, credentials = **15**）。把注释改成 `本参数已 15 个`。

5. 顶部 import 增加 `import '../config/config_schema.dart';`（若还没有）。

- [ ] **Step 2: 改 bin**

`bin/conatus_code.dart` 的 `create` 调用改为：

```dart
  final String? defaultModel = config.llm.defaultModel;
  String? provider;
  String? model;
  if (defaultModel != null) {
    final int slash = defaultModel.indexOf('/');
    provider = defaultModel.substring(0, slash);
    model = defaultModel.substring(slash + 1);
  }
  final ConatusTuiRuntime runtime = await ConatusTuiRuntime.create(
    baseDir: '$workdir$sep${config.agent.projectDir}',
    providers: config.providers,
    provider: provider,
    model: model,
    maxSteps: config.agent.maxSteps,
    turnBudget: TurnBudget(
      maxDuration: config.budget.maxTurnSeconds == null
          ? null
          : Duration(seconds: config.budget.maxTurnSeconds!),
      maxTokens: config.budget.maxTurnTokens,
    ),
    credentials: ConfigCredentials(config),
    fs: layers.fs,
    shell: layers.shell,
  );
```

- [ ] **Step 3: 适配装配测试**

`test/tui/tui_model_view_test.dart` 里用 `provideProviders(app, store: ProviderStore(path: ...))` + `registry.load()` 的装配段，改为：

```dart
    provideProviders(
      app,
      providers: <ProviderProfile>[
        ProviderProfile(
          name: 'a',
          baseUrl: 'https://a.example/v1',
          apiKey: 'k',
          models: <String>['a-model'],
        ),
      ],
      currentName: 'a',
    );
```

（具体用例里的 provider 名/模型名以该文件现有断言为准，只换装配形态；若该文件还有别处引用 `ProviderStore`，一并替换或删除。）

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /Users/fitz/REPO/conatus/packages/conatus_code && dart analyze && dart test`
Expected: `No issues found!` + 全绿（若 `tui_provider_command_test.dart` 仍因旧 /provider 逻辑失败，先做 Task 5 再回跑——**顺序允许先做 Task 5**。）

- [ ] **Step 5: 提交**

```bash
git add lib/src/tui/tui_app.dart bin/conatus_code.dart test/tui/tui_model_view_test.dart
git commit -m "feat(tui): 装配改用 config 的 [providers] 列表，default_model 定当前提供商与模型"
```

---

## Task 5: /provider 只读展示 + /model 改模型名

**Files:**

- Modify: `packages/conatus_code/lib/src/tui/tui_controller_provider.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_provider.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui_provider_view.dart`
- Modify: `packages/conatus_code/lib/src/tui/tui.dart`
- Test: `packages/conatus_code/test/tui/tui_provider_command_test.dart`

- [ ] **Step 1: 改 /provider 为只读**

`lib/src/tui/tui_controller_provider.dart` 的 `_handleProvider` 替换为：

```dart
  /// `/provider`：只读展示 config 里配置的提供商（增删改走 config.toml）。
  Future<void> _handleProvider(String arg) async {
    final ProviderRegistry? registry = _app.providers;
    if (registry == null) {
      transcript.add(TuiRole.system, '提供商管理未装配：config.toml 未配置 [providers]。');
      return;
    }
    providerPrompt.show(providerItems(registry));
  }
```

`providerItems` 替换为（去掉末项「Add New Platform」）：

```dart
  /// 浮层列表项（只读：仅展示 config 配置的提供商）。
  List<TuiProviderItem> providerItems(ProviderRegistry registry) =>
      <TuiProviderItem>[
        for (final ProviderProfile profile in registry.profiles)
          TuiProviderItem(
            name: profile.name,
            baseUrl: profile.baseUrl,
            current: profile.name == registry.currentName,
          ),
      ];
```

删除 `_confirmProviderItem` / `_deleteSelectedProvider` / `_selectProvider` / `_removeProvider` / `_importProviders`，并删除 `_applyLlm` 里 `registry.select` 相关调用（`_applyLlm` 本身保留，/model 用）。`_handleModelOf` 替换为：

```dart
  Future<void> _handleModelOf(ProviderRegistry registry, String arg) async {
    if (arg.isEmpty) {
      transcript.add(TuiRole.system, '当前提供商：${registry.currentName}\n'
          '用法：/model <模型名>');
      return;
    }
    transcript.add(TuiRole.system,
        await _applyLlm(registry, registry.currentName ?? '', model: arg));
  }
```

`modelItems` / `_confirmModelItem` 删除（无 models 清单，/model 不再有浮层候选）；若 `TuiModelPrompt` 因此无人使用，保留类定义但确认没有编译引用（`tui_model.dart` / `tui_model_view.dart` 保留，模型浮层可后续删）。

- [ ] **Step 2: tui_provider.dart 去 isAdd**

`lib/src/tui/tui_provider.dart` 的 `TuiProviderItem`：删除 `isAdd` 字段与构造参数，`label` getter 改为 `=> name;`。`TuiProviderPrompt` 其余不变。

- [ ] **Step 3: tui_provider_view.dart 文案**

`lib/src/tui/tui_provider_view.dart` 的按键提示行改为 `'↑↓ 选择 · Esc 取消'`（去掉「Enter 切换 · D 删除」）。

- [ ] **Step 4: tui.dart 去 D 删除键**

`lib/src/tui/tui.dart` 的 `_onProviderKey`：删掉 `else if (event.logicalKey == LogicalKey.keyD) { unawaited(_controller.deleteSelectedProvider()); }` 分支；Enter 分支改为只关浮层——把 `unawaited(_controller.confirmProviderItem());` 替换为 `prompt.close();`（`deleteSelectedProvider` / `confirmProviderItem` 在 `tui_controller.dart` 的公开包装方法一并删除）。

- [ ] **Step 5: 重写 /provider 测试**

`test/tui/tui_provider_command_test.dart` 整体重写为只读展示断言（沿用该文件既有的 `_build` 装配 helper，但 `provideProviders` 用 Task 4 的新形态）：

```dart
import 'package:conatus_code/conatus_code.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

// ...（保留该文件原有的 _ScriptedProvider 与 _build 装配 helper，
// 把其中的 ProviderStore 装配换成 provideProviders(providers: [...], currentName: 'a')）

  test('/provider 只读展示：列出 provider 与当前标记', () async {
    final ConatusTuiController controller = _build();   // 装配注册表（含 'a'）
    controller.handleLine('/provider');
    // 断言 transcript 或 providerPrompt 状态：providerPrompt.items 含 'a' 且 current
    // （以该文件既有断言风格为准——先读现有用例，保持相同的断言对象与写法）
  });
```

先读现有测试文件再写断言（它之前测增删改查，现在只保留「list 展示」与「/model 切换」两类用例；`/model` 用例改成直接 `handleLine('/model m1')` 并断言 LLM 被替换为模型 m1 的实例）。

- [ ] **Step 6: 跑测试确认通过**

Run: `cd /Users/fitz/REPO/conatus/packages/conatus_code && dart analyze && dart test`
Expected: `No issues found!` + 全绿

- [ ] **Step 7: 提交**

```bash
git add lib/src/tui/tui_controller_provider.dart lib/src/tui/tui_provider.dart lib/src/tui/tui_provider_view.dart lib/src/tui/tui.dart test/tui/tui_provider_command_test.dart
git commit -m "feat(tui): /provider 退化为只读展示，/model 直接切换模型名"
```

---

## Task 6: example 适配 + 文档

**Files:**

- Modify: `packages/conatus_code/example/playground.dart`
- Modify: `packages/conatus_code/README.md`
- Modify: `packages/conatus_code/CHANGELOG.md`

- [ ] **Step 1: playground 去 ProviderStore**

`example/playground.dart` 里 `ProviderStore` / `ProviderSnapshot` 的用法（读 `.conatus/providers.json` 判断 `configured`）替换为环境变量判断：

```dart
  final EnvCredentials envCredentials = EnvCredentials();
  // 是否已配置 Key：凭据服务命中模型 Key（config.toml [credentials] / 环境变量）。
  final bool configured = envCredentials.get('ARK_API_KEY') != null ||
      envCredentials.get('DEEPSEEK_API_KEY') != null;
```

删除 `ProviderStore` / `ProviderSnapshot` 的 import 与变量；`ConatusTuiRuntime.create(...)` 的调用保持 `llm: configured ? null : ...`（configured 时仍需注册表——**改为**同时传 `providers:`（从 config 读？playground 无 config）——**最小改法**：playground 不传 `providers`（null），`configured` 时也显式构造 `OpenAiCompatibleProvider` 传入 `llm:`，避免依赖注册表。若该改动超出 playground 的 demo 意图，可在报告里说明并保留 `llm: configured ? null : FallbackLlm(...)` + 传 `providers: <ProviderProfile>[...]`（从 `EnvCredentials` 读 Key 构造两个 profile）。

先读 `playground.dart` 当前实现再改，保证 `dart analyze example` 零 issue。

- [ ] **Step 2: README 配置示例**

`README.md` 的「配置」章节的 TOML 示例替换为（`[credentials]` / `[llm] default_model` / `[providers.*]`）：

```toml
[credentials]
ARK_API_KEY = "sk-..."        # 非模型 Key 也放这里（TAVILY_API_KEY 等）

[llm]
default_model = "arkcli-agent-plan/doubao-seed-2-0-lite-260215"   # provider/model

[providers.arkcli-agent-plan]
api_key = "ark-..."
base_url = "https://ark.cn-beijing.volces.com/api/plan/v3"
type = "openai"

[providers.deepseek]
api_key = "sk-..."
base_url = "https://api.deepseek.com/v1"
type = "openai"

[agent]
max_steps = 8
workdir = "/path/to/project"
```

并把「模型提供商（`/provider` / `/model`）」章节的 providers.json 描述改为 config.toml 的 `[providers.*]`（`/provider` 只读展示；增删改直接编辑 config.toml；`oauth` 字段保留但不实现；`type`：openai→chat、kimi→responses）。

- [ ] **Step 3: CHANGELOG**

`CHANGELOG.md` 的 `## [未发布]` 段加条目：

```markdown
- provider 配置收敛到 config.toml：新增 `[providers.<名字>]` 表（`api_key` /
  `base_url` / `type` / 可选 `oauth` 子表）与 `[llm] default_model =
"provider/model"`；`providers.json` 不再读写，`[llm] provider` / `model`
  两个字段被 `default_model` 替代，模型 Key 不再走 `[credentials]`/环境变量
  （`[credentials]` 表保留给搜索等非模型 Key）
- `/provider` 命令退化为只读展示；增删改直接编辑 config.toml
- **破坏性**：`ConatusTuiRuntime.create` 移除 `providers`（bool）/`providersFile`
  形参，新增 `List<ProviderConfig>? providers`；已有 `providers.json` 的用户
  需把 provider 定义迁移到 config.toml 的 `[providers.xxx]`
```

- [ ] **Step 4: 全量验证**

Run: `cd /Users/fitz/REPO/conatus/packages/conatus_code && dart analyze && dart test && cd /Users/fitz/REPO/conatus && dart analyze example`
Expected: 全部零 issue + 全绿

- [ ] **Step 5: 提交**

```bash
git add example/playground.dart README.md CHANGELOG.md
git commit -m "docs: 配置示例与变更记录更新到 [providers] 格式"
```

---

## Task 7: 重编 conatio + 端到端验证

**Files:**

- 无（产物 `dist/conatio` 不入库）

- [ ] **Step 1: 重编**

Run: `cd /Users/fitz/REPO/conatus/packages/conatus_code && bash tool/build_binary.sh && ./dist/conatio --help`
Expected: 产物重新生成，`--help` 输出 `用法：conatus_code [--session <id>] [--config <路径>]`

- [ ] **Step 2: 用新格式 config 试启动**

用以下临时 config（写到 `/tmp/conatio-test.toml`）：

```toml
[llm]
default_model = "arkcli-agent-plan/doubao-seed-2-0-lite-260215"

[providers.arkcli-agent-plan]
api_key = ""
base_url = "https://ark.cn-beijing.volces.com/api/plan/v3"
type = "openai"
```

Run: `cd /Users/fitz/REPO/conatus/packages/conatus_code && (./dist/conatio --config /tmp/conatio-test.toml > /tmp/conatio-t4.out 2>&1 & PID=$!; sleep 3; kill -9 $PID 2>/dev/null; wait $PID 2>/dev/null; head -c 300 /tmp/conatio-t4.out)`
Expected: TUI 正常渲染（ansi 片段），无「未知提供商」报错。

再验证三条错误路径（各 Run 一次同一命令，Expected: 进程退出非零 + 输出含对应文案）：

- `default_model` 的 provider 名改成 `nope` → `未知提供商：nope（config.toml [providers] 里没有）`
- 去掉整个 `[providers]` 段 → `未装配 LLM：请在 config.toml 配置 [providers.xxx] 与 [llm] default_model`
- `arkcli-agent-plan` 的 `api_key` 留空且追加 `[providers.arkcli-agent-plan.oauth]` + `key = "oauth/x"` → 输出含 `OAuth 未实现：请为 arkcli-agent-plan 配置 api_key`（该 provider 不可用但 TUI 照常启动）

- [ ] **Step 3: 提交 gitlink**

```bash
cd /Users/fitz/REPO/conatus && git add packages/conatus_code && git commit -m "chore(code): 同步子模块 gitlink"
```

---

## 验收清单

- [ ] `dart analyze`（conatus_code + example）零 issue；`dart test`（conatus_code）全绿
- [ ] `grep -rn "ProviderStore\|providers.json\|kDefaultProviders\|importRegistry" packages/conatus_code/lib packages/conatus_code/bin packages/conatus_code/example` 无残留（除 CHANGELOG/README 的历史描述）
- [ ] 纯 `[providers.*]` + `[llm] default_model` 的 config.toml 能启动 conatio；三条错误路径（无 providers、未知 provider、oauth 空 api_key）行为符合 spec
- [ ] `/provider` 只读展示、`/model` 切换模型名
- [ ] 根仓库与子模块均推送
