#!/usr/bin/env bash
#
# 版本冻结校验（原「统一升版」脚本，git 源分发后退役升版能力）。
#
#   bash tool/version.sh    # 检查：版本冻结在位、无残留的托管版本约束
#
# 背景：全部 23 个包 `publish_to: none`，不再发布 pub.dev；版本演进由 git tag
# 承载（见 README 安装指引与 CHANGELOG）。各 pubspec 的 `version:` 冻结为同一
# 历史值，仅作快照标识；包间依赖一律为 path，不再有 `^x.y.z` 约束需要同步。
#
# 检查内容（fail-closed，任一不过非零退出）：
#   1. 根包与 22 个模块包的 version 完全一致（子模块 conatus_code 独立版本，排除）；
#   2. 全仓（除子模块）不存在 `conatus_*: ^...` 形式的包间版本约束。
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PUBSPECS=(pubspec.yaml)
for f in packages/*/pubspec.yaml; do
  case "$f" in *conatus_code*) continue;; esac # 子模块：独立仓库独立版本
  PUBSPECS+=("$f")
done

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

case "${1:-}" in
  "") ;;
  -h | --help)
    sed -n '3,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    fail "升版能力已退役：版本演进由 git tag 承载（如 v0.17.0），本脚本只做冻结校验"
    ;;
esac

versions="$(grep -h '^version: ' "${PUBSPECS[@]}" | awk '{print $2}' | sort -u)"
count="$(printf '%s\n' "$versions" | grep -c .)"
if [ "$count" -ne 1 ]; then
  grep -H '^version: ' "${PUBSPECS[@]}" >&2
  fail "冻结版本不一致：期望 1 种，实际 $count 种（见上）"
fi

stray="$(grep -H '^  conatus_[a-z_]*: \^' "${PUBSPECS[@]}" || true)"
if [ -n "$stray" ]; then
  printf '%s\n' "$stray" >&2
  fail "存在残留的托管版本约束（见上）：包间依赖一律使用 path"
fi

printf '版本冻结校验通过：%s（%s 个包，包间均为 path 依赖；子模块 conatus_code 独立版本已排除）\n' \
  "$versions" "${#PUBSPECS[@]}"
