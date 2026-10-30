/// 敏感文件排除：凭据 / 私钥类文件名与后缀既不进快照、也不被恢复删除。
///
/// 全局 gitignore 的 git 侧用例见 `checkpoint_global_ignore_test.dart`。
library;

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

void main() {
  group('敏感文件排除', () {
    test('凭据 / 私钥类文件名与后缀被排除', () {
      for (final String p in <String>[
        '.env',
        'a/b/.env',
        '.env.local',
        '.env.production',
        'server.pem',
        'deep/nested/app.key',
        'id_rsa',
        'config/credentials.json',
        'secrets.yaml',
        '.netrc',
        'cert.p12',
      ]) {
        expect(
          checkpointExcluded(p, '', const CheckpointPolicy()),
          isTrue,
          reason: '$p 应被排除',
        );
      }
    });

    test('.env 的模板变体照常进快照', () {
      for (final String p in <String>[
        '.env.example',
        '.env.sample',
        '.env.template',
        '.env.defaults',
      ]) {
        expect(
          checkpointExcluded(p, '', const CheckpointPolicy()),
          isFalse,
          reason: '$p 不含真实凭据',
        );
      }
    });

    test('同名不同物的普通文件不受影响', () {
      for (final String p in <String>[
        'lib/env.dart',
        'lib/keys.dart',
        'pubspec.lock',
        'src/credential_manager.dart',
        '.envrc', // direnv 配置，非凭据
      ]) {
        expect(
          checkpointExcluded(p, '', const CheckpointPolicy()),
          isFalse,
          reason: '$p 不该被误伤',
        );
      }
    });
  });
}
