import 'package:conatus_context/conatus_context.dart';
import 'package:test/test.dart';

void main() {
  test('ID 稳定且为 16 位小写 hex', () {
    final String id = ccrIdOf('hello');
    expect(id, hasLength(16));
    expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(id), true);
    expect(ccrIdOf('hello'), id);
    expect(ccrIdOf('hello!'), isNot(id));
    expect(ccrIdOf('中文内容'), isNot(ccrIdOf('中文內容')));
  });

  test('标记可编码、解析、检测', () {
    final String marker = encodeCcrMarker('0123456789abcdef', 42, 'items');
    expect(marker, '<<ctx:0123456789abcdef 42_items_omitted>>');
    expect(containsCcrMarker('a $marker b'), true);
    final CcrMarker parsed = parseCcrMarker('a $marker b')!;
    expect(parsed.id, '0123456789abcdef');
    expect(parsed.omitted, 42);
    expect(parsed.unit, 'items');
    expect(parseCcrMarker('无标记'), isNull);
    expect(parseCcrMarker('<<ctx:xyz 1_items_omitted>>'), isNull);
  });
}
