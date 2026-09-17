import 'dart:convert';
import 'package:conatus_computer_use/conatus_computer_use.dart';
import 'package:test/test.dart';

void main() {
  group('Screenshot', () {
    test('缺省 mimeType 为 image/png，非空判定正确', () {
      final Screenshot shot = Screenshot(
        bytes: const <int>[1, 2, 3],
        width: 4,
        height: 5,
        capturedAt: DateTime(2026),
      );
      expect(shot.mimeType, 'image/png');
      expect(shot.isEmpty, isFalse);
      expect(shot.attachmentRef, isNull);

      final Screenshot empty = Screenshot(
        bytes: const <int>[],
        width: 0,
        height: 0,
        capturedAt: DateTime(2026),
      );
      expect(empty.isEmpty, isTrue);
    });

    test('copyWith 回填 attachmentRef', () {
      final Screenshot shot = Screenshot(
        bytes: const <int>[1],
        width: 1,
        height: 1,
        capturedAt: DateTime(2026),
      );
      final Screenshot persisted = shot.copyWith(attachmentRef: 'ref-1');
      expect(persisted.attachmentRef, 'ref-1');
      expect(identical(persisted.bytes, shot.bytes), isTrue);
      expect(shot.attachmentRef, isNull);
    });
  });

  group('ScreenRegion', () {
    test('JSON 往返', () {
      const ScreenRegion region =
          ScreenRegion(x: 1, y: 2, width: 320, height: 240);
      final Map<String, Object?> json = region.toJson();
      expect(ScreenRegion.fromJson(json), isA<ScreenRegion>());
      expect(json, <String, Object?>{'x': 1, 'y': 2, 'width': 320, 'height': 240});
    });

    test('fromJson 字段缺失退回 0', () {
      final ScreenRegion region = ScreenRegion.fromJson(const <String, Object?>{});
      expect(region.x, 0);
      expect(region.height, 0);
    });
  });

  group('InMemoryAttachmentStore', () {
    test('save / load / delete 往返', () async {
      final InMemoryAttachmentStore store = InMemoryAttachmentStore();
      final String ref = await store.save(<int>[9, 8, 7], mimeType: 'image/png');

      expect(store.refs, contains(ref));
      expect(await store.load(ref), <int>[9, 8, 7]);

      await store.delete(ref);
      expect(await store.load(ref), isNull);
    });

    test('保存空字节也返回引用', () async {
      final InMemoryAttachmentStore store = InMemoryAttachmentStore();
      final String ref = await store.save(const <int>[], mimeType: 'image/png');
      expect(await store.load(ref), isEmpty);
    });
  });

  group('base64 编解码', () {
    test('往返一致', () {
      final String encoded = encodeBase64Bytes(<int>[1, 2, 3]);
      expect(decodeBase64Bytes(encoded), <int>[1, 2, 3]);
      expect(base64Encode(<int>[1, 2, 3]), encoded);
    });
  });
}
