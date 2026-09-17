#!/usr/bin/env bash
#
# 统一版本管理：伞包与各模块包共用同一个版本号，包间的版本约束也指向它。
#
#   bash tool/version.sh            # 检查（缺省）：版本一致、约束指向它
#   bash tool/version.sh 0.16.0     # 把所有包升到 0.16.0，并同步包间约束
#
# 为什么需要它：pub workspace 会在解析时校验成员之间的版本约束，任何一处没跟着改，
# `dart pub get` 会直接失败（`^0.15.0` 在 0.x 下等价于 `>=0.15.0 <0.16.0`）。
#
# fail-closed：参数非法、或改完检查不过，都非零退出，并把 pubspec 还原成原样。
#
# 用法：bash tool/version.sh [新版本]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PUBSPECS=(pubspec.yaml packages/*/pubspec.yaml)
DEP_LINE='^  conatus_[a-z_]*: '

fail() {
  printf '%s\n' "$1" >&2
  return 1
}

check() {
  local versions count version
  versions="$(grep -h '^version: ' "${PUBSPECS[@]}" | awk '{print $2}' | sort -u)"
  count="$(printf '%s\n' "$versions" | grep -c .)"
  if [ "$count" -ne 1 ]; then
    grep -H '^version: ' "${PUBSPECS[@]}" >&2
    fail "版本号不一致：期望 1 种，实际 $count 种（见上）"
    return 1
  fi
  version="$versions"

  local stray
  stray="$(grep -H "$DEP_LINE" "${PUBSPECS[@]}" | grep -v "conatus_[a-z_]*: \\^$version\$" || true)"
  if [ -n "$stray" ]; then
    printf '%s\n' "$stray" >&2
    fail "以上依赖约束没有指向 ${version}（新约束形式见上）"
    return 1
  fi

  local deps
  deps="$(grep -h "$DEP_LINE" "${PUBSPECS[@]}" | grep -c .)"
  printf '版本一致：%s（%s 个包，%s 条包间约束）\n' \
    "$version" "${#PUBSPECS[@]}" "$deps"
}

backup() {
  local dir="$1"
  for file in "${PUBSPECS[@]}"; do
    cp "$file" "$dir/$(printf '%s' "$file" | tr '/' '-')"
  done
}

restore() {
  local dir="$1"
  for file in "${PUBSPECS[@]}"; do
    cp "$dir/$(printf '%s' "$file" | tr '/' '-')" "$file"
  done
}

bump() {
  local next="$1"
  if ! printf '%s' "$next" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    fail "版本号格式不合法：${next}（期望 x.y.z）"
    return 1
  fi

  local dir
  dir="$(mktemp -d)"
  backup "$dir"

  for file in "${PUBSPECS[@]}"; do
    perl -pi -e "s/^version: .*/version: $next/" "$file"
    perl -pi -e "s/^  (conatus_[a-z_]*: )\\^[0-9.]+$/  \${1}^$next/" "$file"
  done

  if ! check >/dev/null; then
    restore "$dir"
    rm -rf "$dir"
    fail "升版后检查未通过，pubspec 已还原；详见 bash tool/version.sh"
    return 1
  fi
  rm -rf "$dir"

  check
  printf '%s\n' "下一步：按依赖顺序发布 —— core、foundation、compaction、credentials、llm、mcp、" \
    "schedule、search、skill、asr、tts、agent、tasks、tui，最后是仓库根的 conatus"
}

case "${1:-}" in
  "")
    check
    ;;
  -h | --help)
    sed -n '3,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    ;;
  *)
    bump "$1"
    ;;
esac
