/// browser use 共享服务：只注册 Provider 名字，拒绝第二个注册。
library;

import 'package:conatus_core/conatus_core.dart';

import 'provider.dart';

/// Provider 名字。用于注册诊断。
typedef BrowserUseProviderName = String;

/// 共享的浏览器操作服务。
///
/// 只注册名称，拒绝第二个 Provider 注册（包括同名实例）。
/// 不包含通用浏览器操作方法、浏览器资源或模型控制的选择器。
abstract class BrowserUseRegistry {
  /// 预留唯一的 Provider 槽位，直到贡献被释放。
  ///
  /// 第二个注册会失败，即使它重复当前名称。
  /// Provider 必须在释放此注册前停止其工具并等待自有工作完成。
  ///
  /// [name] 是 Provider 拥有的名字，用于注册诊断。
  /// 返回此精确注册的 effect disposer。
  Future<Disposer> register(BrowserUseProviderName name);

  /// 当前已注册的 Provider 名字。未注册时为 null。
  String? get currentProvider;
}

/// [BrowserUseRegistry] 的默认实现。
///
/// 槽位语义：
///
/// 1. **唯一**：已有注册时，任何第二次注册（含同名）抛 [StateError]；
/// 2. **可释放**：返回的 [Disposer] 释放本次注册，释放后可重新注册；
/// 3. **幂等**：disposer 重复调用只释放一次。
class BrowserUseRegistryImpl implements BrowserUseRegistry {
  BrowserUseRegistryImpl([this.provider]);

  /// 装配时绑定的 Provider（[initializeBrowserFor] 用它为新 Session 初始化）。
  final BrowserUseProvider? provider;

  BrowserUseProviderName? _currentProvider;

  @override
  BrowserUseProviderName? get currentProvider => _currentProvider;

  @override
  Future<Disposer> register(BrowserUseProviderName name) async {
    return claim(name);
  }

  /// 同步预留槽位（装配路径用；[register] 的同步形式）。
  ///
  /// 已有注册（含同名）时抛 [StateError]；返回释放本次注册的 [Disposer]。
  Disposer claim(BrowserUseProviderName name) {
    if (_currentProvider != null) {
      throw StateError(
        'browser use Provider 已注册（当前：$_currentProvider），'
        '拒绝第二个注册：$name',
      );
    }
    _currentProvider = name;
    bool removed = false;
    return () {
      if (removed) return;
      removed = true;
      _currentProvider = null;
    };
  }
}
