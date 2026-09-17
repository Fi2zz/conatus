/// 浏览器工具的风险映射：Provider 工具集的风险分级（handoff-9 第 8 节）。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// 按工具名映射 [ToolRisk]。
///
/// - `low`：只读操作（导航、快照、等待、截图）；
/// - `medium`：交互操作（点击、输入、选择、按键）；
/// - `high`：敏感操作（执行 JS、上传、下载、提交表单）。
///
/// 未列出的工具一律 [ToolRisk.medium]——宁可多问一次，也不要让未知的
/// 写操作静默执行。
ToolRisk browserToolRisk(String toolName) {
  if (_lowRisk.contains(toolName)) return ToolRisk.low;
  if (_highRisk.contains(toolName)) return ToolRisk.high;
  return ToolRisk.medium;
}

const Set<String> _lowRisk = <String>{
  'browser_navigate',
  'browser_snapshot',
  'browser_wait_for',
  'browser_take_screenshot',
  'browser_screenshot',
};

const Set<String> _highRisk = <String>{
  'browser_evaluate',
  'browser_file_upload',
  'browser_download',
  'browser_submit',
  'browser_click_payment',
};
