/// 图像路由：按模型能力分级截图投递。
library;

/// 图像支持级别。
enum ImageSupport {
  /// 支持图像。接收持久化截图。
  persistent,

  /// 不支持图像。接收 MCP 图像诊断。
  diagnostic,

  /// 完全不支持。截图被忽略。
  none,
}

/// 根据模型路由判断图像支持级别。
///
/// 支持视觉的模型接收 [ImageSupport.persistent]（挂附件存储时持久化截图）；
/// 其余模型接收 [ImageSupport.diagnostic]（MCP 图像诊断，文本描述）。
ImageSupport imageSupportFor(String provider, String model) {
  if (_visionModels.contains('$provider/$model')) {
    return ImageSupport.persistent;
  }
  return ImageSupport.diagnostic;
}

const Set<String> _visionModels = <String>{
  'doubao/doubao-seed-1-8-251228',
  'doubao/doubao-vision-pro',
};
