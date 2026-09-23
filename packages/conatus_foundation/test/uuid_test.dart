/// UUID v4 生成。
library;

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  test('newUuidV4 输出 8-4-4-4-12 小写十六进制', () {
    expect(newUuidV4(), matches(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-'
        r'[0-9a-f]{4}-[0-9a-f]{12}$'));
  });

  test('newUuidV4 置 version 4 与 RFC 4122 variant 位', () {
    for (int i = 0; i < 20; i++) {
      final String id = newUuidV4();
      expect(id[14], '4'); // version 位（第三段首字符）
      expect('89ab'.contains(id[19]), isTrue); // variant 位（第四段首字符）
    }
  });

  test('newUuidV4 两次生成互不相同', () {
    expect(newUuidV4(), isNot(newUuidV4()));
  });
}
