import 'package:conatus_msp/src/msp_manifest.dart';
import 'package:test/test.dart';

void main() {
  test('Manifest 使用数组和 camelCase 线上结构', () {
    final MspManifest manifest = MspManifest();
    manifest.addTool(const MspToolDescriptor(
      name: 'get_weather',
      description: '查询天气',
      inputSchema: <String, Object?>{'type': 'object'},
    ));
    manifest.addSignal(const MspSignalDescriptor(
      path: 'notify.weather.changed',
    ));

    final Map<String, Object?> json = manifest.toJson();
    expect(manifest.version, 2);
    expect(json['patterns'], isA<List<Object?>>());
    expect(json['signals'], isA<List<Object?>>());
    expect(json['tools'], isA<List<Object?>>());
    expect(json['resources'], isEmpty);
    expect(json['clientCapabilities'], <String, Object?>{
      'sampling': false,
      'elicitation': false,
      'roots': false,
    });
  });

  test('Manifest 可从参考实现字段形态还原', () {
    final MspManifest manifest = MspManifest.fromJson(<String, Object?>{
      'version': 3,
      'patterns': <String>['msp/request-reply'],
      'patternMetadata': <String, Object?>{},
      'capabilities': <String>['rep', 'pub'],
      'signals': <Object?>[
        <String, Object?>{'path': 'notify.web.download'},
      ],
      'tools': <Object?>[],
      'resources': <Object?>[],
      'prompts': <Object?>[],
      'clientCapabilities': <String, Object?>{
        'sampling': false,
        'elicitation': false,
        'roots': false,
      },
    });

    expect(manifest.version, 3);
    expect(manifest.toJson()['capabilities'], <String>['pub', 'rep']);
    expect(manifest.signals.single.path, 'notify.web.download');
  });
}
