# conatus_credentials

conatus 的凭据能力缝：统一的 `Credentials` 契约 + 五种来源。

**读取是同步的**：`get` / `require` / `validate` 读内存快照，远端来源用
`refresh()`（文件来源是 `load()`）把值拉进快照，轮换通过 `changes` 推送。
这样 LLM Provider 之类需要在构造函数里同步解析 Key 的调用方不必改成异步形状。

| 来源 | 类型 | 用途 | 可写 |
| --- | --- | --- | --- |
| 环境变量 | `EnvCredentials` | 进程环境，默认来源（12-factor） | 否 |
| 内存 | `InMemoryCredentials` | 进程内临时凭据、测试替身 | 是 |
| 文件 | `FileCredentials` | 本地 JSON，支持定时刷新 | 否 |
| Vault | `VaultCredentials` | HashiCorp Vault KV v2 | 否 |
| AWS | `AwsSecretsCredentials` | Secrets Manager `GetSecretValue`（SigV4） | 否 |

不可写的来源调用 `update` 会抛 `CredentialsException('read-only')`；缺失抛
`CredentialsException('missing')`。

## 接线

```dart
import 'package:conatus_credentials/conatus_credentials.dart';

// 缺省提供 EnvCredentials（读 Platform.environment）。
final Credentials credentials = provideCredentials(app);

// 或者换成远端来源，装配后拉一次快照。
final VaultCredentials vault = provideCredentials(
  app,
  credentials: VaultCredentials(
    config: VaultConfig(
      address: Platform.environment['VAULT_ADDR']!,
      token: Platform.environment['VAULT_TOKEN']!,
      path: 'conatus/llm',
      refreshInterval: const Duration(minutes: 5),
    ),
  ),
);
await vault.refresh();

credentials.validate(<String>['ARK_API_KEY', 'DEEPSEEK_API_KEY']);
final String? key = credentials.get('ARK_API_KEY')?.value;
app.credentials; // 扩展方法：取当前上下文可见的服务
```

`provideCredentials` 把服务注册为 `'credentials'`，并随上下文释放自动
`close()`（取消变更订阅与定时器）；同一上下文重复提供同名服务抛 `StateError`。

文件来源支持两种形态，`expiresAt` 到点后 `get` 直接返回 `null`：

```json
{ "ARK_API_KEY": "sk-xxx" }
{ "ARK_API_KEY": { "value": "sk-xxx", "expiresAt": "2026-01-01T00:00:00Z" } }
```

## 环境变量

`EnvCredentials` 读 `Platform.environment`（构造时可注入映射）。本包不解析
任何变量名，约定由使用方决定：LLM 用 `ARK_API_KEY` / `DEEPSEEK_API_KEY`，
Vault 用 `VAULT_ADDR` + `VAULT_TOKEN`，AWS 用 `AWS_ACCESS_KEY_ID` /
`AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN`。

## 脱敏

凭据绝不以明文进入日志或事件：`Credential.masked` 给出前 4 位 + `...` + 后 4 位
（长度 ≤ 8 时整串星号），`Credential.toString()` 也只含脱敏值；结构化日志交给
`conatus_core` 的 `redactSecrets`。
