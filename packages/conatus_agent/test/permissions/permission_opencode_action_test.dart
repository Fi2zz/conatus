import 'package:conatus_agent/conatus_agent.dart';
import 'package:test/test.dart';

void main() {
  test('权限动作采用 OpenCode 键名', () {
    expect(permissionActionFor('bash'), 'bash');
    expect(permissionActionFor('run_tests'), 'bash');
    expect(permissionActionFor('git_add'), 'bash');
    expect(permissionActionFor('task'), 'task');
    expect(permissionActionFor('list'), 'read');
    expect(permissionActionFor('todowrite'), 'todowrite');
    expect(permissionActionFor('write'), 'edit');
    expect(permissionActionFor('apply_patch'), 'edit');
  });
}
