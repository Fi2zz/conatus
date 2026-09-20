/// 意图路由器契约。
library;

import 'events.dart';
import 'intent.dart';
import 'route.dart';

/// 意图路由器。
///
/// 只做「注册 + 匹配」：先跑正则，未命中再跑向量，都未命中返回
/// [RouteResult.missed]。要把命中结果接进 Agent Loop，见 `IntentRouterAdapter`。
abstract interface class IntentRouter {
  /// 注册意图。重名抛 `IntentException`（`duplicate`）。
  void register(Intent intent);

  /// 注销意图。未注册的名字是 no-op。
  void unregister(String name);

  /// 路由。
  ///
  /// [state] 是动作执行时可见的附加状态（设备状态、用户偏好等）。
  Future<RouteResult> route(String input, {Map<String, Object?>? state});

  /// 已注册的意图（按注册顺序）。
  List<Intent> get intents;

  /// 变更流：注册 / 注销 / 命中 / 未命中。
  Stream<IntentEvent> get changes;

  /// 释放资源：关闭 [changes]，并释放持有的嵌入提供者。
  void dispose();
}
