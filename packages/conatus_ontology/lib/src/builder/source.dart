/// 数据源描述：本体接地验证的输入。
library;

/// 数据源中的一列。
class DataColumn {
  const DataColumn({
    required this.name,
    required this.type,
    this.description,
  });

  factory DataColumn.fromJson(Map<String, Object?> json) => DataColumn(
        name: json['name']! as String,
        type: json['type']! as String,
        description: json['description'] as String?,
      );

  final String name;
  final String type;
  final String? description;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'type': type,
        'description': description,
      };
}

/// 数据源（表 / 文件 / 数据库）。承载 schema 与样本值，
/// 供概念提取与接地验证使用。
class DataSource {
  const DataSource({
    required this.id,
    required this.name,
    this.kind = 'table',
    this.columns = const <DataColumn>[],
    this.sampleRows = const <Map<String, Object?>>[],
  });

  factory DataSource.fromJson(Map<String, Object?> json) => DataSource(
        id: json['id']! as String,
        name: json['name']! as String,
        kind: json['kind']! as String? ?? 'table',
        columns: <DataColumn>[
          for (final Object? column in json['columns']! as List)
            DataColumn.fromJson(Map<String, Object?>.from(column! as Map)),
        ],
        sampleRows: <Map<String, Object?>>[
          for (final Object? row in json['sampleRows']! as List)
            Map<String, Object?>.from(row! as Map),
        ],
      );

  final String id;
  final String name;
  final String kind;
  final List<DataColumn> columns;
  final List<Map<String, Object?>> sampleRows;

  /// 列名集合。
  Set<String> get columnNames => <String>{
        for (final DataColumn column in columns) column.name,
      };

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'kind': kind,
        'columns': <Map<String, Object?>>[
          for (final DataColumn column in columns) column.toJson(),
        ],
        'sampleRows': sampleRows,
      };
}
