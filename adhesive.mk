#===============================================================================
#  adhesive.mk — CatalystOS 构建系统
#  "把催化剂粘合成化合物 (catalyst.elf)"
#===============================================================================
#  用法:
#    make              构建 catalyst.elf
#    make run          构建 + 跑 QEMU
#    make check        检查 ELF 头 / 段布局 / 符号
#    make doctor       环境自检 (工具链 / QEMU / 目录结构)
#    make why <file>   诊断某个源文件为什么没被编进去
#    make tree         打印源文件发现结果
#    make clean        清理
#    make V=1          显示完整命令 (默认静默)
#===============================================================================

TARGET   := aarch64-unknown-none
BUILD    := build
ELF      := $(BUILD)/catalyst.elf
BIN      := $(BUILD)/catalyst.bin
LINKER   := arch/aarch64/linker.ld

CC       := clang
LD       := ld.lld
OBJCOPY  := llvm-objcopy
OBJDUMP  := llvm-objdump
READELF  := llvm-readelf
NM       := llvm-nm
QEMU     := qemu-system-aarch64

#---- 颜色 (非 TTY 自动降级) ----
ifneq ($(MAKE_TERMOUT),)
  C_R  := \033[31m
  C_G  := \033[32m
  C_Y  := \033[33m
  C_B  := \033[34m
  C_M  := \033[35m
  C_D  := \033[90m
  C_0  := \033[0m
  BOLD := \033[1m
else
  C_R := ; C_G := ; C_Y := ; C_B := ; C_M := ; C_D := ; C_0 := ; BOLD :=
endif

#---- 静默模式: 默认只打标签, V=1 显示完整命令 ----
ifneq ($(V),1)
  Q := @
endif
#===============================================================================
#  1. 源文件发现
#===============================================================================
SRC_DIRS_C := kernel
SRC_DIRS_S := arch/aarch64
INC_DIRS   := include

SRCS_C := $(foreach d,$(SRC_DIRS_C),$(shell find $(d) -name '*.c' 2>/dev/null | sort))
SRCS_S := $(foreach d,$(SRC_DIRS_S),$(shell find $(d) -name '*.S' 2>/dev/null | sort))
SRCS   := $(SRCS_S) $(SRCS_C)
OBJS   := $(patsubst %,$(BUILD)/%.o,$(SRCS))
DEPS   := $(OBJS:.o=.d)

#---- 期望的入口符号必须存在 ----
EXPECT_ENTRY := _start
EXPECT_MAIN  := kernel_main
#===============================================================================
#  2. 源码树体检 — 在编译之前就把蠢错误拦下来
#===============================================================================
define CHECK_TREE
@printf "$(C_B)$(BOLD)▸ 扫描源文件$(C_0)\n"
@if [ -z "$(strip $(SRCS))" ]; then \
    printf "$(C_R)$(BOLD)  ✗ 一个源文件都没找到$(C_0)\n"; \
    printf "$(C_Y)    搜索目录: C=$(SRC_DIRS_C)  S=$(SRC_DIRS_S)$(C_0)\n"; \
    printf "$(C_Y)    检查:  1) 目录是否存在  2) 文件后缀是 .c / .S (大写 S!)$(C_0)\n"; \
    exit 1; \
fi
@printf "$(C_D)    AS: $(strip $(SRCS_S))$(C_0)\n"
@printf "$(C_D)    CC: $(strip $(SRCS_C))$(C_0)\n"
@printf "$(C_G)  ✓ 发现 $(words $(SRCS)) 个源文件 → $(words $(OBJS)) 个目标文件$(C_0)\n"
@if [ ! -f $(LINKER) ]; then \
    printf "$(C_R)$(BOLD)\n  ✗ 链接脚本缺失: $(LINKER)$(C_0)\n"; \
    printf "$(C_Y)    没有它, ld 会用默认脚本 → 入口地址落在 0x10000 之类$(C_0)\n"; \
    printf "$(C_Y)    后果: QEMU 跳进 0x40000000 什么都没有, 屏幕全黑无报错$(C_0)\n"; \
    exit 1; \
fi
@if [ ! -d $(INC_DIRS) ]; then \
    printf "$(C_Y)  ! 提示: $(INC_DIRS)/ 不存在, 头文件要放这儿并配 -I$(C_0)\n"; \
fi
endef
#===============================================================================
#  3. 编译/链接参数
#===============================================================================
CFLAGS := --target=$(TARGET) \
          -ffreestanding -nostdlib -fno-builtin \
          -Wall -Wextra -Werror \
          -Wshadow -Wstrict-prototypes -Wmissing-prototypes \
          -Wundef -Wcast-align -Wwrite-strings \
          -O2 -g \
          -I$(INC_DIRS) \
          -MMD -MP

ASFLAGS := --target=$(TARGET) -g
LDFLAGS := -T $(LINKER) --error-unresolved-symbols
QEMUFLAGS := -machine virt -cpu cortex-a72 -nographic -kernel
#===============================================================================
#  4. 构建规则
#===============================================================================
.PHONY: all
all: $(ELF)
	@printf "$(C_G)$(BOLD)✓ 化合物已合成: $(ELF)$(C_0)\n"
	@printf "$(C_D)  下一步: make check   (验尸: 看入口/段布局)$(C_0)\n"
	@printf "$(C_D)          make run     (点火: 丢进 QEMU)$(C_0)\n"

$(ELF): $(OBJS) $(LINKER)
	@printf "$(C_B)[粘合]$(C_0) $(words $(OBJS)) 个目标 → $(C_B)$@$(C_0)\n"
	$(Q)$(LD) $(LDFLAGS) -o $@ $(filter %.o,$^) 2>$(BUILD)/.ld.log; \
	if [ -s $(BUILD)/.ld.log ]; then \
	    printf "$(C_R)$(BOLD)  ✗ 链接失败, 完整报错:$(C_0)\n"; \
	    sed 's/^/    /' $(BUILD)/.ld.log; \
	    printf "$(C_Y)  诊断提示:$(C_0)\n"; \
	    if grep -qi 'undefined symbol' $(BUILD)/.ld.log; then \
	        sym=$$(grep -io "undefined symbol: *[A-Za-z0-9_]*" $(BUILD)/.ld.log | head -1 | awk '{print $$NF}'); \
	        printf "$(C_Y)    · 未定义符号 '$$sym' → 要么拼错, 要么实现文件没被 find 扫到$(C_0)\n"; \
	        printf "$(C_Y)      试: make why <可能的文件名>$(C_0)\n"; \
	    fi; \
	    if grep -qi 'not aligned\|alignment' $(BUILD)/.ld.log; then \
	        printf "$(C_Y)    · 段对齐问题 → 检查 linker.ld 里 .text.boot 是否排第一$(C_0)\n"; \
	    fi; \
	    if grep -qi 'address.*overflow\|region.*full' $(BUILD)/.ld.log; then \
	        printf "$(C_Y)    · 镜像超出内存区域 → linker.ld 的 . 起点或 RAM 大小不对$(C_0)\n"; \
	    fi; \
	    rm -f $@; \
	    exit 1; \
	fi
	@printf "$(C_D)        入口: 0x$$(printf '%08x' $$(($(shell printf '%s' "0x40000000"))))$(C_0)\n"

$(BUILD)/%.c.o: %.c
	@mkdir -p $(dir $@)
	@printf "$(C_M)[CC]$(C_0)   $< → $(C_D)$@$(C_0)"
	$(Q)$(CC) $(CFLAGS) -c -o $@ $< 2>$(BUILD)/.cc.$$$$.log; \
	if [ -s $(BUILD)/.cc.$$$$.log ]; then \
	    printf "  $(C_R)✗$(C_0)\n"; \
	    sed 's/^/    /' $(BUILD)/.cc.$$$$.log; \
	    printf "$(C_Y)  诊断:$(C_0)\n"; \
	    if grep -qi 'implicit declaration' $(BUILD)/.cc.$$$$.log; then \
	        printf "$(C_Y)    · 函数没声明就被调用 → 在 .h 里补原型, #include 它$(C_0)\n"; \
	        printf "$(C_Y)      (-Werror 已开启, 这条本该编不过)$(C_0)\n"; \
	    fi; \
	    if grep -qi 'multiple definition\|duplicate symbol' $(BUILD)/.cc.$$$$.log; then \
	        printf "$(C_Y)    · 重复定义 → .h 里写了定义而非声明, 忘了加 include guard?$(C_0)\n"; \
	    fi; \
	    if grep -qi 'unknown type name\|undeclared identifier' $(BUILD)/.cc.$$$$.log; then \
	        printf "$(C_Y)    · 类型/标识符未见 → 漏 include 头文件, 或 -I 路径不对$(C_0)\n"; \
	    fi; \
	    if grep -qi 'incompatible pointer' $(BUILD)/.cc.$$$$.log; then \
	        printf "$(C_Y)    · 指针类型不符 → 回想第一课 '0' vs \"0\" 那个坑$(C_0)\n"; \
	    fi; \
	    rm -f $(BUILD)/.cc.$$$$.log; \
	    exit 1; \
	fi
	@printf "  $(C_G)✓$(C_0)\n"
	@rm -f $(BUILD)/.cc.*.log

$(BUILD)/%.S.o: %.S
	@mkdir -p $(dir $@)
	@printf "$(C_M)[AS]$(C_0)   $< → $(C_D)$@$(C_0)"
	$(Q)$(CC) $(ASFLAGS) -c -o $@ $< 2>$(BUILD)/.as.$$$$.log; \
	if [ -s $(BUILD)/.as.$$$$.log ]; then \
	    printf "  $(C_R)✗$(C_0)\n"; \
	    sed 's/^/    /' $(BUILD)/.as.$$$$.log; \
	    printf "$(C_Y)  诊断:$(C_0)\n"; \
	    if grep -qi 'unknown mnemonic\|unrecognized instruction' $(BUILD)/.as.$$$$.log; then \
	        printf "$(C_Y)    · 指令拼错 → 注意 .global(有小数点) / mrs 的方向$(C_0)\n"; \
	    fi; \
	    if grep -qi 'expecting\| operand' $(BUILD)/.as.$$$$.log; then \
	        printf "$(C_Y)    · 操作数语法 → 逗号分隔别省: ldr x0, =0x8000$(C_0)\n"; \
	        printf "$(C_Y)      立即数非法? ARM64 mov 只吃 16 位, 常数太大改用 ldr =...$(C_0)\n"; \
	    fi; \
	    rm -f $(BUILD)/.as.$$$$.log; \
	    exit 1; \
	fi
	@printf "  $(C_G)✓$(C_0)\n"
	@rm -f $(BUILD)/.as.*.log
#===============================================================================
#  5. 诊断命令
#===============================================================================
.PHONY: doctor
doctor:
	@printf "$(C_B)$(BOLD)▸ adhesive 环境自检$(C_0)\n"
	@for t in $(CC) $(LD) $(OBJCOPY) $(OBJDUMP) $(READELF) $(QEMU); do \
	    if command -v $$t >/dev/null 2>&1; then \
	        printf "$(C_G)  ✓ %-22s$(C_0) $(C_D)$$($$t --version 2>&1 | head -1)$(C_0)\n" $$t; \
	    else \
	        printf "$(C_R)  ✗ %-22s$(C_0) 未找到 → pkg install <对应包>\n" $$t; \
	        case $$t in \
	            ld.lld|llvm-*) echo "      pkg install lld" ;; \
	            clang)         echo "      pkg install clang" ;; \
	            qemu-system-aarch64) echo "      pkg install x11-repo && pkg install qemu-system-aarch64" ;; \
	        esac; \
	    fi; \
	done
	@printf "$(C_B)▸ 三符 triple 验证$(C_0)\n"
	@printf 'int x;\n' > $(BUILD)/.probe.c 2>/dev/null || mkdir -p $(BUILD) && printf 'int x;\n' > $(BUILD)/.probe.c; \
	if $(CC) --target=$(TARGET) -ffreestanding -c -o $(BUILD)/.probe.o $(BUILD)/.probe.c 2>/dev/null; then \
	    printf "$(C_G)  ✓ --target=$(TARGET) 可用$(C_0)\n"; \
	else \
	    printf "$(C_R)  ✗ --target=$(TARGET) 编译失败$(C_0)\n"; \
	fi
	@printf "$(C_B)▸ 项目结构$(C_0)\n"
	@for d in $(SRC_DIRS_C) $(SRC_DIRS_S) $(INC_DIRS); do \
	    if [ -d $$d ]; then printf "$(C_G)  ✓ %s/$(C_0)\n" $$d; \
	    else printf "$(C_Y)  ! %s/ 不存在$(C_0)\n" $$d; fi; \
	done
	@test -f $(LINKER) && printf "$(C_G)  ✓ %s$(C_0)\n" $(LINKER) \
	                   || printf "$(C_R)  ✗ %s 缺失$(C_0)\n" $(LINKER)
	@printf "$(C_B)▸ 机器核心数 $(C_D)(可 make -jN 加速)$(C_0)\n"
	@printf "  $(shell nproc 2>/dev/null || echo '?') 核\n"

#---- 诊断: 为什么我的文件没被编进来?
.PHONY: why
why:
	@printf "$(C_B)$(BOLD)▸ adhesive 源码发现诊断$(C_0)\n"
	@printf "$(C_D)  搜索目录 C: $(SRC_DIRS_C)$(C_0)\n"
	@printf "$(C_D)  搜索目录 S: $(SRC_DIRS_S)$(C_0)\n"
	@printf "$(C_D)  已发现 $(words $(SRCS)) 个:$(C_0)\n"
	@$(foreach s,$(SRCS),printf "    $(C_G)✓$(C_0) %s\n" $(s);)
	@echo
	@printf "$(C_Y)  常见原因:$(C_0)\n"
	@printf "$(C_Y)    · 文件在 kernel/ 之外 → 加到 SRC_DIRS_C$(C_0)\n"
	@printf "$(C_Y)    · 后缀是 .s 小写   → 汇编文件必须 .S 大写 (要过 cpp)$(C_0)\n"
	@printf "$(C_Y)    · 文件后缀 .asm/.inc → 不认, 改 .S$(C_0)\n"
	@echo
	@printf "$(C_D)  试: touch <你的文件> && make tree$(C_0)\n"

.PHONY: tree
tree:
	@printf "$(C_B)$(BOLD)▸ 源文件树 → 目标文件映射$(C_0)\n"
	@$(foreach o,$(OBJS),printf "  %s  →  $(C_M)%s$(C_0)\n" $(patsubst $(BUILD)/%.o,%,$(o)) $(o);)

.PHONY: check
check: $(ELF)
	@printf "$(C_B)$(BOLD)▸ 验尸报告$(C_0)\n"
	@entry=$$($(READELF) -h $(ELF) | grep -i 'Entry point' | awk '{print $$NF}'); \
	 printf "  入口地址: $(C_B)$$entry$(C_0)\n"; \
	 case $$entry in \
	     0000000040000000) printf "  $(C_G)✓ 正确 — 与 linker.ld 的 . = 0x40000000 一致$(C_0)\n";; \
	     *) printf "  $(C_R)✗ 不对! 期望 0x40000000$(C_0)\n"; \
	        printf "    $(C_Y)→ linker.ld 第一行 SEARCH/ENTRY 或 . 定位有问题$(C_0)\n"; \
	        printf "    $(C_Y)→ 若是 0x10000 之类, 说明 -T $(LINKER) 没生效$(C_0)\n";; \
	 esac
	@printf "\n  $(C_D)段布局:$(C_0)\n"
	@$(READELF) -S $(ELF) | grep -E '\.text|\.rodata|\.data|\.bss' | sed 's/^/    /'
	@printf "\n  $(C_D)前 8 个符号 (按地址):$(C_0)\n"
	@$(NM) -n $(ELF) | head -8 | sed 's/^/    /'
	@printf "\n  $(C_D)镜像大小: $(C_B)%s$(C_0) 字节\n" $$(stat -c %s $(ELF))

.PHONY: run
run: $(ELF)
	@printf "$(C_G)$(BOLD)▸ 点火 → QEMU (退出: Ctrl+A 松手 再按 X)$(C_0)\n"
	@printf "$(C_D)────────────────────────────────────────────────$(C_0)\n"
	$(QEMU) $(QEMUFLAGS) $(ELF); \
	rc=$$?; \
	printf "$(C_D)────────────────────────────────────────────────$(C_0)\n"; \
	if [ $$rc -ne 0 ]; then \
	    printf "$(C_R)✗ QEMU 退出码 $$rc$(C_0)\n"; \
	    printf "$(C_Y)  · 137 = 被 SIGKILL (Termux 内存压力?)$(C_0)\n"; \
	    printf "$(C_Y)  · 屏幕全黑 → make check 先验入口地址$(C_0)\n"; \
	    printf "$(C_Y)  · 全黑且入口对 → boot.S 的 _start 没跳到 kernel_main$(C_0)\n"; \
	    printf "$(C_Y)  · 乱码 → UART 状态位没查 (FR_TXFF), 或波特率未配$(C_0)\n"; \
	fi

.PHONY: bin
bin: $(ELF)
	$(OBJCOPY) -O binary $< $(BIN)
	@printf "$(C_G)✓ $(BIN) ($(C_D)%s 字节$(C_0))$(C_0)\n" $$(stat -c %s $(BIN))

.PHONY: clean
clean:
	@rm -rf $(BUILD)
	@printf "$(C_G)✓ 已清理 $(BUILD)/$(C_0)\n"

.PHONY: help
help:
	@printf "$(C_B)$(BOLD)adhesive — CatalystOS 构建粘合剂$(C_0)\n"
	@printf "  $(C_M)make$(C_0)           构建 catalyst.elf\n"
	@printf "  $(C_M)make doctor$(C_0)    环境自检 (工具链/triple/目录)\n"
	@printf "  $(C_M)make tree$(C_0)      打印源文件→目标文件映射\n"
	@printf "  $(C_M)make why$(C_0)       诊断某个文件为什么没被编进来\n"
	@printf "  $(C_M)make check$(C_0)     验尸: 入口地址/段布局/符号\n"
	@printf "  $(C_M)make run$(C_0)       构建 + 跑 QEMU\n"
	@printf "  $(C_M)make V=1$(C_0)       显示完整命令 (调试 Makefile 自身)\n"
	@printf "  $(C_M)make -jN$(C_0)       N 线程并行\n"

#---- 依赖跟踪 ----
-include $(DEPS)
