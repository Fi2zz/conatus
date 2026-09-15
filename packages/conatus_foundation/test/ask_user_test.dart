import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('CliAskUser', () {
    test('ask 返回 submit 投递的值', () async {
      final ask = CliAskUser();
      final future = ask.ask('名字？');
      ask.submit('Alice');
      expect(await future, 'Alice');
    });

    test('多个提问按 FIFO 顺序完成', () async {
      final ask = CliAskUser();
      final f1 = ask.ask('a');
      final f2 = ask.ask('b');
      ask.submit('1');
      ask.submit('2');
      expect(await f1, '1');
      expect(await f2, '2');
    });

    test('cancel 使等待中的提问抛出 AskCancelledException', () async {
      final ask = CliAskUser();
      final future = ask.ask('x');
      ask.cancel();
      expect(future, throwsA(isA<AskCancelledException>()));
    });

    test('cancel 后再 ask 立即抛出', () {
      final ask = CliAskUser();
      ask.cancel();
      expect(() => ask.ask('x'), throwsA(isA<AskCancelledException>()));
    });
  });

  group('provideAskUser', () {
    test('将 AskUser 注册为服务', () {
      final ctx = Context.root();
      addTearDown(ctx.dispose);

      provideAskUser(ctx, askUser: CliAskUser());

      expect(ctx.has('askUser'), isTrue);
      expect(ctx.get<AskUser>('askUser'), isA<CliAskUser>());
    });

    test('上下文释放时取消所有提问', () async {
      final ctx = Context.root();
      final ask = CliAskUser();
      provideAskUser(ctx, askUser: ask);

      final future = ask.ask('x');
      ctx.dispose();

      expect(future, throwsA(isA<AskCancelledException>()));
    });
  });
}
