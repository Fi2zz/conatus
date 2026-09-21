import 'dart:convert';
import 'dart:io';

import 'package:conatus_tui/src/tui_attachment.dart';
import 'package:conatus_tui/src/tui_clipboard_image.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tui-attachment-test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  File makeFile(String name, List<int> bytes) {
    final File file = File('${tempDir.path}/$name');
    file.writeAsBytesSync(bytes);
    return file;
  }

  group('extractPathAttachments', () {
    test('全部 token 都是存在的文件路径时识别为附件', () {
      final File png = makeFile('a.png', [1]);
      final File txt = makeFile('b.txt', [2]);

      final List<TuiAttachment> found = extractPathAttachments(
        '${png.path}\n${txt.path}',
        tempDir.path,
      );

      expect(found, hasLength(2));
      expect(found[0].path, png.path);
      expect(found[0].mimeType, 'image/png');
      expect(found[0].isImage, isTrue);
      expect(found[1].mimeType, 'text/plain');
    });

    test('file:// URL 与引号包裹的路径均可识别', () {
      final File png = makeFile('c.png', [1]);

      final List<TuiAttachment> found = extractPathAttachments(
        '"${png.path}"',
        tempDir.path,
      );
      expect(found.single.path, png.path);

      final List<TuiAttachment> viaUrl = extractPathAttachments(
        'file://${png.path}',
        tempDir.path,
      );
      expect(viaUrl.single.path, png.path);
    });

    test('相对路径以 cwd 为基准解析', () {
      final File png = makeFile('d.png', [1]);

      final List<TuiAttachment> found = extractPathAttachments(
        'd.png',
        tempDir.path,
      );
      expect(found.single.path, png.path);
    });

    test('普通文本 / 混合内容 / 不存在的路径返回空', () {
      expect(extractPathAttachments('你好 世界', tempDir.path), isEmpty);
      expect(
        extractPathAttachments(
          '${tempDir.path}/missing.png',
          tempDir.path,
        ),
        isEmpty,
      );
      final File png = makeFile('e.png', [1]);
      expect(
        extractPathAttachments('${png.path} 前面的文字', tempDir.path),
        isEmpty,
      );
    });
  });

  group('materializeAttachments', () {
    test('图片读为 LlmImage，文本内联为 <file> 块', () async {
      final File png = makeFile('f.png', [137, 80, 78, 71]);
      final File txt = makeFile('g.txt', utf8.encode('内容'));

      final AttachmentMaterialization payload = await materializeAttachments([
        TuiAttachment(path: png.path, mimeType: 'image/png'),
        TuiAttachment(path: txt.path, mimeType: 'text/plain'),
      ]);

      expect(payload.images.single.mimeType, 'image/png');
      expect(payload.inlineText, contains('<file path="${txt.path}">'));
      expect(payload.inlineText, contains('内容'));
    });

    test('超限抛 StateError', () async {
      final File png =
          makeFile('h.png', List<int>.filled(kAttachmentImageMaxBytes + 1, 0));

      expect(
        () => materializeAttachments(<TuiAttachment>[
          TuiAttachment(path: png.path, mimeType: 'image/png'),
        ]),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('pngBase64FromOsa', () {
    test('解析 osascript 十六进制输出', () {
      expect(
        pngBase64FromOsa('«data PNGf89504E»'),
        base64Encode(<int>[0x89, 0x50, 0x4E]),
      );
    });

    test('非匹配输出返回 null', () {
      expect(pngBase64FromOsa(''), isNull);
      expect(pngBase64FromOsa('«data PNGf»'), isNull);
    });
  });
}
