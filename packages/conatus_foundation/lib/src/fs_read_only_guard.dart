/// 通用只读路径闸门：`FileSystem` 装饰器，写/删在受保护根下一律拒绝。
///
/// 受保护目录（用户自己的配置 / 安装目录）只允许读取，绝不创建 / 写入 /
/// 删除 / 改权限。闸门包在 `'fs'` 接缝上，write / edit / apply_patch / 写回
/// 等一切经 fs 的写操作自动继承；读操作全部透传。
///
/// 判定同时看两种拼写：`inner.processPath`（已解析符号链接的规范路径）与
/// `target.displayPath`（字面路径）。前者让别名 / 符号链接下的真实位置参与
/// 比较，后者挡住「受保护目录下的链接指向外部」——任一命中即拒绝，
/// fail-closed。受保护根本身也补规范拼写，且**根尚不存在时**沿最近的已存在
/// 祖先解析（见 [realPathViaAncestor]），否则受保护目录未创建时闸门会
/// fail-open。
library;

import 'dart:io';
import 'dart:typed_data';

import 'fs.dart';
import 'fs_read_only_paths.dart';

/// 把写/删限制在受保护根之外的 [FileSystem] 装饰器。
///
/// 只对本地式后端有意义：判定以绝对路径做段级前缀比较，非文件后端的
/// displayPath 不会命中受保护根，因此自然透传。
class ReadOnlyPathGuard implements FileSystem {
  /// 用被装饰的 [inner] 与受保护根 [protectedRoots] 构造。
  ///
  /// [deniedMessage] 是拒绝时 [FsError.message] 的文案，缺省为通用文案；
  /// 产品可注入自己的错误码 / 文案。
  ReadOnlyPathGuard({
    required this.inner,
    required List<String> protectedRoots,
    this.deniedMessage = 'READ_ONLY_PATH: 目标目录只读',
  }) : protectedRoots = <String>[
          for (final String root in protectedRoots)
            if (root.trim().isNotEmpty)
              normalizeReadOnlyPath(Directory(root).absolute.path),
        ];

  /// 实际执行 I/O 的后端。
  final FileSystem inner;

  /// 只读根（绝对路径，段级前缀匹配）。
  final List<String> protectedRoots;

  /// 拒绝文案。
  final String deniedMessage;

  @override
  Future<FsTarget> resolve(String path, {String? cwd}) =>
      inner.resolve(path, cwd: cwd);

  @override
  String processPath(FsTarget target) => inner.processPath(target);

  @override
  String fileUrl(FsTarget target) => inner.fileUrl(target);

  @override
  bool contains(FsTarget parent, FsTarget child) =>
      inner.contains(parent, child);

  @override
  Future<FsInfo?> stat(FsTarget target) => inner.stat(target);

  @override
  Future<FsPathInfo?> lstat(String path, {String? cwd}) =>
      inner.lstat(path, cwd: cwd);

  @override
  Future<String> readText(FsTarget target) => inner.readText(target);

  @override
  Future<Uint8List> readBytes(FsTarget target) => inner.readBytes(target);

  @override
  Future<List<FsDirEntry>> listDir(FsTarget target) => inner.listDir(target);

  @override
  Future<FsWriteOutcome> writeText(
    FsTarget target,
    String content, {
    FsWriteIntent? expected,
  }) {
    _denyIfProtected(target);
    return inner.writeText(target, content, expected: expected);
  }

  @override
  Future<FsEditOutcome> editText(
    FsTarget target,
    FsEditRequest edit, {
    String? expectedVersion,
  }) {
    _denyIfProtected(target);
    return inner.editText(target, edit, expectedVersion: expectedVersion);
  }

  @override
  Future<void> remove(FsTarget target) {
    _denyIfProtected(target);
    _denyIfContainsProtected(target);
    return inner.remove(target);
  }

  /// 命中任一受保护根的任何拼写即抛 [FsError]。
  void _denyIfProtected(FsTarget target) {
    for (final String path in _spellings(target)) {
      if (_hitsAnyRoot(path)) _throwDenied();
    }
  }

  /// 删除目标是否**包含**受保护根（删工作区 / 删 `$HOME` 会连带删受保护目录）。
  ///
  /// 只对 `remove` 生效：写入一个受保护根的祖先目录是合法操作，删除不是。
  void _denyIfContainsProtected(FsTarget target) {
    for (final String path in _spellings(target)) {
      final String ancestor = normalizeReadOnlyPath(path);
      for (final String root in protectedRoots) {
        for (final String form in _rootForms(root)) {
          if (underReadOnlyRoot(form, ancestor)) _throwDenied();
        }
      }
    }
  }

  /// 目标的所有拼写：字面 displayPath 与后端规范路径。
  List<String> _spellings(FsTarget target) => <String>[
        normalizeReadOnlyPath(target.displayPath),
        normalizeReadOnlyPath(inner.processPath(target)),
      ];

  bool _hitsAnyRoot(String path) {
    for (final String root in protectedRoots) {
      if (_matchesRoot(path, root)) return true;
    }
    return false;
  }

  bool _matchesRoot(String path, String root) {
    for (final String form in _rootForms(root)) {
      if (underReadOnlyRoot(path, form)) return true;
    }
    return false;
  }

  Never _throwDenied() =>
      throw FsError(FsErrorCode.permissionDenied, deniedMessage);
}

/// 受保护根的拼写：字面 + 规范（根不存在时沿最近已存在祖先解析）。
Iterable<String> _rootForms(String root) {
  final List<String> forms = <String>[root];
  final String? real = realPathViaAncestor(root);
  if (real != null) forms.add(normalizeReadOnlyPath(real));
  return forms;
}
