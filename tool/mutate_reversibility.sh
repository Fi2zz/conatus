#!/usr/bin/env bash
#
# 变异测试：把真实 bug 逐个注入「可逆效应」的实现**与验证夹具自身**，确认测试套件
# 能杀掉每一个。夹具上的两个变异体是元检查——它们证明负向对照不是摆设。
#
# fail-closed 规则（任一条成立即硬失败，绝不算通过）：
#   * 变异没改到文件（模式没匹配上）：变异体根本没跑
#   * 变异体编译不过：失败无法归因于某条测试
#   * 还原后与备份不是逐字节一致
#   * 任何变异体存活：验证有盲区
#
# 用法：bash tool/mutate_reversibility.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PKG="packages/conatus_core"
SCOPE="$PKG/lib/src/effect_scope.dart"
CONTEXT="$PKG/lib/src/context.dart"
HARNESS="$PKG/test/reversibility_harness.dart"
WORLD="$PKG/test/reversibility_world.dart"

BACKUP="$(mktemp -d)"
TARGETS=("$SCOPE" "$CONTEXT" "$HARNESS" "$WORLD")
for file in "${TARGETS[@]}"; do
  cp "$file" "$BACKUP/$(basename "$file")"
done

restore_file() { cp "$BACKUP/$(basename "$1")" "$1"; }

restore_all() {
  for file in "${TARGETS[@]}"; do
    cp "$BACKUP/$(basename "$file")" "$file" 2>/dev/null || true
  done
}
trap restore_all EXIT INT TERM

# 标签|文件|原文|替换
MUTANTS=(
  "LIFO 改成顺序撤销|$SCOPE|_disposers.removeLast();|_disposers.removeAt(0);"
  "迟到登记不再立即执行|$SCOPE|if (_disposed) {|if (!_disposed) {"
  "撤销异常被静默吞掉|$SCOPE|errors.add(error);|// swallowed"
  "capture 不再登记 Disposer|$SCOPE|track(result);|// not tracked"
  "inject 不登记取消（调用点）|$CONTEXT|_scope.track(canceller);|// not tracked"
  "[元] 夹具不再构造漏登记|$HARNESS|if (spec.mode == PluginMode.unregistered) return;|// disabled"
  "[元] 投影不再观察定时器|$WORLD|timers.where((Timer t) => t.isActive).length|0"
)

killed=0
survived=0
hard_failed=0

printf '%-32s %s\n' "变异体" "结果"
printf '%-32s %s\n' "--------------------------------" "----------------------------------"

for entry in "${MUTANTS[@]}"; do
  IFS='|' read -r label file old new <<<"$entry"
  before="$(shasum -a 256 "$file" | cut -d' ' -f1)"
  OLD="$old" NEW="$new" perl -0pi -e 's/\Q$ENV{OLD}\E/$ENV{NEW}/' "$file"
  after="$(shasum -a 256 "$file" | cut -d' ' -f1)"

  if [ "$before" = "$after" ]; then
    printf '%-32s %s\n' "$label" "硬失败：变异未生效（模式没匹配上）"
    hard_failed=$((hard_failed + 1))
    restore_file "$file"
    continue
  fi

  if ! (cd "$PKG" && dart analyze >/dev/null 2>&1); then
    printf '%-32s %s\n' "$label" "硬失败：变异体编译不过"
    hard_failed=$((hard_failed + 1))
    restore_file "$file"
    continue
  fi

  output="$(cd "$PKG" && dart test -r compact 2>&1)"
  status=$?
  restore_file "$file"

  if ! cmp -s "$BACKUP/$(basename "$file")" "$file"; then
    printf '%-32s %s\n' "$label" "硬失败：还原后与备份不一致"
    hard_failed=$((hard_failed + 1))
    continue
  fi

  if [ $status -ne 0 ]; then
    failures="$(printf '%s' "$output" | grep -c '\[E\]')"
    printf '%-32s %s\n' "$label" "已杀死（$failures 条测试失败）"
    killed=$((killed + 1))
  else
    printf '%-32s %s\n' "$label" "存活 → 验证存在盲区"
    survived=$((survived + 1))
  fi
done

printf '\n合计：杀死 %d，存活 %d，硬失败 %d（共 %d 个变异体）\n' \
  "$killed" "$survived" "$hard_failed" "${#MUTANTS[@]}"

if [ "$survived" -gt 0 ] || [ "$hard_failed" -gt 0 ]; then
  echo "结论：未通过"
  exit 1
fi
echo "结论：全部变异体被杀死，检查器有效"
exit 0
