/// logger-console 插件：内置 logger 服务 + 控制台导出器。
///
/// conatus 核心不带 logger，因此本插件自带 [LoggerService]
/// （分级、命名 logger、可插拔导出器）并默认挂一个 [ConsoleExporter]。
///
/// ```dart
/// final loggerService = provideLogger(app);
/// loggerService.info('服务已启动');
/// final chat = loggerService.logger('chat');
/// chat.warn('会话超时', error, stackTrace);
/// ```
library;

import 'dart:io';
import 'package:conatus_core/conatus_core.dart';

/// 日志级别，严重度 `debug < info < warn < error`。
enum LogLevel {
  debug(0),
  info(1),
  warn(2),
  error(3);

  const LogLevel(this.severity);

  /// 严重度，越大越严重。
  final int severity;
}

/// 一条结构化日志。
class LogRecord {
  const LogRecord({
    required this.level,
    required this.name,
    required this.message,
    required this.time,
    this.error,
    this.stackTrace,
  });

  final LogLevel level;
  final String name;
  final Object? message;
  final DateTime time;
  final Object? error;
  final StackTrace? stackTrace;
}

/// 日志导出器（sink）。
abstract class LogExporter {
  /// 导出一条日志。
  void export(LogRecord record);
}

/// 命名 logger 门面。
class Logger {
  Logger(this.name, this._service);

  final String name;
  final LoggerService _service;

  /// 记录 debug 级日志。
  void debug(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _service._emit(LogLevel.debug, name, message, error, stackTrace);

  /// 记录 info 级日志。
  void info(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _service._emit(LogLevel.info, name, message, error, stackTrace);

  /// 记录 warn 级日志。
  void warn(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _service._emit(LogLevel.warn, name, message, error, stackTrace);

  /// 记录 error 级日志。
  void error(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _service._emit(LogLevel.error, name, message, error, stackTrace);
}

/// 内置日志服务。
class LoggerService {
  LoggerService({this.defaultName = 'root', this.level = LogLevel.info});

  /// 直接用服务方法记录日志时使用的名字。
  final String defaultName;

  /// 全局最小级别；低于它的日志被丢弃。
  LogLevel level;

  final List<LogExporter> _exporters = <LogExporter>[];
  final List<LogRecord> _recent = <LogRecord>[];

  /// [recent] 保留的最大条数。
  int recentLimit = 100;

  /// 已登记的导出器。
  List<LogExporter> get exporters => List<LogExporter>.unmodifiable(_exporters);

  /// 最近记录的日志（最多 [recentLimit] 条）。
  List<LogRecord> get recent => List<LogRecord>.unmodifiable(_recent);

  /// 创建一个命名 logger。
  Logger logger([String? name]) => Logger(name ?? defaultName, this);

  /// 登记一个导出器。
  void addExporter(LogExporter exporter) => _exporters.add(exporter);

  /// 移除一个导出器。返回是否确实移除了一个实例。
  bool removeExporter(LogExporter exporter) => _exporters.remove(exporter);

  /// 以 [defaultName] 记录 debug 级日志。
  void debug(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _emit(LogLevel.debug, defaultName, message, error, stackTrace);

  /// 以 [defaultName] 记录 info 级日志。
  void info(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _emit(LogLevel.info, defaultName, message, error, stackTrace);

  /// 以 [defaultName] 记录 warn 级日志。
  void warn(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _emit(LogLevel.warn, defaultName, message, error, stackTrace);

  /// 以 [defaultName] 记录 error 级日志。
  void error(Object? message, [Object? error, StackTrace? stackTrace]) =>
      _emit(LogLevel.error, defaultName, message, error, stackTrace);

  void _emit(
    LogLevel messageLevel,
    String name,
    Object? message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    if (messageLevel.severity < level.severity) return;
    final LogRecord record = LogRecord(
      level: messageLevel,
      name: name,
      message: message,
      error: error,
      stackTrace: stackTrace,
      time: DateTime.now(),
    );
    _recent.add(record);
    if (_recent.length > recentLimit) {
      _recent.removeRange(0, _recent.length - recentLimit);
    }
    for (final LogExporter exporter in List<LogExporter>.of(_exporters)) {
      exporter.export(record);
    }
  }
}

/// 写入一整行的 sink；默认写 `stdout`。
typedef LogWriter = void Function(String line);

/// 控制台导出器：格式 `[I] name  message`。
class ConsoleExporter implements LogExporter {
  ConsoleExporter({LogWriter? writer, this.level, this.showTime = false})
      : _writer = writer ?? _stdoutWriter;

  final LogWriter _writer;

  /// 导出器自身的级别过滤；null 表示不过滤（由服务级别决定）。
  final LogLevel? level;

  /// 是否在行首输出 ISO 时间。
  final bool showTime;

  @override
  void export(LogRecord record) {
    final LogLevel? threshold = level;
    if (threshold != null && record.level.severity < threshold.severity) {
      return;
    }
    final StringBuffer buffer = StringBuffer();
    if (showTime) buffer.write('${record.time.toIso8601String()} ');
    buffer
      ..write('[${_tag(record.level)}] ')
      ..write(record.name)
      ..write('  ')
      ..write(record.message);
    if (record.error != null) {
      buffer
        ..write(' ')
        ..write(record.error);
    }
    _writer(buffer.toString());
    final StackTrace? stackTrace = record.stackTrace;
    if (stackTrace != null) _writer(stackTrace.toString());
  }

  static void _stdoutWriter(String line) => stdout.writeln(line);

  static String _tag(LogLevel level) => switch (level) {
        LogLevel.debug => 'D',
        LogLevel.info => 'I',
        LogLevel.warn => 'W',
        LogLevel.error => 'E',
      };
}

/// 将 [LoggerService] 提供到上下文，并按需挂上控制台导出器。
///
/// 返回该服务，便于直接取得命名 logger。上下文释放时移除本插件添加的导出器。
LoggerService provideLogger(
  Context ctx, {
  LoggerService? logger,
  LogLevel level = LogLevel.info,
  bool console = true,
  LogWriter? writer,
  bool showTime = false,
}) {
  final LoggerService service =
      logger ?? LoggerService(defaultName: ctx.name, level: level);
  ctx.provide('logger', service);
  if (console) {
    final ConsoleExporter exporter =
        ConsoleExporter(writer: writer, showTime: showTime);
    service.addExporter(exporter);
    ctx.onDispose(() => service.removeExporter(exporter));
  }
  return service;
}
