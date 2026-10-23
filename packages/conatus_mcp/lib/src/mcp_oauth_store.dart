/// OAuth 令牌的本地存储：`~/.nava/oauth/<server>.json`，0600、原子写。
///
/// 目录由调用方给出（运行时是 `NAVA_HOME/oauth`，测试注入临时目录）。文件名
/// 只保留 `[A-Za-z0-9._-]`，其余字符替换成 `_`——server 名来自配置，不能让
/// `../` 之类的名字把令牌写进目录外。**令牌内容不进日志，也不出现在错误里。**
library;

import 'dart:convert';
import 'dart:io';

import 'mcp_oauth_types.dart';

/// 单台 server 的令牌文件路径（`<dir>/<安全化 server>.json`）。
String oauthTokenFileName(String server) {
  final String safe = server.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (safe.isEmpty) return '_';
  if (safe == '.' || safe == '..') return '_';
  return safe;
}

/// 按 server 名读写 OAuth 令牌。
class McpOAuthStore {
  /// 直接构造；[dir] 不会被自动创建，直到第一次 [save]。
  McpOAuthStore(this.dir);

  /// 令牌目录。
  final String dir;

  /// 某台 server 的令牌文件路径。
  String pathOf(String server) =>
      '$dir${Platform.pathSeparator}${oauthTokenFileName(server)}.json';

  /// 读取令牌；文件不存在、损坏或字段非法时返回 `null`（按未授权处理）。
  ///
  /// 读到坏文件不抛错：启动期不能因为一份旧令牌卡住整台 MCP，交由重新授权
  /// 修复。
  Future<McpOAuthToken?> load(String server) async {
    final File file = File(pathOf(server));
    try {
      if (!await file.exists()) return null;
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return null;
      return McpOAuthToken.fromJson(decoded);
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// 原子写入令牌文件：同目录临时文件 → `chmod 600` → rename 覆盖。
  ///
  /// 中途失败不会留下半写文件；临时文件在 [dir] 内，rename 才是原子的。
  Future<void> save(String server, McpOAuthToken token) async {
    await Directory(dir).create(recursive: true);
    final File target = File(pathOf(server));
    final File temp = File(
      '${target.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temp.writeAsString(jsonEncode(token.toJson()), flush: true);
      await _restrict(temp);
      if (Platform.isWindows && await target.exists()) await target.delete();
      await temp.rename(target.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  /// 删除令牌；文件不存在视为成功。
  Future<void> remove(String server) async {
    final File file = File(pathOf(server));
    try {
      await file.delete();
    } on FileSystemException {
      // 不存在或已删：幂等。
    }
  }
}

/// 把文件权限收成 0600（POSIX）；Windows 无对应语义，跳过。
Future<void> _restrict(File file) async {
  if (Platform.isWindows) return;
  final ProcessResult result =
      await Process.run('chmod', <String>['600', file.path]);
  if (result.exitCode != 0) {
    throw FileSystemException('无法设置令牌文件权限 0600', file.path);
  }
}
