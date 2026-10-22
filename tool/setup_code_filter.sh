#!/usr/bin/env bash
# 为子模块安装 workspace filter：checkout 时把 pubspec.yaml 里被注释的
# `# resolution: workspace` 恢复为生效状态，`git add` 时再自动注释掉，
# 使本地开发走 workspace、独立 clone 仍按 git 依赖解析。
#
# 用法：
#   bash tool/setup_code_filter.sh                  # 处理 conatus_code（未拉取则跳过）
#   bash tool/setup_code_filter.sh packages/conatus_code # 只处理指定子模块
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

setup_one() {
  local pkg="$1"
  if [ ! -f "$pkg/pubspec.yaml" ]; then
    echo "未找到 $pkg/pubspec.yaml（未拉取子模块？）" >&2
    return 1
  fi

  git -C "$pkg" config filter.conatus-workspace.clean \
    "sed 's/^resolution: workspace\$/# resolution: workspace/'"
  git -C "$pkg" config filter.conatus-workspace.smudge \
    "sed 's/^# resolution: workspace\$/resolution: workspace/'"

  # 若工作区仍是被注释的状态，就地恢复为生效状态（不覆盖其它未提交改动）。
  if grep -q '^# resolution: workspace$' "$pkg/pubspec.yaml"; then
    sed -i.bak 's/^# resolution: workspace$/resolution: workspace/' "$pkg/pubspec.yaml"
    rm -f "$pkg/pubspec.yaml.bak"
  fi

  # workspace 禁止 override 成员包，用一个本地 overrides 文件清空 pubspec.yaml 的
  # dependency_overrides；独立 clone 没有该文件，override 照常生效。
  local overrides="$pkg/pubspec_overrides.yaml"
  if [ ! -f "$overrides" ]; then
    printf '%s\n' \
      '# 由 tool/setup_code_filter.sh 生成，勿提交：清空 pubspec.yaml 的' \
      '# dependency_overrides —— workspace 内禁止 override 成员包。' \
      'dependency_overrides: {}' > "$overrides"
  fi

  echo "已安装 conatus-workspace filter，$pkg 处于 workspace 态"
}

if [ $# -gt 0 ]; then
  setup_one "$root/$1"
  exit $?
fi

for target in packages/conatus_code; do
  setup_one "$root/$target" || echo "跳过 $target"
done
