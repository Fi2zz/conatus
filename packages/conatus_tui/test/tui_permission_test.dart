/// 权限模式与审批门：三档阈值行为、总是允许、计划审批、取消视为拒绝、目录信任。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_tui/conatus_tui.dart';
import 'package:test/test.dart';

ApprovalRequest _tool(String name) =>
    ApprovalRequest(id: 'r1', toolName: name, description: '说明');

/// 带路径参数的审批请求。
ApprovalRequest _pathTool(String path, [String name = 'read_file']) =>
    ApprovalRequest(
      id: 'r2',
      toolName: name,
      description: '读取文件',
      arguments: <String, Object?>{'path': path},
      pathArgs: <String>[path],
    );

/// 提供本地 fs 的审批门夹具（临时目录用完即删）。
class _FsFixture {
  _FsFixture(this.root, this.choice, this.gate);

  final Directory root;
  final TuiChoicePrompt choice;
  final TuiPermissionGate gate;
}

_FsFixture _withFs() {
  final Directory root = Directory.systemTemp.createTempSync('trust');
  addTearDown(() => root.deleteSync(recursive: true));
  final Context ctx = Context.root();
  addTearDown(ctx.dispose);
  final FileSystem fs = provideFileSystemLocal(ctx);
  final TuiChoicePrompt choice = TuiChoicePrompt();
  return _FsFixture(root, choice, TuiPermissionGate(choice: choice, fs: fs));
}

void main() {
  test('三档阈值映射：Always Ask 拦 medium，Ask When Needed 拦 high，Never Ask 不拦', () {
    expect(TuiPermissionMode.alwaysAsk.threshold, ToolRisk.medium);
    expect(TuiPermissionMode.askWhenNeeded.threshold, ToolRisk.high);
    expect(TuiPermissionMode.neverAsk.threshold, isNull);
  });

  test('parsePermissionMode 识别枚举名，其余返回 null', () {
    expect(parsePermissionMode('alwaysAsk'), TuiPermissionMode.alwaysAsk);    expect(parsePermissionMode(' NEVERASK '), TuiPermissionMode.neverAsk);
    expect(parsePermissionMode('nope'), isNull);
  });

  test('Never Ask 直接放行，不弹浮层', () async {
    final TuiChoicePrompt choice = TuiChoicePrompt();
    final TuiPermissionGate gate = TuiPermissionGate(
      choice: choice,
      mode: TuiPermissionMode.neverAsk,
    );

    expect(await gate.request(_tool('cron_add')), isTrue);
    expect(choice.open, isFalse);
  });

  test('允许一次放行但不记住工具', () async {
    final TuiChoicePrompt choice = TuiChoicePrompt();
    final TuiPermissionGate gate = TuiPermissionGate(choice: choice);

    final Future<bool> pending = gate.request(_tool('cron_add'));
    expect(choice.open, isTrue);
    choice.confirm(); // 首项即「允许一次」

    expect(await pending, isTrue);
    expect(gate.alwaysAllowed, isEmpty);
  });

  test('总是允许记住工具，后续调用不再弹浮层', () async {
    final TuiChoicePrompt choice = TuiChoicePrompt();
    final TuiPermissionGate gate = TuiPermissionGate(choice: choice);

    final Future<bool> pending = gate.request(_tool('cron_add'));
    choice
      ..move(1)
      ..confirm();

    expect(await pending, isTrue);
    expect(gate.alwaysAllowed, contains('cron_add'));

    expect(await gate.request(_tool('cron_add')), isTrue);
    expect(choice.open, isFalse);
  });

  test('拒绝返回 false', () async {
    final TuiChoicePrompt choice = TuiChoicePrompt();
    final TuiPermissionGate gate = TuiPermissionGate(choice: choice);

    final Future<bool> pending = gate.request(_tool('cron_add'));
    choice
      ..move(2)
      ..confirm();

    expect(await pending, isFalse);
  });

  test('取消视为拒绝', () async {
    final TuiChoicePrompt choice = TuiChoicePrompt();
    final TuiPermissionGate gate = TuiPermissionGate(choice: choice);

    final Future<bool> pending = gate.request(_tool('cron_add'));
    choice.cancel();

    expect(await pending, isFalse);
  });

  test('计划审批：批准与拒绝走独立选项', () async {
    final TuiChoicePrompt choice = TuiChoicePrompt();
    final TuiPermissionGate gate = TuiPermissionGate(choice: choice);
    const Plan plan = Plan(goal: '目标');

    final Future<bool> approve = gate.requestPlan(plan);
    choice.confirm();
    expect(await approve, isTrue);

    final Future<bool> reject = gate.requestPlan(plan);
    choice
      ..move(1)
      ..confirm();
    expect(await reject, isFalse);
  });

  test('pending 流广播请求', () async {
    final TuiChoicePrompt choice = TuiChoicePrompt();
    final TuiPermissionGate gate = TuiPermissionGate(choice: choice);

    final Future<ApprovalRequest> seen = gate.pending.first;
    final Future<bool> pending = gate.request(_tool('cron_add'));
    choice.cancel();

    expect((await seen).toolName, 'cron_add');
    await pending;
  });

  test('resetAlwaysAllowed 清空白名单', () async {
    final TuiChoicePrompt choice = TuiChoicePrompt();
    final TuiPermissionGate gate = TuiPermissionGate(choice: choice);

    final Future<bool> pending = gate.request(_tool('cron_add'));
    choice
      ..move(1)
      ..confirm();
    await pending;
    expect(gate.alwaysAllowed, contains('cron_add'));

    gate.resetAlwaysAllowed();
    expect(gate.alwaysAllowed, isEmpty);

    // 白名单已清空：再调用仍会弹浮层。
    final Future<bool> again = gate.request(_tool('cron_add'));
    expect(choice.open, isTrue);
    choice.cancel();
    expect(await again, isFalse);
  });

  group('信任此文件夹', () {
    test('路径工具弹层多出「信任此文件夹」选项', () async {
      final _FsFixture fixture = _withFs();
      final Directory root = fixture.root;
      final TuiChoicePrompt choice = fixture.choice;
      final TuiPermissionGate gate = fixture.gate;
      final String file = '${root.path}${Platform.pathSeparator}a.txt';

      final Future<bool> pending = gate.request(_pathTool(file));
      final List<String> labels =
          choice.request!.choices.map((TuiChoice c) => c.label).toList();
      expect(labels, contains('信任此文件夹'));
      expect(labels, contains('允许一次'));

      choice.cancel();
      expect(await pending, isFalse);
    });

    test('无路径参数的工具不出现该选项', () async {
      final _FsFixture fixture = _withFs();
      final TuiChoicePrompt choice = fixture.choice;

      final Future<bool> pending = fixture.gate.request(_tool('cron_add'));
      final List<String> labels =
          choice.request!.choices.map((TuiChoice c) => c.label).toList();
      expect(labels, isNot(contains('信任此文件夹')));

      choice.cancel();
      await pending;
    });

    test('未装配 fs 时不出现该选项（退化为总是允许）', () async {
      final TuiChoicePrompt choice = TuiChoicePrompt();
      final TuiPermissionGate gate = TuiPermissionGate(choice: choice);

      final Future<bool> pending = gate.request(_pathTool('/tmp/a.txt'));
      final List<String> labels =
          choice.request!.choices.map((TuiChoice c) => c.label).toList();
      expect(labels, isNot(contains('信任此文件夹')));
      expect(labels, contains('总是允许该工具'));

      choice.cancel();
      await pending;
    });

    test('选「信任此文件夹」后，同目录内的路径免问、目录外仍要问', () async {
      final _FsFixture fixture = _withFs();
      final Directory root = fixture.root;
      final TuiChoicePrompt choice = fixture.choice;
      final TuiPermissionGate gate = fixture.gate;
      final String sep = Platform.pathSeparator;
      final String inside = '${root.path}${sep}a.txt';
      final String sibling = '${root.path}${sep}b.txt';

      // 选中「信任此文件夹」（第二项）。
      final Future<bool> first = gate.request(_pathTool(inside));
      choice
        ..move(1)
        ..confirm();
      expect(await first, isTrue);
      expect(gate.trustedFolders, hasLength(1));
      expect(gate.trustedFolders.single, contains(root.path));

      // 同目录内的另一个文件：preapproved 放行，不弹层。
      expect(await gate.preapproved(_pathTool(sibling)), isTrue);
      expect(choice.open, isFalse);

      // 目录外：仍要问。
      expect(await gate.preapproved(_pathTool('/etc/passwd')), isFalse);
    });

    test('信任按工具隔离：别的工具用同目录仍要问', () async {
      final _FsFixture fixture = _withFs();
      final Directory root = fixture.root;
      final TuiChoicePrompt choice = fixture.choice;
      final TuiPermissionGate gate = fixture.gate;
      final String file = '${root.path}${Platform.pathSeparator}a.txt';

      final Future<bool> pending = gate.request(_pathTool(file));
      choice
        ..move(1)
        ..confirm();
      await pending;

      expect(await gate.preapproved(_pathTool(file)), isTrue);
      expect(
        await gate.preapproved(_pathTool(file, 'write_file')),
        isFalse,
      );
    });

    test('信任目录取路径所在目录，而非文件本身', () async {
      final _FsFixture fixture = _withFs();
      final Directory root = fixture.root;
      final TuiChoicePrompt choice = fixture.choice;
      final TuiPermissionGate gate = fixture.gate;
      final String sep = Platform.pathSeparator;
      final String sub = '${root.path}${sep}sub';
      Directory(sub).createSync(recursive: true);
      final String nested = '$sub${sep}deep.txt';

      final Future<bool> pending = gate.request(_pathTool(nested));
      choice
        ..move(1)
        ..confirm();
      await pending;

      // 目录本身是已存在的目录：信任它，其子孙都覆盖。
      expect(gate.trustedFolders.single, contains(sub));
      expect(await gate.preapproved(_pathTool('$sub${sep}other.txt')), isTrue);
      expect(
        await gate.preapproved(_pathTool('${root.path}${sep}outside.txt')),
        isFalse,
      );
    });

    test('Never Ask 下 preapproved 直接放行', () async {
      final _FsFixture fixture = _withFs();
      fixture.gate.mode = TuiPermissionMode.neverAsk;
      expect(await fixture.gate.preapproved(_pathTool('/etc/passwd')), isTrue);
    });

    test('resetAlwaysAllowed 同时清空目录信任', () async {
      final _FsFixture fixture = _withFs();
      final Directory root = fixture.root;
      final TuiChoicePrompt choice = fixture.choice;
      final TuiPermissionGate gate = fixture.gate;
      final String file = '${root.path}${Platform.pathSeparator}a.txt';

      final Future<bool> pending = gate.request(_pathTool(file));
      choice
        ..move(1)
        ..confirm();
      await pending;
      expect(gate.trustedFolders, isNotEmpty);

      gate.resetAlwaysAllowed();
      expect(gate.trustedFolders, isEmpty);
      expect(await gate.preapproved(_pathTool(file)), isFalse);
    });
  });

  group('restorePermissionMode', () {    test('无记录时为默认档', () {
      final Session session = Session(id: 's');
      expect(restorePermissionMode(session), TuiPermissionMode.askWhenNeeded);
    });

    test('折叠最后一条 permission/mode 事件', () {
      final Session session = Session(id: 's');
      expect(restorePermissionMode(session), TuiPermissionMode.askWhenNeeded);

      session.append(kPermissionModeEvent,
          data: <String, Object?>{'mode': 'alwaysAsk'});
      expect(restorePermissionMode(session), TuiPermissionMode.alwaysAsk);

      session.append(kPermissionModeEvent,
          data: <String, Object?>{'mode': 'neverAsk'});
      expect(restorePermissionMode(session), TuiPermissionMode.neverAsk);
    });

    test('事件数据非法时回落到默认档', () {
      final Session session = Session(id: 's');
      session.append(kPermissionModeEvent,
          data: <String, Object?>{'mode': 'nope'});
      expect(restorePermissionMode(session), TuiPermissionMode.askWhenNeeded);

      session.append(kPermissionModeEvent);
      expect(restorePermissionMode(session), TuiPermissionMode.askWhenNeeded);
    });
  });
}
