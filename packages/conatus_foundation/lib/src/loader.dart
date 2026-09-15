/// loader 插件：按名注册插件工厂 + 声明式配置树。
///
/// Dart 没有动态 `import()`，因此 loader 用**注册表**代替模块解析：
/// 宿主先 `register('name', factory)`，再用配置树声明要加载哪些插件。
///
/// ```dart
/// final loader = provideLoader(app, plugins: <String, PluginFactory>{
///   'logger': (ctx, config) => provideLogger(ctx),
/// });
/// loader.apply(<LoaderEntry>[
///   const LoaderEntry(id: 'logger', name: 'logger'),
/// ]);
/// loader.reload('logger'); // 重启该 entry
/// ```
library;

import 'package:conatus_core/conatus_core.dart';

/// 插件工厂：接收子上下文与配置，在子上下文上施加副作用。
typedef PluginFactory = void Function(Context ctx, Object? config);

/// loader 相关错误。
class LoaderException implements Exception {
  const LoaderException(this.message);

  final String message;

  @override
  String toString() => 'LoaderException: $message';
}

/// loader 配置树的一个节点。
///
/// [name] 为 null 时是分组节点，本身不加载插件，只承载 [children]。
class LoaderEntry {
  const LoaderEntry({
    this.id,
    this.name,
    this.config,
    this.disabled = false,
    this.children = const <LoaderEntry>[],
  });

  /// 从 JSON 反序列化。
  factory LoaderEntry.fromJson(Map<String, Object?> json) => LoaderEntry(
        id: json['id'] as String?,
        name: json['name'] as String?,
        config: json['config'],
        disabled: (json['disabled'] as bool?) ?? false,
        children: <LoaderEntry>[
          for (final Object? child
              in (json['children'] as List<Object?>?) ?? const <Object?>[])
            LoaderEntry.fromJson(child as Map<String, Object?>),
        ],
      );

  /// 稳定 id；缺省时由 [Loader] 自动生成。
  final String? id;

  /// 插件名（注册表键）；null 表示分组。
  final String? name;

  /// 传给插件工厂的配置。
  final Object? config;

  /// 禁用该 entry（分组不受影响）。
  final bool disabled;

  /// 子节点。
  final List<LoaderEntry> children;

  /// 是否是分组节点。
  bool get isGroup => name == null;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        if (id != null) 'id': id,
        if (name != null) 'name': name,
        if (config != null) 'config': config,
        if (disabled) 'disabled': true,
        if (children.isNotEmpty)
          'children': <Map<String, Object?>>[
            for (final LoaderEntry child in children) child.toJson(),
          ],
      };
}

/// 装载器服务：持有插件注册表与已加载的 entry 树。
///
/// 已加载的 entry 都是装载器上下文的子上下文，随宿主上下文释放而自动卸载。
class Loader {
  Loader(this._ctx, {Map<String, PluginFactory>? plugins}) {
    if (plugins != null) _factories.addAll(plugins);
  }

  final Context _ctx;
  final Map<String, PluginFactory> _factories = <String, PluginFactory>{};
  final Map<String, LoaderEntry> _entries = <String, LoaderEntry>{};
  final Map<String, Context> _running = <String, Context>{};
  int _seq = 0;

  // ── 注册表 ──────────────────────────────────────────────

  /// 注册一个插件工厂；同名会覆盖。
  void register(String name, PluginFactory factory) {
    if (name.isEmpty) throw const LoaderException('插件名不能为空');
    _factories[name] = factory;
  }

  /// 注销一个插件工厂。返回是否确实移除了一个。
  bool unregister(String name) => _factories.remove(name) != null;

  /// 是否已注册某插件。
  bool has(String name) => _factories.containsKey(name);

  /// 已注册的插件名。
  List<String> get names => _factories.keys.toList(growable: false);

  // ── 配置树 ──────────────────────────────────────────────

  /// 已加载 entry 的 id（按加载顺序）。
  List<String> get ids => _entries.keys.toList(growable: false);

  /// 是否没有任何 entry。
  bool get isEmpty => _entries.isEmpty;

  /// entry 对应的插件子上下文；未加载或未运行时为 null。
  Context? contextOf(String id) => _running[id];

  /// entry 的配置节点。
  LoaderEntry? entryOf(String id) => _entries[id];

  /// 全量替换配置树：先卸载现有 entry，再按 [entries] 重新加载。
  void apply(List<LoaderEntry> entries) {
    for (final String id in _entries.keys.toList().reversed) {
      _running.remove(id)?.dispose();
    }
    _entries.clear();
    for (final LoaderEntry entry in entries) {
      load(entry);
    }
  }

  /// 从 JSON 配置全量替换配置树。
  void applyJson(List<Map<String, Object?>> entries) =>
      apply(<LoaderEntry>[for (final e in entries) LoaderEntry.fromJson(e)]);

  /// 加载一个 entry，返回其 id。分组会递归加载 [LoaderEntry.children]。
  String load(LoaderEntry entry, {String? parent}) {
    final String id = entry.id ?? _nextId(parent);
    if (_entries.containsKey(id)) {
      throw LoaderException('entry "$id" 已存在');
    }
    _entries[id] = entry;

    if (!entry.isGroup && !entry.disabled) {
      final PluginFactory? factory = _factories[entry.name];
      if (factory == null) {
        _entries.remove(id);
        throw LoaderException('未注册的插件 "${entry.name}"（entry "$id"）');
      }
      _running[id] =
          _ctx.plugin(id, (Context child) => factory(child, entry.config));
    }

    for (final LoaderEntry child in entry.children) {
      load(child, parent: id);
    }
    return id;
  }

  /// 卸载 entry 及其所有后代。
  void remove(String id) {
    final List<String> targets = _entries.keys
        .where((String key) => key == id || key.startsWith('$id:'))
        .toList()
        .reversed
        .toList();
    if (targets.isEmpty) throw LoaderException('未知 entry "$id"');
    for (final String key in targets) {
      _running.remove(key)?.dispose();
      _entries.remove(key);
    }
  }

  /// 重启单个 entry 的插件（分组与禁用项不重启）。
  void reload(String id) {
    final LoaderEntry? entry = _entries[id];
    if (entry == null) throw LoaderException('未知 entry "$id"');
    _running.remove(id)?.dispose();
    if (entry.isGroup || entry.disabled) return;
    final PluginFactory? factory = _factories[entry.name];
    if (factory == null) {
      throw LoaderException('未注册的插件 "${entry.name}"（entry "$id"）');
    }
    _running[id] =
        _ctx.plugin(id, (Context child) => factory(child, entry.config));
  }

  String _nextId(String? parent) {
    _seq += 1;
    final String id = 'entry-$_seq';
    return parent == null ? id : '$parent:$id';
  }
}

/// 将 [Loader] 提供到上下文，可选预注册插件并立即加载 [config]。
Loader provideLoader(
  Context ctx, {
  Map<String, PluginFactory>? plugins,
  List<LoaderEntry>? config,
}) {
  final Loader loader = Loader(ctx, plugins: plugins);
  ctx.provide('loader', loader);
  if (config != null) loader.apply(config);
  return loader;
}
