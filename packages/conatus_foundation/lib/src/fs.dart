/// filesystem 插件（能力缝 / Service Definition）：抽象的文件系统契约。
///
/// 服务键 `'fs'`，只定义接口，具体实现由 provider 提供（内置实现见
/// `fs_local.dart` 的 [LocalFileSystem] / `provideFileSystemLocal`）。
/// 后端负责稳定目标身份、文本读写的 UTF-8 校验与原子变更；读取窗口、
/// 观察策略等留在消费方与策略插件。
library;

import 'package:conatus_core/conatus_core.dart';
import 'fs_types.dart';

export 'fs_types.dart';

/// 抽象文件系统提供方。
///
/// 目标必须在别名下保持身份一致；读取暴露普通 UTF-8 文本或类型化错误；
/// 目录列举稳定且不读内容；写入与编辑必须原子。可选的守卫带来陈旧保护，
/// 但不改变无守卫时的契约。
abstract class FileSystem {
  /// 把模型/插件提供的路径解析为稳定的 [FsTarget]。
  ///
  /// 相同文件应产出相同 [FsTarget.targetKey]；相对路径以 [cwd] 为基准。
  Future<FsTarget> resolve(String path, {String? cwd});

  /// 返回本文件系统执行世界中子进程可打开的规范绝对路径。
  String processPath(FsTarget target);

  /// 返回目标在本执行世界的规范 `file:` URI。
  String fileUrl(FsTarget target);

  /// 判断 [child] 是否就是 [parent] 或其子孙（按规范身份，不解析不透明键）。
  bool contains(FsTarget parent, FsTarget child);

  /// 返回目标元数据；目标不存在时返回 null。绝不返回内容。
  Future<FsInfo?> stat(FsTarget target);

  /// 返回路径元数据，且不跟随最后一段符号链接。
  Future<FsPathInfo?> lstat(String path, {String? cwd});

  /// 读取整个普通文本文件为解码后的字符串。
  Future<String> readText(FsTarget target);

  /// 按名字稳定排序返回目录的直接子项；只含元数据，不读文件内容。
  Future<List<FsDirEntry>> listDir(FsTarget target);

  /// 原子地创建或替换 UTF-8 文本；[expected] 提供意图与陈旧守卫，省略即无条件。
  Future<FsWriteOutcome> writeText(
    FsTarget target,
    String content, {
    FsWriteIntent? expected,
  });

  /// 原子地做字面替换编辑；提供 [expectedVersion] 时先校验版本再匹配。
  Future<FsEditOutcome> editText(
    FsTarget target,
    FsEditRequest edit, {
    String? expectedVersion,
  });

  /// 删除目标文件（或目录）；目标不存在时静默返回。
  Future<void> remove(FsTarget target);
}

/// 将自定义 [fs] 作为 `'fs'` 服务提供到上下文。
void provideFileSystem(Context ctx, {required FileSystem fs}) {
  ctx.provide('fs', fs);
}
