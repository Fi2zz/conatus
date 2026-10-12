/// op 流编译管道：把模型流式产出中的 ops 代码块编译为补丁操作。
///
/// 协议：模型在 ```` ```ops ```` 围栏块内输出一个 JSON 数组，元素是
/// `PatchOp` 的 JSON 形态（`kind` 判别）。op 文本内不得出现 ``` 序列。
library;

import 'dart:convert';

import 'patch.dart';

/// ops 代码块的开围栏。
const String kOpsFence = '```ops';

const String _kFenceClose = '```';

/// 从完整 [text] 编译全部 ops 块；无 ops 块返回空列表。
///
/// 块体不是 JSON 数组时抛 [FormatException]；未知 op `kind` 抛
/// [ArgumentError]。
List<PatchOp> compileOpsBlock(String text) => OpStreamCompiler().feed(text);

/// 流式编译器：逐段喂入模型产出，每闭合一个 ops 块产出其 ops。
///
/// 围栏可跨段拆分（缓冲区累积识别）；未闭合的块留待下一段。
class OpStreamCompiler {
  final StringBuffer _buf = StringBuffer();
  int _consumed = 0;

  /// 喂入一段流式文本，返回本轮新编译出的 ops（无则空列表）。
  List<PatchOp> feed(String chunk) {
    _buf.write(chunk);
    final String text = _buf.toString();
    final List<PatchOp> out = <PatchOp>[];
    int open = text.indexOf(kOpsFence, _consumed);
    while (open >= 0) {
      final int bodyStart = open + kOpsFence.length;
      final int close = text.indexOf(_kFenceClose, bodyStart);
      if (close < 0) break;
      out.addAll(_parseOps(text.substring(bodyStart, close)));
      _consumed = close + _kFenceClose.length;
      open = text.indexOf(kOpsFence, _consumed);
    }
    return out;
  }
}

List<PatchOp> _parseOps(String body) {
  final Object? decoded = jsonDecode(body.trim());
  if (decoded is! List) {
    throw const FormatException('ops 块须为 JSON 数组');
  }
  return <PatchOp>[
    for (final Object? op in decoded)
      patchOpFromJson(Map<String, Object?>.from(op! as Map)),
  ];
}
