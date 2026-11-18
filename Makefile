#====== CatalystOS / aarch64 ======

TARGET   := aarch64-unknown-none
BUILD    := build
SRC_ARCH := arch/aarch64

CC       := clang
LD       := ld.lld
OBJCOPY  := llvm-objcopy
OBJDUMP  := llvm-objdump
READELF  := llvm-readelf
QEMU     := qemu-system-aarch64

CFLAGS   := --target=$(TARGET) -ffreestanding -nostdlib -fno-builtin \
            -Wall -Wextra -Werror -O2 \
            -Iinclude
ASFLAGS  := --target=$(TARGET)
LDFLAGS  := -T $(SRC_ARCH)/linker.ld
QEMUFLAGS:= -machine virt -cpu cortex-a72 -nographic -kernel

#---- 源与产物 ----
SRCS := $(SRC_ARCH)/boot.S kernel/kernel.c
OBJS := $(patsubst %,$(BUILD)/%.o,$(SRCS))
ELF  := $(BUILD)/catalyst.elf
BIN  := $(BUILD)/catalyst.bin

#---- 默认目标 ----
all: $(ELF)

#---- 链接 ----
$(ELF): $(OBJS) $(SRC_ARCH)/linker.ld
	@echo "[LD] $@"
	$(LD) $(LDFLAGS) -o $@ $(filter %.o,$^)

#---- 编译 C ----
$(BUILD)/kernel/%.c.o: kernel/%.c
	@mkdir -p $(dir $@)
	@echo "[CC] $<"
	$(CC) $(CFLAGS) -c -o $@ $<

#---- 汇编 ----
$(BUILD)/arch/aarch64/%.S.o: arch/aarch64/%.S
	@mkdir -p $(dir $@)
	@echo "[AS] $<"
	$(CC) $(ASFLAGS) -c -o $@ $<

#---- 二进制 ----
bin: $(ELF)
	$(OBJCOPY) -O binary $< $(BIN)

#---- 检查 ----
check: $(ELF)
	@echo "===== ELF Header ====="
	$(READELF) -h $(ELF) | grep -iE 'entry|machine|type'
	@echo "===== Sections ====="
	$(READELF) -S $(ELF)
	@echo "===== Symbols ====="
	llvm-nm -n $(ELF)

#---- 运行 ----
run: $(ELF)
	$(QEMU) $(QEMUFLAGS) $(ELF)

#---- 调试：QEMU 内置 GDB stub，挂起等连接 ----
debug: $(ELF)
	$(QEMU) $(QEMUFLAGS) $(ELF) -S -gdb tcp::1234

clean:
	rm -rf $(BUILD)

.PHONY: all bin check run debug clean
