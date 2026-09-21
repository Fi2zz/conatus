# conatus_fs_tools

[实验性] conatus 的文件系统工具包，对齐 DSH 官方 `dsh-tool-fs` 与搜索工具。

| 工具         | 对齐 DSH | 说明                     |
| ------------ | -------- | ------------------------ |
| `read_file`  | `read`   | 分页读取，带行号         |
| `write_file` | `write`  | 三种模式，版本守卫       |
| `edit_file`  | `edit`   | 字面替换，唯一匹配       |
| `rg`         | `grep`   | ripgrep 搜索，结构化输出 |
| `glob`       | `glob`   | 按模式发现文件           |

## 使用

```dart
provideFileSystemLocal(app);
provideTools(app);
provideFsTools(app); // read_file / write_file / edit_file / rg / glob
```

依赖 `conatus_foundation` 的 `fs` / `shell` 接缝：`fs` 必需；
`shell` 缺省或未发现 ripgrep 二进制时跳过 `rg`（`glob` 仍注册）。
搜索结果超上限时经 `ToolResultEviction` 落盘，模型按路径读回。
