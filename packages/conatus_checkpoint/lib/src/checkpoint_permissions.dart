/// 检查点落盘权限的**打开时迁移**（E-12）。
///
/// 权限收紧挂在 `snapshot()` 上，只覆盖「本进程之后新写的检查点」；升级前已
/// 存在的检查点（目录 0755 / 文件 0644）不会自己变紧——一次性或已结束的旧会话
/// 永不快照，其含工作区全文（可能夹带 `.env` / `id_rsa`）的内容会无限期保持
/// 同机可读。这里在打开 store 时对已有 `<projectDir>/checkpoints` 目录补收紧
/// 一次（目录 0700 挡住其他用户遍历进去，无需逐文件 chmod），与 E-13 对旧会话
/// 文件「下次追加补收紧」的语义对齐。
library;

import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

/// 若 `<projectDir>/checkpoints` 已存在，收紧其为 0700（幂等）。
Future<void> tightenExistingCheckpoints(String projectDir) async {
  final Directory dir = Directory(
    '$projectDir${Platform.pathSeparator}checkpoints',
  );
  if (!dir.existsSync()) return;
  await restrictDirectoryPermissions(dir.path);
}
