/// providers.json 持久化：读写 `{current, providers}` 结构。
library;

import 'dart:convert';
import 'dart:io';

import 'provider_profile.dart';

/// 注册表快照。
class ProviderSnapshot {
  const ProviderSnapshot({
    this.providers = const <ProviderProfile>[],
    this.current,
  });

  /// 提供商列表。
  final List<ProviderProfile> providers;

  /// 当前选中的提供商名。
  final String? current;
}

/// JSON 文件存储。
///
/// 文件缺失或损坏时 [load] 返回空快照（由注册表回落到内置默认），不抛异常。
class ProviderStore {
  ProviderStore({required this.path});

  /// 文件路径。
  final String path;

  /// 读快照。
  ProviderSnapshot load() {
    final File file = File(path);
    if (!file.existsSync()) {
      return const ProviderSnapshot();
    }
    try {
      final Object? raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map<String, Object?>) {
        return const ProviderSnapshot();
      }
      return ProviderSnapshot(
        providers: <ProviderProfile>[
          for (final Object? item in _items(raw))
            if (item is Map<String, Object?>) ProviderProfile.fromJson(item),
        ],
        current: raw['current'] as String?,
      );
    } on FormatException {
      return const ProviderSnapshot();
    }
  }

  /// 写快照（父目录自动创建）。
  void save(ProviderSnapshot snapshot) {
    final File file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'current': snapshot.current,
        'providers': <Map<String, Object?>>[
          for (final ProviderProfile profile in snapshot.providers)
            profile.toJson(),
        ],
      }),
    );
  }

  static List<Object?> _items(Map<String, Object?> raw) =>
      (raw['providers'] as List<Object?>?) ?? const <Object?>[];
}
