/// 可逆性验证的观测等价边界：oracle 的分辨率由「观察什么」决定。
///
/// 论文 §3.3.2 说恢复是 up to **observational equivalence** 的，而等价关系取决于
/// 观察口径。本仓的可逆性验证（`reversibility_world.dart` 的 `project`）只比较
/// 键名、存活资源数与字符串，**不比对象身份、不比监听器顺序**。因此逆若还原成
/// 一个「内容等价但不是同一个对象」的状态，oracle 会判为通过。
///
/// 这是**设计上的宽松点，不是 bug**——但如果你关心对象身份（比如某个单例），就
/// 必须把它加进投影。本文件把这个边界钉成文档：一旦有人把投影改得更细（开始比
/// 较身份），下面的测试会失败，迫使那个决定被显式做出。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:test/test.dart';

/// 一个内容等价但不是同一对象的列表。
List<int> _freshBox() => <int>[1, 2, 3];

void main() {
  group('观测等价的边界', () {
    test('逆还原成等价但不同的对象：oracle 判为通过，但身份已变', () {
      final Context root = Context.root();
      addTearDown(root.dispose);

      final List<int> original = _freshBox();
      final Disposer undo = root.provide('svc', original);

      // 可观测投影：只问这个键在不在、取到的值长什么样（字符串）。
      List<String> project() => <String>['svc: ${root.get<List<int>>('svc')}'];

      final List<String> before = project();
      undo();
      // 若某实现把逆改成「重新提供一个内容相同的对象」……
      root.provide('svc', _freshBox());
      final List<String> after = project();

      expect(after, before); // oracle 判为还原成功（观测等价）
      expect(identical(root.get('svc'), original), isFalse); // 但对象身份已经变了
    });

    test('逆还原成不同的值：oracle 抓住（本组探针非空转）', () {
      final Context root = Context.root();
      addTearDown(root.dispose);

      final Disposer undo = root.provide('svc', <int>[1, 2, 3]);
      List<String> project() => <String>['svc: ${root.get<List<int>>('svc')}'];

      final List<String> before = project();
      undo();
      root.provide('svc', <int>[9, 9, 9]); // 值真的不同
      final List<String> after = project();

      expect(after, isNot(before)); // oracle 抓住
    });
  });
}
