/// 类型化编辑验证器：校验编辑是否符合 schema 约束。
library;

import 'edits.dart';
import 'layer.dart';
import 'node.dart';
import 'relation.dart';
import 'schema.dart';

/// 类型化编辑的验证器。
class TypedEditValidator {
  const TypedEditValidator(this.schema);

  final OntologySchema schema;

  /// 验证编辑是否合法。
  ///
  /// 检查：
  /// · 节点类型是否在 schema 中定义
  /// · 字段是否符合类型约束、必填字段齐全
  /// · 关系类型是否在 allowedRelations 中
  /// · 引用类型是否在 allowedReferences 中
  /// · 引用的对象是否存在
  ValidationResult validate(TypedEdit edit, OntologyLayer layer) {
    return switch (edit) {
      AddNode(:final OntologyNode node) => _validateNode(node, layer),
      RemoveNode(:final String nodeId) =>
        _requireNode(layer, nodeId, '删除的节点不存在'),
      UpdateNodeFields(:final String nodeId, :final fields) =>
        _validateFields(layer, nodeId, fields),
      AddRelation(:final SemanticRelation relation) =>
        _validateRelation(relation, layer),
      RemoveRelation(:final String relationId) =>
        _requireRelation(layer, relationId, '删除的关系不存在'),
      AddReference(:final StructuralReference reference) =>
        _validateReference(reference, layer),
      RemoveReference(:final String referenceId) =>
        _requireReference(layer, referenceId, '删除的引用不存在'),
      MergeTerms(:final String sourceTermId, :final String targetTermId) =>
        _validateMerge(layer, sourceTermId, targetTermId),
      SplitTerm(:final String sourceTermId, :final List<Term> newTerms) =>
        _validateSplit(layer, sourceTermId, newTerms),
    };
  }

  ValidationResult _validateNode(OntologyNode node, OntologyLayer layer) {
    if (layer.node(node.id) != null) {
      return ValidationResult.invalid('节点 ${node.id} 已存在');
    }
    final List<SchemaField>? fields = schema.nodeFields[node.type];
    if (fields == null) {
      return ValidationResult.invalid('节点类型 ${node.type} 未在 schema 中定义');
    }
    final Map<String, Object?> json = node.toJson();
    for (final SchemaField field in fields) {
      final Object? value = json[field.name];
      if (field.required && value == null) {
        return ValidationResult.invalid('字段 ${field.name} 必填');
      }
      if (value == null) continue;
      if (!_typeMatches(field.type, value)) {
        return ValidationResult.invalid(
            '字段 ${field.name} 类型不符（期望 ${field.type.name}）');
      }
    }
    return const ValidationResult();
  }

  ValidationResult _validateFields(
      OntologyLayer layer, String nodeId, Map<String, Object?> fields) {
    final OntologyNode? node = layer.node(nodeId);
    if (node == null) return ValidationResult.invalid('节点 $nodeId 不存在');
    final List<SchemaField>? allowed = schema.nodeFields[node.type];
    if (allowed == null) {
      return ValidationResult.invalid('节点类型 ${node.type} 未在 schema 中定义');
    }
    for (final MapEntry<String, Object?> entry in fields.entries) {
      final SchemaField? field =
          _findField(allowed, entry.key);
      if (field == null) {
        return ValidationResult.invalid('字段 ${entry.key} 不在 schema 中');
      }
      if (!_typeMatches(field.type, entry.value)) {
        return ValidationResult.invalid(
            '字段 ${entry.key} 类型不符（期望 ${field.type.name}）');
      }
    }
    return const ValidationResult();
  }

  ValidationResult _validateRelation(
      SemanticRelation relation, OntologyLayer layer) {
    if (!schema.allowedRelations.contains(relation.kind)) {
      return ValidationResult.invalid('关系类型 ${relation.kind} 不被允许');
    }
    if (layer.node(relation.fromTermId) == null ||
        layer.node(relation.toTermId) == null) {
      return const ValidationResult.invalid('关系引用的 Term 不存在');
    }
    return const ValidationResult();
  }

  ValidationResult _validateReference(
      StructuralReference reference, OntologyLayer layer) {
    if (!schema.allowedReferences.contains(reference.kind)) {
      return ValidationResult.invalid('引用类型 ${reference.kind} 不被允许');
    }
    if (layer.node(reference.fromId) == null ||
        layer.node(reference.toId) == null) {
      return const ValidationResult.invalid('引用连接的对象不存在');
    }
    return const ValidationResult();
  }

  ValidationResult _validateMerge(
      OntologyLayer layer, String sourceTermId, String targetTermId) {
    if (sourceTermId == targetTermId) {
      return const ValidationResult.invalid('不能合并同一个 Term');
    }
    if (layer.node(sourceTermId) == null || layer.node(targetTermId) == null) {
      return const ValidationResult.invalid('被合并的 Term 不存在');
    }
    return const ValidationResult();
  }

  ValidationResult _validateSplit(
      OntologyLayer layer, String sourceTermId, List<Term> newTerms) {
    if (layer.node(sourceTermId) == null) {
      return const ValidationResult.invalid('被拆分的 Term 不存在');
    }
    if (newTerms.isEmpty) {
      return const ValidationResult.invalid('拆分必须产出至少一个新 Term');
    }
    for (final Term term in newTerms) {
      final ValidationResult result = _validateNode(term, layer);
      if (!result.isValid) return result;
    }
    return const ValidationResult();
  }

  ValidationResult _requireNode(OntologyLayer layer, String id, String message) =>
      layer.node(id) == null ? ValidationResult.invalid(message) : const ValidationResult();

  ValidationResult _requireRelation(
          OntologyLayer layer, String id, String message) =>
      layer.relations.any((r) => r.id == id)
          ? const ValidationResult()
          : ValidationResult.invalid(message);

  ValidationResult _requireReference(
          OntologyLayer layer, String id, String message) =>
      layer.references.any((r) => r.id == id)
          ? const ValidationResult()
          : ValidationResult.invalid(message);

  static SchemaField? _findField(List<SchemaField> fields, String name) {
    for (final SchemaField field in fields) {
      if (field.name == name) return field;
    }
    return null;
  }

  static bool _typeMatches(SchemaFieldType type, Object? value) {
    return switch (type) {
      SchemaFieldType.string => value is String,
      SchemaFieldType.stringArray =>
        value is List && value.every((Object? item) => item is String),
      SchemaFieldType.datetime => value is String && DateTime.tryParse(value) != null,
    };
  }
}
