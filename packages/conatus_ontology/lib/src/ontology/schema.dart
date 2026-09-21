/// Schema 层：定义本体对象的字段和关系规则。
library;

/// 字段类型。
enum SchemaFieldType { string, stringArray, datetime }

/// 字段定义。
class SchemaField {
  const SchemaField(this.name, this.type, {this.required = false});

  final String name;
  final SchemaFieldType type;
  final bool required;
}

/// Schema 层。定义本体对象的字段和关系规则。
class OntologySchema {
  const OntologySchema({
    required this.nodeFields,
    required this.allowedRelations,
    required this.allowedReferences,
  });

  factory OntologySchema.defaults() => const OntologySchema(
        nodeFields: <String, List<SchemaField>>{
          'term': <SchemaField>[
            SchemaField('name', SchemaFieldType.string, required: true),
            SchemaField('definition', SchemaFieldType.string, required: true),
            SchemaField('aliases', SchemaFieldType.stringArray),
            SchemaField('domain', SchemaFieldType.string),
          ],
          'mapping': <SchemaField>[
            SchemaField('termId', SchemaFieldType.string, required: true),
            SchemaField('source', SchemaFieldType.string, required: true),
            SchemaField('expression', SchemaFieldType.string),
          ],
          'constraint': <SchemaField>[
            SchemaField('expression', SchemaFieldType.string, required: true),
            SchemaField('scope', SchemaFieldType.string, required: true),
            SchemaField('description', SchemaFieldType.string),
          ],
          'evidence': <SchemaField>[
            SchemaField('source', SchemaFieldType.string, required: true),
            SchemaField('observedAt', SchemaFieldType.datetime, required: true),
          ],
        },
        allowedRelations: <String>{
          'is_a',
          'part_of',
          'derives_from',
          'related_to',
        },
        allowedReferences: <String>{
          'mapped_to',
          'constrained_by',
          'supported_by',
        },
      );

  final Map<String, List<SchemaField>> nodeFields;
  final Set<String> allowedRelations;
  final Set<String> allowedReferences;
}

/// 校验结果。
class ValidationResult {
  const ValidationResult({this.isValid = true, this.message = ''});

  const ValidationResult.invalid(this.message) : isValid = false;

  final bool isValid;
  final String message;
}
