/// C1：权限路径按 workdir / 真实路径匹配，绝对与相对拼写不能互相绕过。
library;

import 'dart:io';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

class _Rig {
  _Rig(this.ctx, this.evaluator);

  final Context ctx;
  final PermissionEvaluator evaluator;

  PermissionVerdict verdict(Call call, List<PermissionRule> rules) {
    final Tool tool = ctx.tools.get(call.name)!;
    return evaluator
        .evaluate(
          tool,
          ToolCall(name: call.name, arguments: call.args),
          PermissionScope(rules: rules),
        )
        .verdict;
  }
}

typedef Call = ({String name, Map<String, Object?> args});

_Rig _rig(String workdir) {
  final Context ctx = Context.root();
  addTearDown(ctx.dispose);
  provideTools(ctx);
  for (final String name in <String>['read', 'write']) {
    ctx.tools.fn(
      name,
      pathParams: const <String>['path'],
      handler: (ToolContext c) async => ToolResult.success('ok'),
    );
  }
  return _Rig(
    ctx,
    PermissionEvaluator(interactive: true, workdir: workdir),
  );
}

Directory _workspace() {
  final Directory dir = Directory.systemTemp.createTempSync('perm-path');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

void main() {
  test('相对规则 edit "src/*" 拦住绝对路径调用', () {
    final Directory dir = _workspace();
    final _Rig rig = _rig(dir.path);
    final String target = '${dir.path}${Platform.pathSeparator}src/x.dart';

    final PermissionVerdict verdict = rig.verdict(
      (name: 'write', args: <String, Object?>{'path': target}),
      const <PermissionRule>[
        PermissionRule(
          action: 'edit',
          resource: 'src/*',
          effect: PermissionEffect.deny,
        ),
      ],
    );

    expect(verdict.effect, PermissionEffect.deny);
  });

  test('绝对规则 read "<workdir>/secret/*" 拦住相对路径调用', () {
    final Directory dir = _workspace();
    final _Rig rig = _rig(dir.path);
    final String rule = '${dir.path}${Platform.pathSeparator}secret/*';

    final PermissionVerdict verdict = rig.verdict(
      (name: 'read', args: <String, Object?>{'path': 'secret/x'}),
      <PermissionRule>[
        PermissionRule(
          action: 'read',
          resource: rule,
          effect: PermissionEffect.deny,
        ),
      ],
    );

    expect(verdict.effect, PermissionEffect.deny);
  });

  test('工作区符号链接指向外部：deny 按真实路径命中', () {
    if (Platform.isWindows) return;
    final Directory dir = _workspace();
    final Directory outside = _workspace();
    final String secret = '${outside.path}${Platform.pathSeparator}hosts';
    File(secret).writeAsStringSync('127.0.0.1\n');
    Link('${dir.path}${Platform.pathSeparator}notes.txt').createSync(secret);
    final _Rig rig = _rig(dir.path);

    final PermissionVerdict verdict = rig.verdict(
      (name: 'read', args: <String, Object?>{'path': 'notes.txt'}),
      <PermissionRule>[
        PermissionRule(
          action: 'read',
          resource: '${outside.path}/*',
          effect: PermissionEffect.deny,
        ),
      ],
    );

    expect(verdict.effect, PermissionEffect.deny);
  });

  test('工作区符号链接指向外部：external_directory 规则生效', () {
    if (Platform.isWindows) return;
    final Directory dir = _workspace();
    final Directory outside = _workspace();
    final String secret = '${outside.path}${Platform.pathSeparator}hosts';
    File(secret).writeAsStringSync('127.0.0.1\n');
    Link('${dir.path}${Platform.pathSeparator}notes.txt').createSync(secret);
    final _Rig rig = _rig(dir.path);

    final PermissionVerdict verdict = rig.verdict(
      (name: 'read', args: <String, Object?>{'path': 'notes.txt'}),
      const <PermissionRule>[
        PermissionRule(
          action: 'external_directory',
          resource: '*',
          effect: PermissionEffect.deny,
        ),
      ],
    );

    expect(verdict.effect, PermissionEffect.deny);
  });

  test('external_directory 规则资源展开 ~ 与相对 workdir', () {
    final Directory dir = _workspace();
    final String home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE']!;

    expect(
      permissionPatternSpellings('~/shared/*', dir.path),
      contains('$home/shared/*'),
    );
    expect(
      permissionPatternSpellings('shared/*', dir.path),
      contains('${dir.path}/shared/*'),
    );
  });
}
