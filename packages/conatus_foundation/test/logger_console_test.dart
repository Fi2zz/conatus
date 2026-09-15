import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

class _Collector implements LogExporter {
  _Collector(this.records);

  final List<LogRecord> records;

  @override
  void export(LogRecord record) => records.add(record);
}

void main() {
  group('LoggerService', () {
    test('按级别过滤', () {
      final service = LoggerService(level: LogLevel.warn);
      final records = <LogRecord>[];
      service.addExporter(_Collector(records));

      service.debug('d');
      service.info('i');
      service.warn('w');
      service.error('e');

      expect(records.map((LogRecord r) => r.message), <String>['w', 'e']);
    });

    test('命名 logger 记录名字、错误与堆栈', () {
      final service = LoggerService();
      final records = <LogRecord>[];
      service.addExporter(_Collector(records));
      final StackTrace stackTrace = StackTrace.current;

      service.logger('chat').warn('超时', StateError('boom'), stackTrace);

      final LogRecord record = records.single;
      expect(record.level, LogLevel.warn);
      expect(record.name, 'chat');
      expect(record.message, '超时');
      expect(record.error, isA<StateError>());
      expect(record.stackTrace, same(stackTrace));
    });

    test('removeExporter 移除导出器', () {
      final service = LoggerService();
      final collector = _Collector(<LogRecord>[]);

      service.addExporter(collector);
      expect(service.exporters, hasLength(1));
      expect(service.removeExporter(collector), isTrue);
      expect(service.removeExporter(collector), isFalse);
      expect(service.exporters, isEmpty);
    });

    test('recent 缓冲受 recentLimit 限制', () {
      final service = LoggerService()..recentLimit = 2;

      service.info('1');
      service.info('2');
      service.info('3');

      expect(
        service.recent.map((LogRecord r) => r.message),
        <String>['2', '3'],
      );
    });
  });

  group('ConsoleExporter', () {
    test('格式化并按自身级别过滤', () {
      final lines = <String>[];
      final service = LoggerService();
      service.addExporter(
        ConsoleExporter(writer: lines.add, level: LogLevel.info),
      );

      service.debug('d');
      service.info('hi');
      service.error('boom', StateError('x'));

      expect(lines, hasLength(2));
      expect(lines[0], '[I] root  hi');
      expect(lines[1], startsWith('[E] root  boom'));
    });

    test('showTime 前缀 ISO 时间', () {
      final lines = <String>[];
      final service = LoggerService();
      service.addExporter(
        ConsoleExporter(writer: lines.add, showTime: true),
      );

      service.info('hi');

      expect(lines.single, matches(RegExp(r'^\S+ \[I\] root  hi$')));
    });
  });

  group('provideLogger', () {
    test('注册服务并随上下文释放移除导出器', () {
      final ctx = Context.root();
      final service = provideLogger(ctx);

      expect(ctx.has('logger'), isTrue);
      expect(ctx.require<LoggerService>('logger'), same(service));
      expect(service.exporters, hasLength(1));

      ctx.dispose();
      expect(service.exporters, isEmpty);
    });

    test('console: false 时不挂控制台导出器', () {
      final ctx = Context.root();
      addTearDown(ctx.dispose);

      final service = provideLogger(ctx, console: false);
      expect(service.exporters, isEmpty);
    });
  });
}
