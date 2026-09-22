#!/usr/bin/env bash
# 为 conatus_code 子模块安装 workspace filter：checkout 时把 pubspec.yaml 里被
# 注释的 `# resolution: workspace` 恢复为生效状态，`git add` 时再自动注释掉，
# 使本地开发走 workspace、独立 clone 仍按 git 依赖解析。
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
code="$root/packages/conatus_code"

if [ ! -f "$code/pubspec.yaml" ]; then
  echo "未找到 $code/pubspec.yaml，请先执行 git submodule update --init" >&2
  exit 1
fi

git -C "$code" config filter.conatus-workspace.clean \
  "sed 's/^resolution: workspace\$/# resolution: workspace/'"
git -C "$code" config filter.conatus-workspace.smudge \
  "sed 's/^# resolution: workspace\$/resolution: workspace/'"

# 若工作区仍是被注释的状态，就地恢复为生效状态（不覆盖其它未提交改动）。
if grep -q '^# resolution: workspace$' "$code/pubspec.yaml"; then
  sed -i.bak 's/^# resolution: workspace$/resolution: workspace/' "$code/pubspec.yaml"
  rm -f "$code/pubspec.yaml.bak"
fi

echo "已安装 conatus-workspace filter，$code/pubspec.yaml 处于 workspace 态"
