# 方案：Git 源分发——保留 workspace 与子包，子包全部不发布，根包统一导出

> 日期：2026-09-26 · 状态：已批准，待执行
>
> 背景：解决「发布与版本管理繁琐」（15 个包逐个发布、version.sh 同步 23 个
> pubspec、漏改一处 `dart pub get` 即失败），同时保留 workspace 多包开发体验。

## 方案形状

不移动任何代码。保留 pub workspace 与全部 22 个 `conatus_*` 子包；所有子包与根包
都声明 `publish_to: none`；根包 `conatus` 用 **path 依赖** 全部 22 个子包并统一导出。
用户通过 **git 源**依赖根包，安装时一次性获得全部子包：

```yaml
# 用户的 pubspec.yaml
dependencies:
  conatus:
    git: {url: https://github.com/Fi2zz/conatus.git, ref: master}   # 或 pin 到 tag
```

## 已完成的可行性验证（/tmp 三组对照实验，全部通过）

| 验证点 | 结果 |
|---|---|
| git 依赖根包时，其内部 path 依赖子包随包一次性解析安装 | ✅ `acme_sub 0.16.0 from git ... in packages/acme_sub` |
| workspace 根 path 依赖成员，本地 `dart pub get` | ✅ 通过（成员 `resolution: workspace` 已就位） |
| 含 path 依赖的根包 `dart pub publish --dry-run` | ✅ 被 pub 拒绝（4 errors：必须使用 hosted source）→ 根包必须 `publish_to: none` |
| 消费者只依赖根包、直接 `import` 各子包名（conatus_code 场景） | ✅ 可行（仅 unnecessary_import info） |

结论：**技术路径完全可行，改动集中在配置与文档，零代码移动。**

## 具体改动清单

1. **14 个稳定包 pubspec**（core / foundation / credentials / llm / search / skill /
   asr / tts / mcp / schedule / cron / compaction / agent / tasks）：各加一行
   `publish_to: none`；`version: 0.16.0` 冻结不再变动。8 个实验性包已有该字段，不动。
2. **根 `pubspec.yaml`**：
   - 加 `publish_to: none`。
   - `dependencies`：现有 14 个 `^0.16.0` 版本约束 → 全部改为 path 依赖
     （如 `conatus_agent: {path: packages/conatus_agent}`）；8 个实验性包从
     `dev_dependencies` 移入 `dependencies` 并同样 path 依赖（共 22 个）。
   - `dev_dependencies`：移除已上移的 8 个实验性包；保留 `test` / `lints` /
     `conatus_code`（git 源）。
   - 保留 `workspace: [packages/*]`。
3. **`lib/conatus.dart`**：追加 8 行实验性包 export（alerting / browser_use /
   computer_use / intent / observability / team / workflow / ontology），文件头注释
   更新为「单入口导出全部模块」。
4. **`packages/conatus_code` 子模块**：`pubspec.yaml` 的 13 个 git path 依赖 →
   单个 `conatus: {git: ...}`（其 import `package:conatus_xxx` 无需改动，实验验证
   子包名仍解析）；`tool/setup_code_filter.sh` 评估简化；通过后
   `bash tool/build_binary.sh` 重建 `nava`。
5. **`tool/version.sh` 退役**：升版概念由 git tag 承载；删除或改为「子包版本冻结」
   校验脚本（防误改）。同步更新 AGENTS.md。
6. **文档**：
   - 根 `README.md`：安装指引改为 git 源写法；标注「pub.dev 上 0.16.0 为最后
     hosted 版本，此后通过 git 源分发」；包表格说明不变（结构未动）。
   - `AGENTS.md`：第 7 节版本管理（version.sh 退役）、第 8 节发布流程（无发布
     动作，改为 tag 流程）、第 10 节已知边界（version.sh 子模块缺口一并消失）重写。
   - `CHANGELOG.md`：记录分发方式变更。
7. **CI**（`.github/workflows/integration-test.yml`）：现有测试矩阵无需改；新增一个
   「消费链验证」job——检出仓库后建临时消费者包以本地 git 源依赖根包，跑
   `dart analyze`，防 path 依赖/导出链回归。

## 验证清单（全部通过才算完成）

- [ ] 根 `dart pub get`（workspace 解析）+ `dart analyze --fatal-infos`
- [ ] 根 `dart test` + `for d in packages/*/; do (cd "$d" && dart test); done` +
      `dart test test/integration/ --reporter=expanded`
- [ ] `bash tool/verify_reversibility.sh`
- [ ] 消费链全链路：/tmp 临时消费者以本地路径 git 依赖本仓库 → `pub get` /
      `analyze` / `dart run` 调用各子包符号
- [ ] `conatus_code`：`dart test` + `build_binary.sh` + `nava` smoke
- [ ] 文档安装指引按新写法实际操作一遍

## 代价（如实列出）

- **pub.dev 停止更新**：`dart pub add conatus` 失效，用户须手写 git 依赖
  （README 给模板）。
- 失去 pub.dev 的文档托管与搜索发现性。
- 未来若有下游库要发布到 pub.dev 并依赖 conatus——pub 同样拒绝 git 依赖，该下游
  只能改用 git 或 vendoring；当前无已知下游，风险低。
- 子包全部 `publish_to: none` 后，误执行 `dart pub publish` 会被 pub 直接拒绝
  （负向保护）。

## 遗留决策点（执行前确认）

1. **是否发 pub.dev 告别版**：建议把当前 master 以 0.16.1 发最后一版 hosted，
   README 标注「此后请改用 git 源」，给已有 hosted 用户一个指路标。（可选）
2. **git tag 策略**：从本次变更起打 `v0.17.0` tag，用户可 `ref: v0.17.0` pin
   版本；后续演进以 tag 为版本锚点，CHANGELOG 照旧维护。

## 不做的事

- 不移动/合并任何代码与测试文件，不改任何公开 API 签名。
- 不动 8 个实验性包的代码内容与既有 `publish_to: none`。
- 不改动 workspace 成员关系与子模块 filter 的核心机制（仅评估简化）。
