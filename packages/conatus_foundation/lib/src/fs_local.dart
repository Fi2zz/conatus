/// filesystem 插件的本地实现：基于 `dart:io` 读写宿主磁盘。
///
/// 目标身份由 realpath 派生（别名共享同一键），写入经临时文件 + rename 原子
/// 发布，编辑在守卫校验后做字面替换。相对路径以构造时的 [cwd] 为基准。
/// 具体机制拆到 part 文件（路径与探测、读写操作），本文件只保留薄接口门面。
library;

import 'dart:convert';
import 'dart:io';
import 'package:conatus_core/conatus_core.dart';
import 'fs.dart';

part 'fs_local_ops.dart';
part 'fs_local_paths.dart';

/// 宿主文件系统后端。
class LocalFileSystem implements FileSystem {
  LocalFileSystem({String? cwd}) : cwd = cwd ?? Directory.current.path;

  /// 相对路径的解析基准。
  final String cwd;

  @override
  Future<FsTarget> resolve(String path, {String? cwd}) =>
      _resolveLocal(this.cwd, path, cwd);

  @override
  String processPath(FsTarget target) => target.targetKey;

  @override
  String fileUrl(FsTarget target) => Uri.file(processPath(target)).toString();

  @override
  bool contains(FsTarget parent, FsTarget child) =>
      _pathContains(processPath(parent), processPath(child));

  @override
  Future<FsInfo?> stat(FsTarget target) => _statTarget(target);

  @override
  Future<FsPathInfo?> lstat(String path, {String? cwd}) =>
      _lstatPath(this.cwd, path, cwd);

  @override
  Future<String> readText(FsTarget target) => _readTargetText(target);

  @override
  Future<List<FsDirEntry>> listDir(FsTarget target) => _listTargetDir(target);

  @override
  Future<FsWriteOutcome> writeText(
    FsTarget target,
    String content, {
    FsWriteIntent? expected,
  }) =>
      _writeTargetText(target, content, expected);

  @override
  Future<FsEditOutcome> editText(
    FsTarget target,
    FsEditRequest edit, {
    String? expectedVersion,
  }) =>
      _editTargetText(target, edit, expectedVersion);

  @override
  Future<void> remove(FsTarget target) => _removeTarget(target);
}

/// 提供本地文件系统为 `'fs'` 服务；[fs] 用于注入自定义实现。
FileSystem provideFileSystemLocal(Context ctx, {FileSystem? fs}) {
  final FileSystem resolved = fs ?? LocalFileSystem();
  ctx.provide('fs', resolved);
  return resolved;
}
