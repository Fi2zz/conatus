import 'dart:convert';
import 'dart:typed_data';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_tts/conatus_tts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

class _FakeSession implements TtsSession {
  _FakeSession(this.sink, this.name);

  final TtsAudioSink sink;
  final String name;
  final StringBuffer text = StringBuffer();
  bool finished = false;
  bool closed = false;

  @override
  void send(String chunk) => text.write(chunk);

  @override
  Future<void> finish() async {
    finished = true;
    sink.write(utf8.encode('audio:$name:${text.toString()}'));
    await sink.close();
  }

  @override
  void close() => closed = true;
}

class _FakeProvider implements TtsProvider {
  _FakeProvider(this.name, {this.fails = false});

  @override
  final String name;
  final bool fails;
  _FakeSession? last;
  TtsVoice? lastVoice;

  @override
  TtsAudioFormat get audioFormat => const TtsAudioFormat();

  @override
  TtsVoice? get defaultVoice => const TtsVoice('v');

  @override
  Future<TtsSession> start(
    TtsAudioSink sink, {
    TtsVoice? voice,
    TtsAudioFormat? format,
    double? speed,
    double? volume,
    double? pitch,
  }) async {
    if (fails) throw const TtsException('boom');
    lastVoice = voice;
    return last = _FakeSession(sink, name);
  }
}

void main() {
  group('TtsAudioSink 实现', () {
    test('BytesAudioSink 累积字节', () async {
      final BytesAudioSink sink = BytesAudioSink()
        ..write(<int>[1, 2])
        ..write(<int>[3]);
      await sink.close();
      expect(sink.bytes, <int>[1, 2, 3]);
    });

    test('StreamAudioSink 按序投递并关闭', () async {
      final StreamAudioSink sink = StreamAudioSink();
      final Future<List<List<int>>> collected = sink.stream.toList();
      sink
        ..write(<int>[1])
        ..write(<int>[2]);
      await sink.close();
      expect(await collected, <List<int>>[
        <int>[1],
        <int>[2],
      ]);
    });
  });

  group('TtsService', () {
    test('register / providers / get', () {
      final TtsService service = TtsService();
      final Disposer off = service.register(_FakeProvider('a'));

      expect(service.providers.map((TtsProvider p) => p.name), <String>['a']);
      expect(service.get('a'), isNotNull);
      expect(service.get('nope'), isNull);

      off();
      expect(service.providers, isEmpty);
    });

    test('顺序回退：首个成功即返回', () async {
      final TtsService service = TtsService()
        ..register(_FakeProvider('a', fails: true))
        ..register(_FakeProvider('b'));

      final TtsSession session = await service.start(BytesAudioSink());
      expect(session, isA<_FakeSession>());
    });

    test('指定 provider / 无 provider / 全失败', () async {
      final TtsService service = TtsService()
        ..register(_FakeProvider('a'))
        ..register(_FakeProvider('b', fails: true));

      expect(
        await service.start(BytesAudioSink(), provider: 'a'),
        isA<_FakeSession>(),
      );
      await expectLater(
        service.start(BytesAudioSink(), provider: 'b'),
        throwsA(isA<TtsException>()),
      );
      await expectLater(
        service.start(BytesAudioSink(), provider: 'z'),
        throwsA(isA<TtsException>()),
      );
      await expectLater(
        TtsService().start(BytesAudioSink()),
        throwsA(isA<TtsException>()),
      );
    });

    test('synthesize 收集音频字节', () async {
      final _FakeProvider provider = _FakeProvider('a');
      final TtsService service = TtsService()..register(provider);

      final List<int> bytes = await service.synthesize('你好');

      expect(utf8.decode(bytes), 'audio:a:你好');
      expect(provider.last!.finished, isTrue);
    });

    test('speak 写入自定义 sink 并透传 voice', () async {
      final _FakeProvider provider = _FakeProvider('a');
      final TtsService service = TtsService()..register(provider);
      final BytesAudioSink sink = BytesAudioSink();

      await service.speak('hi', sink, voice: const TtsVoice('custom'));

      expect(utf8.decode(sink.bytes), 'audio:a:hi');
      expect(provider.lastVoice!.id, 'custom');
    });
  });

  group('provideTts / ctx.tts', () {
    test('默认注册豆包 provider', () {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);

      final TtsService service = provideTts(ctx);
      expect(service.providers.single.name, 'doubao');
      expect(identical(ctx.tts, service), isTrue);
    });

    test('显式 providers 随上下文释放撤销', () {
      final Context ctx = Context.root();
      final TtsService service =
          provideTts(ctx, providers: <TtsProvider>[_FakeProvider('x')]);

      expect(service.providers.single.name, 'x');
      ctx.dispose();
      expect(service.providers, isEmpty);
    });
  });

  group('DoubaoHttpTtsProvider', () {
    test('解析 base64 音频并写入 sink', () async {
      final Uint8List audio = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
      String? seenText;
      final http.Client client = MockClient((http.Request request) async {
        final Map<String, dynamic> body =
            jsonDecode(request.body) as Map<String, dynamic>;
        seenText = (body['request'] as Map<String, dynamic>)['text'] as String;
        final Map<String, dynamic> app = body['app'] as Map<String, dynamic>;
        expect(app['appid'], 'aid');
        return http.Response(
          jsonEncode(<String, Object?>{
            'code': 3000,
            'message': 'Success',
            'data': base64Encode(audio),
          }),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });

      final DoubaoHttpTtsProvider provider = DoubaoHttpTtsProvider(
        appId: 'aid',
        accessToken: 'tok',
        client: client,
      );
      final TtsService service = TtsService()..register(provider);

      final List<int> bytes = await service.synthesize('你好');
      expect(bytes, audio);
      expect(seenText, '你好');
    });

    test('业务错误码抛 TtsException', () async {
      final http.Client client = MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object?>{'code': 3001, 'message': 'bad'}),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      final TtsService service = TtsService()
        ..register(DoubaoHttpTtsProvider(
          appId: 'aid',
          accessToken: 'tok',
          client: client,
        ));

      await expectLater(
        service.synthesize('你好'),
        throwsA(isA<TtsException>()),
      );
    });

    test('缺少凭据时抛 TtsException', () async {
      final DoubaoHttpTtsProvider provider = DoubaoHttpTtsProvider(
        appId: '',
        accessToken: '',
        client: MockClient(
            (http.Request request) async => throw StateError('不应请求')),
      );

      await expectLater(
        provider.start(BytesAudioSink()),
        throwsA(isA<TtsException>()),
      );
    });
  });
}
