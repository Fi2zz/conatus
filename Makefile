# conatus_code（子模块）二进制打包入口，在仓库根执行。常用：
#   make            # 编译产出 packages/conatus_code/dist/nava
#   make install    # 编译并软链 ~/bin/nava（已在 PATH）
#   make clean      # 删除 packages/conatus_code/dist
#
# 产物路径可用 OUTPUT 覆盖：make build OUTPUT=/tmp/nava

OUTPUT ?= packages/conatus_code/dist/nava
CODE_DIR := packages/conatus_code
NAVA_LINK := $(HOME)/bin/nava

.PHONY: all build install clean

all: build

build:
	bash $(CODE_DIR)/tool/build_binary.sh $(OUTPUT)

install: build
	ln -sf "$(abspath $(OUTPUT))" "$(NAVA_LINK)"
	@echo "已链接：$(NAVA_LINK) -> $(abspath $(OUTPUT))"

clean:
	rm -rf $(CODE_DIR)/dist
