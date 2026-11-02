class MspSignalOptions {
  MspSignalOptions({this.pattern, this.target, this.path, this.reqid});

  final String? pattern;
  final String? target;
  final String? path;
  final String? reqid;
  Map<String, Object?> payload = <String, Object?>{};
  double? timestamp;
}

class MspSignal {
  MspSignal({
    required this.type,
    required this.source,
    MspSignalOptions? options,
  }) : options = options ?? MspSignalOptions();

  factory MspSignal.fromJson(Map<String, Object?> json) {
    final MspSignalOptions options = MspSignalOptions(
      pattern: json['pattern'] as String?,
      target: json['target'] as String?,
      path: json['path'] as String?,
      reqid: json['reqid'] as String?,
    )
      ..payload = _readPayload(json['payload'])
      ..timestamp = _readTimestamp(json['timestamp']);
    return MspSignal(
      type: _readRequiredString(json, 'type'),
      source: _readRequiredString(json, 'source'),
      options: options,
    );
  }

  final String type;
  final String source;
  final MspSignalOptions options;

  String? get pattern => options.pattern;
  String? get target => options.target;
  String? get path => options.path;
  String? get reqid => options.reqid;
  Map<String, Object?> get payload => options.payload;
  double get timestamp => options.timestamp ?? 0;

  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        'source': source,
        'pattern': pattern,
        'target': target,
        'path': path,
        'reqid': reqid,
        'payload': payload,
        'timestamp': options.timestamp ?? _nowSeconds(),
      };
}

String _readRequiredString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String) throw FormatException('Signal.$key 必须为字符串');
  return value;
}

Map<String, Object?> _readPayload(Object? value) {
  if (value == null) return <String, Object?>{};
  if (value is! Map) throw const FormatException('Signal.payload 必须为对象');
  return Map<String, Object?>.from(value);
}

double _readTimestamp(Object? value) =>
    value is num ? value.toDouble() : _nowSeconds();

double _nowSeconds() => DateTime.now().microsecondsSinceEpoch / 1000000;
