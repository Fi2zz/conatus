/// 游标三操作：预览 / 分叉 / 截断（区间 traveling 的数据层）。
library;

import 'fold.dart';
import 'patch_log.dart';

/// 预览：只读地查看 [upto]（不含）时刻的文档状态，不动序列。
DocumentState previewAt(PatchLog log, int upto) =>
    foldPatches(log.effective(upto: upto));

/// 分叉：从 [upto]（不含）起一条新故事线，旧线保留。
PatchLog forkLog(PatchLog log, int upto) => log.forkAt(upto);

/// 截断：作废 [index] 之后的全部补丁（序列本身只追加，不删）。
void truncateLog(PatchLog log, int index) => log.truncateAfter(index);
