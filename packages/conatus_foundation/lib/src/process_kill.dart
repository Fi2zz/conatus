/// 进程树终结：`Process.kill` 只作用于直接子进程，孤儿化的孙进程需要单独收。
///
/// 为什么需要：后台任务与前台命令都用 `bash -c "cmd"` 启动。形如
/// `bash -c "a & b"` 的命令里，`a` 是孙进程——杀掉 bash 不会连带杀掉它，
/// 它会孤儿化继续运行（后台 kill / 超时 / 进程退出清场都会漏）。这里用
/// POSIX 的 `pgrep -P` 递归收集后代，**先杀后代再杀根**。
///
/// best-effort：`pgrep` 不可用、目标已消失、无权限都静默跳过——它服务于
/// 「尽量别留孤儿」，不该反过来让调用方失败。
library;

import 'dart:io';

/// 终结 [pid] 及其全部后代进程（POSIX 用进程树递归，Windows 只杀根）。
Future<void> killProcessTree(int pid) async {
  if (Platform.isWindows) {
    Process.killPid(pid, ProcessSignal.sigkill);
    return;
  }
  for (final int child in childPids(pid)) {
    await killProcessTree(child);
  }
  Process.killPid(pid, ProcessSignal.sigkill);
}

/// [pid] 的直接子进程 pid 列表；`pgrep` 不可用或没有子进程时返回空。
List<int> childPids(int pid) {
  final ProcessResult result;
  try {
    result = Process.runSync('pgrep', <String>['-P', '$pid']);
  } on ProcessException {
    return const <int>[];
  }
  if (result.exitCode != 0) return const <int>[];
  final List<int> pids = <int>[];
  for (final String line in '${result.stdout}'.split('\n')) {
    final int? value = int.tryParse(line.trim());
    if (value != null) pids.add(value);
  }
  return pids;
}
