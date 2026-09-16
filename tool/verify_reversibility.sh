#!/usr/bin/env bash
#
# 可逆效应验证的一键入口：按顺序跑完所有层。
#
# 层与「能抓到什么」的对应：
#   静态检查   → 类型/lint 类问题
#   单元测试   → 行为回归
#   随机顺序   → 用例间隐式依赖（flaky 会让所有数字失效）
#   行覆盖率   → 未被执行的机制分支
#   变异测试   → 测试是否真的在断言（本脚本的核心）
#
# fail-closed：任一层的工具缺失、崩溃或非零退出都计为未通过，绝不静默跳过。
#
# 用法：bash tool/verify_reversibility.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PKG="packages/conatus_core"
fail=0

step() { printf '\n=== %s ===\n' "$1"; }

step "静态检查（全仓）"
dart analyze --fatal-infos || fail=1

step "单元测试（conatus_core）"
(cd "$PKG" && dart test -r failures-only) || fail=1

step "随机顺序（3 个种子）"
for seed in 1 42 12345; do
  printf 'seed=%-6s ' "$seed"
  (cd "$PKG" && dart test -r failures-only --test-randomize-ordering-seed="$seed" | tail -1) ||
    fail=1
done

step "行覆盖率（机制自身）"
rm -rf "$PKG/coverage"
if (cd "$PKG" && dart test --coverage=coverage -r failures-only >/dev/null 2>&1) &&
  (cd "$PKG" && dart run coverage:format_coverage --lcov \
    --in=coverage --out=coverage/lcov.info --report-on=lib >/dev/null 2>&1) &&
  [ -f "$PKG/coverage/lcov.info" ]; then
  awk '/^SF:/{sf=$0} /^LF:/{lf=$0} /^LH:/{lh=$0;
       if (sf ~ /effect_scope\.dart|context\.dart/) { sub(/^SF:/, "", sf); print "  " sf " → " lh " / " lf }}' \
    "$PKG/coverage/lcov.info"
else
  echo "  跳过：coverage 工具不可用 → 按 fail-closed 计为未通过"
  fail=1
fi
rm -rf "$PKG/coverage"

step "变异测试"
bash tool/mutate_reversibility.sh || fail=1

printf '\n'
if [ "$fail" -ne 0 ]; then
  echo "总判定：未通过"
  exit 1
fi
echo "总判定：通过"
