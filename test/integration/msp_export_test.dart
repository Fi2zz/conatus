import 'dart:io';

import 'package:conatus/conatus.dart';
import 'package:test/test.dart';

void main() {
  test('伞包导出 MSP 节点与 Context 装配', () {
    final Context context = Context.root();
    final MspNode node = MspNode(
      nodeId: 'umbrella-consumer',
      nodesDirectory: Directory.systemTemp,
    );

    expect(provideMsp(context, node), same(node));
    expect(context.msp, same(node));
    context.dispose();
  });
}
