# conatus_coding

[实验性] conatus 的 coding 场景包。

| 层次     | 能力                                     | 来源                 |
| -------- | ---------------------------------------- | -------------------- |
| 读写层   | `read_file` / `write_file` / `edit_file` | `conatus_fs_tools`   |
| 搜索层   | `rg` / `glob`                            | `conatus_fs_tools`   |
| 执行层   | `CodeRuntime` 接缝 + 子进程后端          | 本包                 |

## 使用

```dart
provideFileSystemLocal(app);
provideTools(app);
provideFsTools(app);            // 读写 + 搜索（本包入口已含）
provideCoding(app, codeRuntime: SubprocessCodeRuntime(
  shell: shell,
  executable: 'dart',
  extension: '.dart',
), enableRuntime: true);

// 执行一段代码：失败是结果字段，不是异常。
final CodeRunResult result = await runtime.run(
  CodeRunRequest(program: 'void main() { print("hi"); }'),
);
```

依赖 `conatus_foundation` 的 `fs` / `shell` / `tools` 接缝：`fs` 与 `tools`
必需；`shell` 缺省或未发现 ripgrep 二进制时跳过 `rg`（`glob` 仍注册）。

`isolation` 只是部署与诊断的描述符，不构成任何安全承诺。
