/// 经 TUI 选项浮层征询的审批实现：把 [Approval] 接到 [TuiChoicePrompt] 上。
///
/// 被拦截的工具弹出「允许一次 / 总是允许该工具 / 拒绝」；声明了路径参数
/// （`Tool.pathParams`）的工具另给「信任此文件夹」，选中后按「工具 + 目录」
/// 记住授权，之后该工具对落在该目录内的路径不再询问。计划审批（`requestPlan`）
/// 另给一组「批准 / 拒绝」选项。超时与取消都视为拒绝。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'tui_choice.dart';
import 'tui_permission.dart';

/// 等待用户决策的时长：交互类提问不受工具默认超时约束。
const Duration kTuiDecisionTimeout = Duration(minutes: 30);

/// 工具审批的选项 id。
const String kApprovalAllowOnce = 'allow-once';
const String kApprovalAllowAlways = 'allow-always';
const String kApprovalTrustFolder = 'trust-folder';
const String kApprovalDeny = 'deny';

/// 计划审批的选项 id。
const String kPlanApprove = 'plan-approve';
const String kPlanReject = 'plan-reject';

/// 选项浮层驱动的审批端口。
class TuiPermissionGate implements Approval {
  TuiPermissionGate({
    required this.choice,
    FileSystem? fs,
    this.mode = TuiPermissionMode.askWhenNeeded,
  }) : _fs = fs;

  /// 选项浮层。
  final TuiChoicePrompt choice;

  /// 文件系统能力缝；用于把「信任此文件夹」判定为目录包含关系。
  /// 未提供时该选项不出现（退化为「总是允许该工具」）。
  final FileSystem? _fs;

  final StreamController<ApprovalRequest> _pending =
      StreamController<ApprovalRequest>.broadcast();
  final Set<String> _alwaysAllowed = <String>{};
  final Set<_TrustedFolder> _trustedFolders = <_TrustedFolder>{};

  /// 当前权限模式；已记住的信任清单在切换时保持不变。
  TuiPermissionMode mode;

  /// 本会话内已被「总是允许」的工具名。
  Set<String> get alwaysAllowed => Set<String>.unmodifiable(_alwaysAllowed);

  /// 本会话内已授权的「工具 + 目录」。
  List<String> get trustedFolders => <String>[
        for (final _TrustedFolder trust in _trustedFolders)
          '${trust.toolName} → ${trust.folder}',
      ];

  /// 清空所有信任记录（切会话时调用：信任是会话级状态）。
  void resetAlwaysAllowed() {
    _alwaysAllowed.clear();
    _trustedFolders.clear();
  }

  @override
  Stream<ApprovalRequest> get pending => _pending.stream;

  /// 已授权「工具 + 目录」覆盖请求路径时放行，不再打扰用户。
  @override
  Future<bool> preapproved(ApprovalRequest request) async {
    if (mode == TuiPermissionMode.neverAsk) return true;
    if (_trustedFolders.isEmpty || request.pathArgs.isEmpty) return false;
    for (final String path in request.pathArgs) {
      if (!await _coveredByTrust(request.toolName, path)) return false;
    }
    return true;
  }

  @override
  Future<bool> request(ApprovalRequest request) async {
    if (!_pending.isClosed) _pending.add(request);
    if (mode == TuiPermissionMode.neverAsk) return true;
    if (_alwaysAllowed.contains(request.toolName)) return true;
    final String? picked = await choice.ask(
      TuiChoiceRequest(
        title: '是否允许执行 "${request.toolName}"？',
        choices: _toolChoices(request),
      ),
      timeout: kTuiDecisionTimeout,
    );
    if (picked == kApprovalTrustFolder) {
      await _rememberTrust(request.toolName, request.pathArgs);
      return true;
    }
    if (picked == kApprovalAllowAlways) {
      _alwaysAllowed.add(request.toolName);
      return true;
    }
    return picked == kApprovalAllowOnce;
  }

  @override
  Future<bool> requestPlan(Plan plan) async {
    final String? picked = await choice.ask(
      TuiChoiceRequest(
        title: '计划待批准：${plan.summary()}',
        choices: const <TuiChoice>[
          TuiChoice(
            id: kPlanApprove,
            label: '批准计划',
            description: '退出 Plan Mode 并开始执行。',
          ),
          TuiChoice(
            id: kPlanReject,
            label: '拒绝计划',
            description: '保持 Plan Mode，模型会据反馈修订。',
          ),
        ],
      ),
      timeout: kTuiDecisionTimeout,
    );
    return picked == kPlanApprove;
  }

  @override
  Future<void> close() async {
    choice.cancel();
    if (!_pending.isClosed) await _pending.close();
  }

  /// 该工具是否已获授权访问 [path]（path 必须落在某个已信任目录内）。
  Future<bool> _coveredByTrust(String toolName, String path) async {
    final FileSystem? fs = _fs;
    if (fs == null) return false;
    for (final _TrustedFolder trust in _trustedFolders) {
      if (trust.toolName != toolName) continue;
      if (await _within(fs, trust.folder, path)) return true;
    }
    return false;
  }

  /// 路径 [path] 是否位于目录 [folder] 之内（含同名）。解析失败视为不在。
  Future<bool> _within(FileSystem fs, String folder, String path) async {
    try {
      final FsTarget parent = await fs.resolve(folder);
      final FsTarget child = await fs.resolve(path);
      return fs.contains(parent, child);
    } catch (_) {
      return false;
    }
  }

  /// 记录「工具 + 目录」信任：目录取本次路径的父目录。
  Future<void> _rememberTrust(String toolName, List<String> paths) async {
    final FileSystem? fs = _fs;
    if (fs == null || paths.isEmpty) return;
    for (final String path in paths) {
      final String folder = await _folderOf(fs, path);
      _trustedFolders.add(_TrustedFolder(toolName, folder));
    }
  }

  /// 取路径所在目录：已是目录则用它自己，否则用其父目录。
  Future<String> _folderOf(FileSystem fs, String path) async {
    try {
      final FsTarget target = await fs.resolve(path);
      final FsInfo? info = await fs.stat(target);
      if (info?.type == FsFileType.directory) return target.displayPath;
    } catch (_) {
      // 解析失败则退化为按父目录处理。
    }
    final String normalized = path.replaceAll('\\', '/');
    final int cut = normalized.lastIndexOf('/');
    if (cut <= 0) return normalized;
    return path.substring(0, cut);
  }

  List<TuiChoice> _toolChoices(ApprovalRequest request) {
    final String? folder = request.pathArgs.isEmpty || _fs == null
        ? null
        : _parentLabel(request.pathArgs.first);
    return <TuiChoice>[
      TuiChoice(
        id: kApprovalAllowOnce,
        label: '允许一次',
        description: request.description.isEmpty
            ? '本次调用后重新询问。'
            : request.description,
      ),
      if (folder != null)
        TuiChoice(
          id: kApprovalTrustFolder,
          label: '信任此文件夹',
          description: '本次会话内，$folder 下的访问不再询问。',
        ),
      const TuiChoice(
        id: kApprovalAllowAlways,
        label: '总是允许该工具',
        description: '本次会话内不再询问这个工具（不限路径）。',
      ),
      const TuiChoice(
        id: kApprovalDeny,
        label: '拒绝',
        description: '不执行，把拒绝结果回给模型。',
      ),
    ];
  }

  /// 仅用于展示的父目录文本（真实目录判定走 fs）。
  String _parentLabel(String path) {
    final String normalized = path.replaceAll('\\', '/');
    final int cut = normalized.lastIndexOf('/');
    return cut <= 0 ? normalized : path.substring(0, cut);
  }
}

/// 一条「工具 + 目录」信任记录。
class _TrustedFolder {
  const _TrustedFolder(this.toolName, this.folder);

  final String toolName;
  final String folder;

  @override
  bool operator ==(Object other) =>
      other is _TrustedFolder &&
      other.toolName == toolName &&
      other.folder == folder;

  @override
  int get hashCode => Object.hash(toolName, folder);
}
