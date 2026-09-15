import 'dart:async';

import 'package:conatus_asr/conatus_asr.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:test/test.dart';

class _FakeSession implements AsrSession {
  _FakeSession(this.name);

  final String name;
  final StreamController<AsrEvent> _controller = StreamController<AsrEvent>();
  final List<int> received = <int>[];
  bool finished = false;
  bool closed = false;

  @override
  Stream<AsrEvent> get events => _controller.stream;

  @override
  void send(List<int> bytes) => received.addAll(bytes);

  @override
  Future<void> finish() async {
    finished = true;
    _controller.add(
      AsrFinal(AsrResult(text: 'text:$name', isFinal: true)),
    );
    await _controller.close();
  }

  @override
  void close() {
    closed = true;
    if (!_controller.isClosed) unawaited(_controller.close());
  }
}

class _FakeProvider implements AsrProvider {
  _FakeProvider(this.name, {this.fails = false});

  @override
  final String name;
  final bool fails;
  _FakeSession? last;
  AsrAudioFormat? lastAudio;
  String? lastLanguage;
  List<String>? lastHotwords;

  @override
  AsrAudioFormat get audioFormat => const AsrAudioFormat();

  @override
  Future<AsrSession> start({
    AsrAudioFormat? audio,
    String? language,
    List<String> hotwords = const <String>[],
  }) async {
    if (fails) throw const AsrException('boom');
    lastAudio = audio;
    lastLanguage = language;
    lastHotwords = hotwords;
    return last = _FakeSession(name);
  }
}

void main() {
  group('AsrService', () {
    test('register / providers / get', () {
      final AsrService service = AsrService();
      final Disposer off = service.register(_FakeProvider('a'));

      expect(
        service.providers.map((AsrProvider p) => p.name),
        <String>['a'],
      );
      expect(service.get('a'), isNotNull);
      expect(service.get('nope'), isNull);

      off();
      expect(service.providers, isEmpty);
    });

    test('顺序回退：首个成功即返回', () async {
      final AsrService service = AsrService()
        ..register(_FakeProvider('a', fails: true))
        ..register(_FakeProvider('b'));

      final AsrSession session = await service.start();
      expect(session, isA<_FakeSession>());
    });

    test('指定 provider 只走该 provider', () async {
      final AsrService service = AsrService()
        ..register(_FakeProvider('a'))
        ..register(_FakeProvider('b', fails: true));

      expect(await service.start(provider: 'a'), isA<_FakeSession>());
      await expectLater(
        service.start(provider: 'b'),
        throwsA(isA<AsrException>()),
      );
      await expectLater(
        service.start(provider: 'z'),
        throwsA(isA<AsrException>()),
      );
    });

    test('无 provider 或全部失败时抛 AsrException', () async {
      await expectLater(
        AsrService().start(),
        throwsA(isA<AsrException>()),
      );

      final AsrService failing = AsrService()
        ..register(_FakeProvider('a', fails: true));
      await expectLater(failing.start(), throwsA(isA<AsrException>()));
    });
  });

  group('transcribe', () {
    test('把字节流灌入会话并产出最终文本', () async {
      final _FakeProvider provider = _FakeProvider('a');
      final AsrService service = AsrService()..register(provider);

      final String text = await service.transcribeText(
        Stream<List<int>>.fromIterable(<List<int>>[
          <int>[1, 2],
          <int>[3],
        ]),
        language: 'zh-CN',
      );

      expect(text, 'text:a');
      expect(provider.last!.received, <int>[1, 2, 3]);
      expect(provider.last!.finished, isTrue);
      expect(provider.last!.closed, isTrue);
      expect(provider.lastLanguage, 'zh-CN');
    });

    test('transcribe 产出 partial 到 final 的事件序列', () async {
      final AsrService service = AsrService()..register(_FakeProvider('a'));

      final List<AsrEvent> events = await service
          .transcribe(Stream<List<int>>.fromIterable(<List<int>>[
            <int>[1],
          ]))
          .toList();

      expect(events, hasLength(1));
      final AsrEvent event = events.single;
      expect(event, isA<AsrFinal>());
      expect(event.result.text, 'text:a');
    });

    test('音频格式覆盖透传到 provider', () async {
      final _FakeProvider provider = _FakeProvider('a');
      final AsrService service = AsrService()..register(provider);

      await service.transcribeText(
        Stream<List<int>>.fromIterable(<List<int>>[
          <int>[1],
        ]),
        audioFormat: const AsrAudioFormat(format: 'wav'),
      );

      expect(provider.lastAudio!.format, 'wav');
    });
  });

  group('provideAsr / ctx.asr', () {
    test('默认注册豆包 provider', () {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);

      final AsrService service = provideAsr(ctx);
      expect(service.providers.single.name, 'doubao');
      expect(identical(ctx.asr, service), isTrue);
    });

    test('显式 providers 随上下文释放撤销', () {
      final Context ctx = Context.root();
      final AsrService service =
          provideAsr(ctx, providers: <AsrProvider>[_FakeProvider('x')]);

      expect(service.providers.single.name, 'x');
      ctx.dispose();
      expect(service.providers, isEmpty);
    });
  });

  group('DoubaoStreamingAsrProvider 鉴权', () {
    test('auth 动态鉴权头合并并覆盖默认头', () async {
      final _CapturingSocket socket = _CapturingSocket();
      final DoubaoStreamingAsrProvider provider = DoubaoStreamingAsrProvider(
        apiKey: 'static-key',
        connector: (Uri url, Map<String, String> headers) async {
          socket.headers = headers;
          return socket;
        },
        auth: () async => <String, String>{'Authorization': 'sig-123'},
      );

      final AsrSession session = await provider.start();
      expect(socket.headers!['Authorization'], 'sig-123');
      expect(socket.headers!['X-Api-Key'], 'static-key');
      expect(socket.headers!['X-Api-Resource-Id'], isNotEmpty);
      expect(socket.sent, hasLength(1)); // full client request
      session.close();
    });

    test('仅有 auth 时无需静态凭据', () async {
      final _CapturingSocket socket = _CapturingSocket();
      final DoubaoStreamingAsrProvider provider = DoubaoStreamingAsrProvider(
        apiKey: '',
        appKey: '',
        accessKey: '',
        connector: (Uri url, Map<String, String> headers) async {
          socket.headers = headers;
          return socket;
        },
        auth: () => <String, String>{'Authorization': 'Bearer t'},
      );

      final AsrSession session = await provider.start();
      expect(socket.headers!['Authorization'], 'Bearer t');
      expect(socket.headers!.containsKey('X-Api-Key'), isFalse);
      session.close();
    });

    test('无静态凭据且无 auth 时抛 AsrException', () async {
      final DoubaoStreamingAsrProvider provider = DoubaoStreamingAsrProvider(
        apiKey: '',
        appKey: '',
        accessKey: '',
        connector: (Uri url, Map<String, String> headers) async =>
            throw StateError('不应建连'),
      );

      await expectLater(provider.start(), throwsA(isA<AsrException>()));
    });
  });
}

/// 捕获建连头与出站帧的假 socket。
class _CapturingSocket implements AsrSocket {
  final StreamController<Object?> _incoming = StreamController<Object?>();
  final List<List<int>> sent = <List<int>>[];
  Map<String, String>? headers;

  @override
  Stream<Object?> get messages => _incoming.stream;

  @override
  void send(List<int> data) => sent.add(data);

  @override
  Future<void> close() async {
    if (!_incoming.isClosed) await _incoming.close();
  }
}
