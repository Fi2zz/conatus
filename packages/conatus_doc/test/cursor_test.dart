import 'package:conatus_doc/conatus_doc.dart';
import 'package:test/test.dart';

DocPatch ai(String id, String blockId, String text) => DocPatch(
      id: id,
      author: PatchAuthor.ai,
      ops: <PatchOp>[InsertBlockOp(blockId: blockId, text: text)],
    );

void main() {
  group('游标', () {
    test('previewAt 只读：序列与生效集不变', () {
      final PatchLog log = PatchLog()
        ..append(ai('p1', 'b1', '一'))
        ..append(ai('p2', 'b2', '二'));
      final DocumentState early = previewAt(log, 1);
      expect(early.text, '一');
      expect(log.length, 2);
      expect(log.effective(), hasLength(2));
    });

    test('forkLog 从指定时刻开支线，旧线保留', () {
      final PatchLog log = PatchLog()
        ..append(ai('p1', 'b1', '一'))
        ..append(ai('p2', 'b2', '二'));
      final PatchLog branch = forkLog(log, 1)..append(ai('p3', 'b3', '支线'));
      expect(foldPatches(branch.effective()).text, contains('支线'));
      expect(log.length, 2);
    });

    test('truncateLog 作废后续补丁', () {
      final PatchLog log = PatchLog()
        ..append(ai('p1', 'b1', '一'))
        ..append(ai('p2', 'b2', '二'));
      truncateLog(log, 0);
      expect(foldPatches(log.effective()).text, '一');
    });
  });
}
