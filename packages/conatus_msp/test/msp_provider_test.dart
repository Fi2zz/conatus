import 'dart:async';
import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_msp/conatus_msp.dart';
import 'package:test/test.dart';

void main() {
  test('Context 释放会停止节点并撤销目录声明', () async {
    final Directory directory =
        Directory.systemTemp.createTempSync('conatus-msp-context-');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final Context context = Context.root();
    final MspNode node = MspNode(nodeId: 'provider', nodesDirectory: directory);
    final MspNode provided = provideMsp(context, node);
    expect(provided, same(node));
    expect(context.msp, same(node));
    await node.start();
    final File declaration = File('${directory.path}/provider.json');
    expect(declaration.existsSync(), isTrue);

    context.dispose();
    await _waitFor(() => !node.running && !declaration.existsSync());
    expect(node.running, isFalse);
    expect(declaration.existsSync(), isFalse);
  });
}

Future<void> _waitFor(bool Function() condition) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('等待 Context 清理超时');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
