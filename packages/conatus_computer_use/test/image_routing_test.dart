import 'package:conatus_computer_use/conatus_computer_use.dart';
import 'package:test/test.dart';

void main() {
  group('imageSupportFor', () {
    test('视觉模型接收持久化截图', () {
      expect(
        imageSupportFor('doubao', 'doubao-seed-1-8-251228'),
        ImageSupport.persistent,
      );
      expect(
        imageSupportFor('doubao', 'doubao-vision-pro'),
        ImageSupport.persistent,
      );
    });

    test('其余模型接收诊断', () {
      expect(imageSupportFor('doubao', 'doubao-pro-32k'), ImageSupport.diagnostic);
      expect(imageSupportFor('deepseek', 'deepseek-chat'), ImageSupport.diagnostic);
      expect(imageSupportFor('unknown', 'unknown-model'), ImageSupport.diagnostic);
    });
  });
}
