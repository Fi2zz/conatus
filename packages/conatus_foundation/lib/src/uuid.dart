/// 随机 UUID v4 生成（无第三方依赖）。
library;

import 'dart:math';

/// 生成一个随机 UUID v4：小写十六进制、`8-4-4-4-12` 分段。
///
/// 用于会话 id 等需要全局唯一标识、且不希望引入依赖的场景。
String newUuidV4() {
  final Random random = Random.secure();
  final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
  final StringBuffer buffer = StringBuffer();
  for (int index = 0; index < 16; index++) {
    if (index == 4 || index == 6 || index == 8 || index == 10) {
      buffer.write('-');
    }
    buffer.write(bytes[index].toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
