#===============================================================================
#  adhesive.mk v3.0 — CatalystOS 构建粘合剂  [1/4 骨架·工具链·输出]
#  ⚠ 缩进即语法: ifeq/endif 内必须缩进, 顶格会被当顶层语句执行
#    改完先跑: make -n doctor
#===============================================================================
ifndef ADHESIVE_INCLUDED
ADHESIVE_INCLUDED := 1
ADHESIVE_VERSION  := 3.0

#---- 1. 工具链 ----
TARGET   ?= aarch64-unknown-none
CROSS    ?=
CC       := $(CROSS)clang
LD       := $(CROSS)ld.lld
OBJCOPY  := $(CROSS)llvm-objcopy
OBJDUMP  := $(CROSS)llvm-objdump
READELF  := $(CROSS)llvm-readelf
NM       := $(CROSS)llvm-nm
SIZE     := $(CROSS)llvm-size
QEMU     ?= qemu-system-aarch64
TOOLS    := $(CC) $(LD) $(OBJCOPY) $(OBJDUMP) $(READELF) $(NM)

# 期望存在的符号 (doctor 扫描用, 按课程进度加)
EXPECT_SYMS ?= _start kernel_main

#---- 2. 目录与产物 ----
BUILD    ?= build
ELF      := $(BUILD)/catalyst.elf
BIN      := $(BUILD)/catalyst.bin
MAP      := $(BUILD)/catalyst.map
LINKER   ?= arch/aarch64/linker.ld
SRC_DIRS_C ?= kernel
SRC_DIRS_S ?= arch/aarch64
INC_DIRS   ?= include

#---- 3. Verbose + 颜色 ----
ifeq ($(V),1)
Q :=
VECHO := @true
else
Q := @
VECHO := @echo
endif

IS_TTY := $(shell [ -t 1 ] && echo yes)

ifeq ($(NO_COLOR),)
ifeq ($(IS_TTY),yes)
C_R  := \033[31m
C_G  := \033[32m
C_Y  := \033[33m
C_B  := \033[34m
C_M  := \033[35m
C_C  := \033[36m
C_D  := \033[90m
C_0  := \033[0m
BOLD := \033[1m
endif
endif

act_CC   = $(VECHO) "$(C_G)$(BOLD)  CC     $(C_0)$(patsubst $(BUILD)/%,%,$@)"
act_AS   = $(VECHO) "$(C_M)$(BOLD)  AS     $(C_0)$(patsubst $(BUILD)/%,%,$@)"
act_LD   = $(VECHO) "$(C_B)$(BOLD)  LD     $(C_0)$@"
act_GEN  = $(VECHO) "$(C_C)$(BOLD)  GEN    $(C_0)$@"
act_QEMU = $(VECHO) "$(C_Y)$(BOLD) QEMU    $(C_0)"
BAR := ────────────────────────────────────────────────────

#---- 4. 源文件自动发现 ----
SRCS_C := $(foreach d,$(SRC_DIRS_C),$(shell find $(d) -name '*.c' 2>/dev/null | sort))
SRCS_S := $(foreach d,$(SRC_DIRS_S),$(shell find $(d) -name '*.S' 2>/dev/null | sort))
SRCS   := $(SRCS_S) $(SRCS_C)
OBJS   := $(patsubst %,$(BUILD)/%.o,$(SRCS))
DEPS   := $(OBJS:.o=.d)
EXCLUDE ?=
OBJS   := $(filter-out $(patsubst %,$(BUILD)/%.o,$(EXCLUDE)),$(OBJS))

#---- 5. 编译参数 ----
WARN := -Wall -Wextra -Werror \
        -Wshadow -Wstrict-prototypes -Wmissing-prototypes \
        -Wmissing-declarations -Wredundant-decls \
        -Wundef -Wcast-align -Wwrite-strings -Wdouble-promotion \
        -Wconstant-logical-operand -Wtautological-constant-compare \
        -Wmisleading-indentation -Wimplicit-fallthrough \
        -Wpointer-arith -Wnested-externs -Wbad-function-cast \
        -Wno-unused-command-line-argument
CFLAGS_BASE := --target=$(TARGET) \
               -ffreestanding -nostdlib -fno-builtin \
               -O2 -g -I$(INC_DIRS) $(WARN)
CFLAGS    ?= $(CFLAGS_BASE)
ASFLAGS   ?= --target=$(TARGET) -g -I$(INC_DIRS)
LDFLAGS   ?= -T $(LINKER) --error-unresolved-symbols -Map=$(MAP)
QEMUFLAGS ?= -machine virt -cpu cortex-a72 -nographic -kernel

#===============================================================================
#  6. 构建规则
#===============================================================================
.PHONY: all
all: $(ELF)
	@printf "$(C_G)$(BOLD)✓ catalyst.elf 已合成$(C_0)  $(C_D)(%s 字节)$(C_0)\n" "$$(stat -c %s $(ELF))"
	@printf "$(C_D)  doctor → 体检   check → 验尸   run → 点火$(C_0)\n"

#---- L4 链接诊断 ----
$(ELF): $(OBJS) $(LINKER)
	$(call act_LD)
	$(Q)rm -f $@
	$(Q)$(LD) $(LDFLAGS) -o $@ $(filter %.o,$^) >$(BUILD)/.ld.log 2>&1; \
	if [ -s $(BUILD)/.ld.log ]; then \
	    printf "$(C_R)$(BOLD)  ✗ 链接失败$(C_0)\n"; sed 's/^/    /' $(BUILD)/.ld.log; \
	    printf "$(C_Y)  诊断:$(C_0)\n"; \
	    if grep -qiE 'undefined symbol|undefined reference|unresolved' $(BUILD)/.ld.log; then \
	        s=$$(grep -oE "(undefined symbol|undefined reference to)[^:]*[: ]*[A-Za-z_][A-Za-z0-9_]*" $(BUILD)/.ld.log | head -1 | awk '{print $$NF}'); \
	        printf "$(C_Y)    · 未解析符号 '%s'$(C_0)\n" "$$s"; \
	        printf "$(C_Y)      → 拼错? 文件没被 find 扫到(make why)? 函数加了 static 却跨文件用?$(C_0)\n"; \
	        printf "$(C_Y)      → .S 里 .global 丢了小数点?$(C_0)\n"; \
	    fi; \
	    if grep -qi 'multiple definition' $(BUILD)/.ld.log; then \
	        printf "$(C_Y)    · 重复定义 → .h 里写了函数体, 或漏 include guard / 漏 static$(C_0)\n"; \
	    fi; \
	    if grep -qiE 'not aligned|alignment' $(BUILD)/.ld.log; then \
	        printf "$(C_Y)    · 段对齐冲突 → .text.boot 是否 KEEP 且排第一? 向量表漏 .align 11?$(C_0)\n"; \
	    fi; \
	    if grep -qiE 'overflow|region .* full|out of memory|exceeds' $(BUILD)/.ld.log; then \
	        printf "$(C_Y)    · 镜像超内存区域 → linker.ld 的 . 起点 / RAM LENGTH; 查 make size$(C_0)\n"; \
	    fi; \
	    if grep -qiE 'cannot find|no such file' $(BUILD)/.ld.log; then \
	        printf "$(C_Y)    · 找不到文件 → -T %s 路径对吗?$(C_0)\n" "$(LINKER)"; \
	    fi; \
	    if grep -qiE 'entry symbol|_start' $(BUILD)/.ld.log; then \
	        printf "$(C_Y)    · 入口符号缺失 → boot.S 的 '.global _start' 有小数点吗?$(C_0)\n"; \
	    fi; \
	    printf "$(C_Y)    · (未识别的链接错类, 以上原文为准)$(C_0)\n"; \
	    rm -f $@; exit 1; \
	fi
	@printf "$(C_D)        入口: $(C_B)%s$(C_0)   目标: $(C_B)%s$(C_0)\n" \
	        "$$($(READELF) -h $@ | awk '/Entry point/{print $$NF}')" "$(TARGET)"

#---- L3 编译诊断: C ----
$(BUILD)/%.c.o: %.c
	$(call act_CC)
	@mkdir -p $(dir $@)
	$(Q)$(CC) $(CFLAGS) -c -o $@ $< >$(BUILD)/.diag.$$$$.log 2>&1; \
	if [ -s $(BUILD)/.diag.$$$$.log ]; then \
	    printf "$(C_R)  ✗ $<\n$(C_0)"; sed 's/^/    /' $(BUILD)/.diag.$$$$.log; \
	    printf "$(C_Y)  诊断:$(C_0)\n"; \
	    if grep -qi 'implicit declaration' $(BUILD)/.diag.$$$$.log; then \
	        printf "$(C_Y)    · 函数未声明就被调用 → 在 .h 补原型 + #include 它$(C_0)\n"; \
	    fi; \
	    if grep -qiE 'undeclared identifier|unknown type name' $(BUILD)/.diag.$$$$.log; then \
	        printf "$(C_Y)    · 标识符未见: 1)漏#include 2)-I错 3)**guard写成#ifdef了**(静默吞头文件)$(C_0)\n"; \
	        printf "$(C_Y)      验证: clang -Iinclude -E %s | grep -c <标识符>$(C_0)\n" "$<"; \
	    fi; \
	    if grep -qiE 'redefinition|previous definition|duplicate' $(BUILD)/.diag.$$$$.log; then \
	        printf "$(C_Y)    · 重复定义 → .h 里写了函数体, 或漏 include guard$(C_0)\n"; \
	    fi; \
	    if grep -qiE 'logical .*with constant|tautological|always evaluates to true' $(BUILD)/.diag.$$$$.log; then \
	        printf "$(C_Y)    · **位操作误用 &&** → 寄存器位域一律 & | ~ (&&结果只有0/1, 两边非零则恒真)$(C_0)\n"; \
	    fi; \
	    if grep -qiE 'anonymous struct|expected identifier|expected .* before|stray|syntax error|missing terminating' $(BUILD)/.diag.$$$$.log; then \
	        printf "$(C_Y)    · 语法错: 'struct void foo()' / 漏; / 引号不成对 → **第一个错才是真错**$(C_0)\n"; \
	    fi; \
	    if grep -qiE 'misleading' $(BUILD)/.diag.$$$$.log; then \
	        printf "$(C_Y)    · 缩进撒谎 → 空循环体的 ';' 独占一行, 缩进比 while 深一级$(C_0)\n"; \
	    fi; \
	    if grep -qiE 'no previous prototype|missing.declarations' $(BUILD)/.diag.$$$$.log; then \
	        printf "$(C_Y)    · 全局函数无原型 → 建 .h 声明; 别加 static (符号不导出, 链接会找不到)$(C_0)\n"; \
	    fi; \
	    if grep -qiE 'unused function|unused variable' $(BUILD)/.diag.$$$$.log; then \
	        printf "$(C_Y)    · static 无人用 → 放错文件; 跨文件用要 .h + static inline 且真被 include$(C_0)\n"; \
	    fi; \
	    if grep -qiE 'incompatible pointer|makes pointer|makes integer' $(BUILD)/.diag.$$$$.log; then \
	        printf "$(C_Y)    · 指针/整数混用 → 回想 '0'(整数48) vs \"0\"(地址) 那个坑$(C_0)\n"; \
	    fi; \
	    if grep -qiE 'fallthrough' $(BUILD)/.diag.$$$$.log; then \
	        printf "$(C_Y)    · switch 穿透 → 每个 case 要 break 或 /* fallthrough */$(C_0)\n"; \
	    fi; \
	    if grep -qiE 'division by zero|shift.*exceed|overflow in constant' $(BUILD)/.diag.$$$$.log; then \
	        printf "$(C_Y)    · 常量算术错 → 移位超位宽? 除零?$(C_0)\n"; \
	    fi; \
	    if grep -qiE 'asm|constraint|operand' $(BUILD)/.diag.$$$$.log; then \
	        printf "$(C_Y)    · 内联汇编: mrs \"mrs %%0, CurrentEL\":\"=r\"(v) | msr \"msr X, %%0\"::\"r\"(v):\"memory\"$(C_0)\n"; \
	    fi; \
	    printf "$(C_Y)    · (adhesive v$(ADHESIVE_VERSION) 未识别此类, 以上原文为准)$(C_0)\n"; \
	    rm -f $(BUILD)/.diag.*.log; exit 1; \
	fi
	@rm -f $(BUILD)/.diag.*.log

#---- L3 编译诊断: 汇编 ----
$(BUILD)/%.S.o: %.S
	$(call act_AS)
	@mkdir -p $(dir $@)
	$(Q)$(CC) $(ASFLAGS) -c -o $@ $< >$(BUILD)/.diag.$$$$.log 2>&1; \
	if [ -s $(BUILD)/.diag.$$$$.log ]; then \
	    printf "$(C_R)  ✗ $<\n$(C_0)"; sed 's/^/    /' $(BUILD)/.diag.$$$$.log; \
	    printf "$(C_Y)  诊断:$(C_0)\n"; \
	    if grep -qiE 'unknown mnemonic|unrecognized|bad instruction' $(BUILD)/.diag.$$$$.log; then \
	        printf "$(C_Y)    · 拼错: '.global'(有小数点) / mrs 方向(目标寄存器在前) → 汇编器常把错词当标号, 静默$(C_0)\n"; \
	    fi; \
	    if grep -qiE 'expecting|operand|junk after|comma' $(BUILD)/.diag.$$$$.log; then \
	        printf "$(C_Y)    · 操作数: 逗号别省(ldr x0, =0x8000); mov 只吃16位, 太大改 ldr =...$(C_0)\n"; \
	    fi; \
	    if grep -qiE 'align' $(BUILD)/.diag.$$$$.log; then \
	        printf "$(C_Y)    · .align N 在 aarch64 是 2^N 字节 → 向量表 2KB 用 .align 11, 每项用 .align 7$(C_0)\n"; \
	    fi; \
	    if grep -qiE 'already defined|redefined' $(BUILD)/.diag.$$$$.log; then \
	        printf "$(C_Y)    · 符号重复 → 两个 .S 都写了 _start?$(C_0)\n"; \
	    fi; \
	    printf "$(C_Y)    · (adhesive v$(ADHESIVE_VERSION) 未识别此类, 以上原文为准)$(C_0)\n"; \
	    rm -f $(BUILD)/.diag.*.log; exit 1; \
	fi
	@rm -f $(BUILD)/.diag.*.log

#===============================================================================
#  7. L1+L2 体检
#===============================================================================
.PHONY: doctor
doctor:
	@printf "$(C_B)$(BOLD)▸ adhesive v$(ADHESIVE_VERSION) 环境自检$(C_0)\n"
	@for t in $(TOOLS); do \
	    if command -v $$t >/dev/null 2>&1; then \
	        printf "$(C_G)  ✓ %-20s$(C_0) $(C_D)%s$(C_0)\n" "$$t" "$$($$t --version 2>&1 | head -1 | cut -c1-46)"; \
	    else \
	        printf "$(C_R)  ✗ %-20s$(C_0) 未找到$(C_0)\n" "$$t"; \
	        case $$t in \
	            *clang)         printf "$(C_Y)      pkg install clang$(C_0)\n";; \
	            ld.lld|*llvm-*) printf "$(C_Y)      pkg install lld$(C_0)\n";; \
	        esac; \
	    fi; \
	done
	@if command -v $(QEMU) >/dev/null 2>&1; then \
	    printf "$(C_G)  ✓ %-20s$(C_0) $(C_D)%s$(C_0)\n" "$(QEMU)" "$$($(QEMU) --version 2>&1 | head -1)"; \
	else \
	    printf "$(C_R)  ✗ %-20s$(C_0) → pkg install qemu-system-aarch64$(C_0)\n" "$(QEMU)"; \
	fi
	@printf "$(C_B)▸ triple 验证$(C_0)\n"
	@mkdir -p $(BUILD)
	@printf 'int __probe;\n' > $(BUILD)/.probe.c
	@if $(CC) --target=$(TARGET) -ffreestanding -c -o $(BUILD)/.probe.o $(BUILD)/.probe.c 2>/dev/null; then \
	    printf "$(C_G)  ✓ --target=$(TARGET) 可用$(C_0)\n"; \
	else \
	    printf "$(C_R)  ✗ --target=$(TARGET) 编译失败$(C_0)\n"; \
	fi
	@rm -f $(BUILD)/.probe.c $(BUILD)/.probe.o
	@printf "$(C_B)▸ 项目结构$(C_0)\n"
	@for d in $(SRC_DIRS_C) $(SRC_DIRS_S) $(INC_DIRS); do \
	    if [ -d $$d ]; then printf "$(C_G)  ✓ %s/$(C_0)\n" $$d; \
	    else printf "$(C_Y)  ! %s/ 不存在$(C_0)\n" $$d; fi; \
	done
	@if [ -f $(LINKER) ]; then printf "$(C_G)  ✓ %s$(C_0)\n" $(LINKER); \
	else printf "$(C_R)  ✗ %s 缺失 → ld 用默认脚本, 入口落 0x10000, QEMU 黑屏无报错$(C_0)\n" $(LINKER); fi
	@printf "$(C_B)▸ L2 手滑扫描 (你踩过的坑)$(C_0)\n"
	@h=$$(grep -rn '^#ifdef CATALYST' include/ 2>/dev/null | wc -l); \
	if [ "$$h" -gt 0 ]; then \
	    printf "$(C_R)  ✗ %s 处 #ifdef 当 guard (必须 #ifndef)$(C_0)\n" $$h; \
	    grep -rn '^#ifdef CATALYST' include/ | sed 's/^/      /'; \
	else printf "$(C_G)  ✓ include guard 全 #ifndef$(C_0)\n"; fi
	@h=$$(grep -rnE '\b(el|val|sctlr|spsr|hcr|scr|esr|far|reg|tmp)\w*\s*>>[^;]*&&' kernel/ arch/ include/ 2>/dev/null | wc -l); \
	if [ "$$h" -gt 0 ]; then \
	    printf "$(C_Y)  ! %s 处位域用 && (应 &)$(C_0)\n" $$h; \
	    grep -rnE '\b(el|val|sctlr|spsr|hcr|scr|esr|far|reg|tmp)\w*\s*>>[^;]*&&' kernel/ arch/ include/ | sed 's/^/      /'; \
	else printf "$(C_G)  ✓ 位域未见 && 误用$(C_0)\n"; fi
	@h=$$(grep -rn 'struct void' kernel/ arch/ include/ 2>/dev/null | wc -l); \
	if [ "$$h" -gt 0 ]; then printf "$(C_R)  ✗ %s 处 'struct void' 手滑$(C_0)\n" $$h; \
	    grep -rn 'struct void' kernel/ arch/ include/ | sed 's/^/      /'; \
	else printf "$(C_G)  ✓ 未见 struct void$(C_0)\n"; fi
	@h=$$(grep -rn "putc(\"" kernel/ arch/ 2>/dev/null | wc -l); \
	if [ "$$h" -gt 0 ]; then printf "$(C_Y)  ! %s 处 putc(\"...\") 双引号传的是指针$(C_0)\n" $$h; \
	    grep -rn "putc(\"" kernel/ arch/ | sed 's/^/      /'; \
	else printf "$(C_G)  ✓ putc 未见双引号误用$(C_0)\n"; fi
	@printf "$(C_B)▸ 空编译单元 / 期望符号$(C_0)\n"
	@f=0; for s in $(SRCS_S) $(SRCS_C); do \
	    if [ ! -s "$$s" ]; then printf "$(C_Y)  ! %s 空文件 → 编成空 .o 且全程不报错$(C_0)\n" "$$s"; f=1; fi; \
	 done; \
	 if [ "$$f" = 0 ]; then printf "$(C_G)  ✓ 无空源文件$(C_0)\n"; fi
	@for s in $(EXPECT_SYMS); do \
	    if grep -rqw "$$s" $(SRC_DIRS_S) $(SRC_DIRS_C) 2>/dev/null; then \
	        printf "$(C_G)  ✓ %-18s 已定义$(C_0)\n" "$$s"; \
	    else \
	        printf "$(C_Y)  ! %-18s 尚未定义 (后续课程会用到)$(C_0)\n" "$$s"; \
	    fi; \
	done

#===============================================================================
#  8. 导航 / L6 验尸
#===============================================================================
.PHONY: why
why:
	@printf "$(C_B)$(BOLD)▸ 源文件发现诊断$(C_0)\n"
	@printf "$(C_D)  扫描: C=%s  S=%s$(C_0)\n" "$(SRC_DIRS_C)" "$(SRC_DIRS_S)"
	@printf "$(C_D)  已发现 %s 个:$(C_0)\n" "$(words $(SRCS))"
	@$(foreach s,$(SRCS),printf "    $(C_G)✓$(C_0) %s\n" $(s);)
	@printf "$(C_Y)  常见原因: 目录外(make SRC_DIRS_C+=目录) / .s小写 / 被 EXCLUDE$(C_0)\n"

.PHONY: tree
tree:
	@printf "$(C_B)$(BOLD)▸ 源文件 → 产物 (%s 个)$(C_0)\n" "$(words $(OBJS))"
	@$(foreach o,$(OBJS),printf "  $(C_D)%-38s$(C_0)→ $(C_M)%s$(C_0)\n" $(patsubst $(BUILD)/%.o,%,$(o)) $(o);)

.PHONY: size
size: $(ELF)
	@printf "$(C_B)$(BOLD)▸ 体积报告$(C_0)\n"
	@$(SIZE) -A $(ELF) 2>/dev/null | sed 's/^/  /' || $(SIZE) $(ELF) | sed 's/^/  /'
	@printf "  $(C_D)ELF 总: %s 字节$(C_0)\n" "$$(stat -c %s $(ELF))"

.PHONY: check
check: $(ELF)
	@printf "$(C_B)$(BOLD)▸ 验尸报告: $(ELF)$(C_0)\n"
	@e=$$($(READELF) -h $(ELF) | awk '/Entry point/{print $$NF}'); \
	printf "  入口: $(C_B)0x%s$(C_0) " $$e; \
	case $$e in \
	    0000000040000000) printf "$(C_G)✓ 与 linker.ld 一致$(C_0)\n";; \
	    0000000000010000) printf "$(C_R)✗ 0x10000 = ld 用默认脚本, -T 没生效"✓ 语法 OK"(C_0)\n";; \
	    *) printf "$(C_R)✗ 期望 0x40000000$(C_0)\n";; \
	esac
	@printf "\n  $(C_D)段布局:$(C_0)\n"
	@$(READELF) -S $(ELF) | awk '/\.text|\.rodata|\.data|\.bss|vectors/{printf "    %-16s %-10s addr=%s size=%s\n",$$2,$$3,$$5,$$6}'
	@printf "\n  $(C_D)对齐检查 (向量表要 2KB = 低 11 位全 0):$(C_0)\n"
	@$(NM) -n $(ELF) 2>/dev/null | grep -iE 'exception_vectors|_start|kernel_main' | while read a t n; do \
	    lo=$$((0x$$a & 2047)); \
	    if [ "$$lo" = 0 ]; then printf "    $(C_G)✓$(C_0) %-20s 0x%s\n" "$$n" "$$a"; \
	    else printf "    $(C_R)✗$(C_0) %-20s 0x%s 低11位=%d ← 不对齐!\n" "$$n" "$$a" "$$lo"; fi; \
	done
	@printf "\n  $(C_D)未定义符号 (应为空):$(C_0)\n"
	@$(NM) -u $(ELF) 2>/dev/null | sed 's/^/    /' | head -10
	@printf "\n  $(C_D)前 8 符号:$(C_0)\n"
	@$(NM) -n $(ELF) | head -8 | sed 's/^/    /'
	@printf "\n  $(C_D)链接映射: $(C_M)%s$(C_0)\n" "$(MAP)"

.PHONY: disasm
disasm: $(ELF)
	@if [ -z "$(FN)" ]; then \
	    printf "$(C_Y)用法: make disasm FN=kernel_main$(C_0)\n"; \
	    $(NM) -n $(ELF) | grep ' [tT] ' | sed 's/^/    /'; \
	else \
	    printf "$(C_B)$(BOLD)▸ 反汇编 $(FN)$(C_0)\n"; \
	    $(OBJDUMP) -d --disassemble=$(FN) $(ELF) | sed 's/^/  /'; \
	fi

.PHONY: trace
trace: $(ELF)
	@printf "$(C_Y)▸ QEMU 全量追踪 → $(C_M)build/qemu.log$(C_0)\n"
	$(QEMU) -machine virt -cpu cortex-a72 -nographic -kernel $(ELF) \
	        -d int,cpu_reset,guest_errors,mmu -D $(BUILD)/qemu.log 2>&1 || true
	@printf "$(C_G)✓ %s 行 → grep -nE 'Exception|Synchronous' %s | head -30$(C_0)\n" "$$(wc -l < $(BUILD)/qemu.log)" "$(BUILD)/qemu.log"

.PHONY: tags
tags:
	@if command -v ctags >/dev/null 2>&1; then \
	    ctags -R --fields=+iaS --extra=+q $(SRC_DIRS_C) $(SRC_DIRS_S) $(INC_DIRS) \
	    && printf "$(C_G)✓ tags 已生成$(C_0)\n"; \
	else printf "$(C_Y)! pkg install universal-ctags$(C_0)\n"; fi

#===============================================================================
#  9. L5 运行 + 清理
#===============================================================================
.PHONY: run
run: $(ELF)
	$(call act_QEMU)
	@printf "$(C_D)$(BAR)$(C_0)\n"
	$(Q) $(QEMU) $(QEMUFLAGS) $(ELF); rc=$$?; \
	printf "$(C_D)$(BAR)$(C_0)\n"; \
	if [ $$rc -eq 0 ]; then \
	    printf "$(C_G)✓ QEMU 正常退出$(C_0)\n"; \
	else \
	    printf "$(C_R)✗ QEMU 退出码 $$rc$(C_0)\n"; \
	    printf "$(C_Y)  · 137=SIGKILL(Termux 内存压力) / 打印后卡住=正常, Ctrl+A 松手 X$(C_0)\n"; \
	    printf "$(C_Y)  · 全黑: 1)入口非0x40000000 2)_start没bl到kernel_main$(C_0)\n"; \
	    printf "$(C_Y)        3)VBAR_EL1=0 异常跳地址0静默死 4)HCR_EL2.RW漏设掉进AArch32$(C_0)\n"; \
	    printf "$(C_Y)  · 乱码→UART未初始化/FR_TXFF没查; 只打半句→后面指令异常, 看ELR$(C_0)\n"; \
	    printf "$(C_Y)  · 深挖: make trace$(C_0)\n"; \
	fi

.PHONY: bin
bin: $(ELF)
	$(call act_GEN)
	$(Q)$(OBJCOPY) -O binary $(ELF) $(BIN)
	@printf "  $(C_D)%s 字节$(C_0)\n" "$$(stat -c %s $(BIN))"

.PHONY: clean
clean:
	$(Q)rm -rf $(BUILD)
	@printf "$(C_G)✓ 已清理 $(BUILD)/$(C_0)\n"

.PHONY: mrproper
mrproper: clean
	$(Q)rm -f tags cscope.* *~ 2>/dev/null
	@printf "$(C_G)✓ 彻底清扫$(C_0)\n"

.PHONY: help
help:
	@printf "$(C_B)$(BOLD)adhesive v$(ADHESIVE_VERSION) — CatalystOS 构建粘合剂$(C_0)\n"
	@printf "  $(C_M)make$(C_0)              构建\n"
	@printf "  $(C_M)make V=1$(C_0)          完整命令\n"
	@printf "  $(C_M)make doctor$(C_0)       L1工具+L2手滑+空文件+期望符号\n"
	@printf "  $(C_M)make check$(C_0)        L6 入口/段/2KB对齐/未定义符号\n"
	@printf "  $(C_M)make run|trace$(C_0)    L5 点火 / QEMU 全量追踪\n"
	@printf "  $(C_M)make disasm FN=foo$(C_0) 反汇编\n"
	@printf "  $(C_M)make size|tree|why$(C_0) 体积 / 映射 / 文件未被编入诊断\n"
	@printf "  $(C_M)make clean|mrproper$(C_0)\n"
	@printf "\n  $(C_D)覆盖: make CC=clang-21 TARGET=... EXCLUDE=\"...\" EXPECT_SYMS=\"...\"$(C_0)\n"

#---- 头文件依赖: 必须在 OBJS/DEPS 之后 ----
-include $(DEPS)

endif # ADHESIVE_INCLUDED
