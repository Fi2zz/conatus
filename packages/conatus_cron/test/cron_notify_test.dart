import 'package:conatus_cron/conatus_cron.dart';
import 'package:test/test.dart';

void main() {
  test('纯 Dart 环境 mobileCronNotifier 返回 null（由宿主注入）', () {
    expect(mobileCronNotifier(), isNull);
    expect(mobileCronNotifier(channel: 'custom/channel'), isNull);
  });
}
