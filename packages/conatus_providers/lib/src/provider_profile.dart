/// 模型提供商配置：端点、凭据键与可选模型清单。
library;

import 'package:conatus_llm/conatus_llm.dart';

/// 一个模型提供商的配置。
///
/// [credentialKey] 是环境变量 / 凭据服务里的键名（如 `ARK_API_KEY`），
/// 密钥本身不进配置；[models] 是可选模型清单，首个为默认模型。
class ProviderProfile {
  const ProviderProfile({
    required this.name,
    required this.baseUrl,
    this.credentialKey = '',
    this.models = const <String>[],
    this.apiStyle = LlmApiStyle.chat,
    this.description = '',
    this.userAgent = '',
  });

  /// 从 JSON 反序列化；缺 `name` / `baseUrl` 时抛 [FormatException]。
  factory ProviderProfile.fromJson(Map<String, Object?> json) {
    final Object? name = json['name'];
    final Object? baseUrl = json['baseUrl'];
    if (name is! String || name.isEmpty || baseUrl is! String || baseUrl.isEmpty) {
      throw const FormatException('provider 需要非空的 name 与 baseUrl');
    }
    return ProviderProfile(
      name: name,
      baseUrl: baseUrl,
      credentialKey: json['credentialKey'] as String? ?? '',
      models: <String>[
        for (final Object? model
            in (json['models'] as List<Object?>?) ?? const <Object?>[])
          if (model is String) model,
      ],
      apiStyle:
          json['apiStyle'] == 'responses' ? LlmApiStyle.responses : LlmApiStyle.chat,
      description: json['description'] as String? ?? '',
      userAgent: json['userAgent'] as String? ?? '',
    );
  }

  /// 提供商名（如 `'deepseek'`）。
  final String name;

  /// OpenAI 兼容端点根地址（如 `'https://api.deepseek.com'`）。
  final String baseUrl;

  /// 凭据键名；空串表示无凭据。
  final String credentialKey;

  /// 可选模型清单；首个为默认模型。
  final List<String> models;

  /// 请求形态。
  final LlmApiStyle apiStyle;

  /// 列表里展示的补充说明（可空）。
  final String description;

  /// 请求携带的 User-Agent（空串用默认 `ConatusCode/0.16`；可伪装成其他
  /// harness 客户端，如 dsh）。
  final String userAgent;

  /// 默认模型；无清单返回 `null`。
  String? get defaultModel => models.isEmpty ? null : models.first;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'baseUrl': baseUrl,
        if (credentialKey.isNotEmpty) 'credentialKey': credentialKey,
        if (models.isNotEmpty) 'models': models,
        'apiStyle': apiStyle.name,
        if (description.isNotEmpty) 'description': description,
        if (userAgent.isNotEmpty) 'userAgent': userAgent,
      };
}
