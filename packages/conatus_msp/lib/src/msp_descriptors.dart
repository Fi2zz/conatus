class MspSignalDescriptor {
  const MspSignalDescriptor({
    required this.path,
    this.schema = const <String, Object?>{},
    this.description = '',
  });

  factory MspSignalDescriptor.fromJson(Map<String, Object?> json) =>
      MspSignalDescriptor(
        path: json['path'] as String,
        schema: _readObject(json['schema']),
        description: json['description'] as String? ?? '',
      );

  final String path;
  final Map<String, Object?> schema;
  final String description;

  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        if (schema.isNotEmpty) 'schema': schema,
        if (description.isNotEmpty) 'description': description,
      };
}

class MspToolDescriptor {
  const MspToolDescriptor({
    required this.name,
    this.description = '',
    this.inputSchema = const <String, Object?>{},
  });

  factory MspToolDescriptor.fromJson(Map<String, Object?> json) =>
      MspToolDescriptor(
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        inputSchema: _readObject(json['inputSchema']),
      );

  final String name;
  final String description;
  final Map<String, Object?> inputSchema;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'description': description,
        'inputSchema': inputSchema,
        'outputTypes': <String>[],
        'annotations': <String, Object?>{},
      };
}

Map<String, Object?> _readObject(Object? value) {
  if (value is Map) return Map<String, Object?>.from(value);
  return <String, Object?>{};
}
