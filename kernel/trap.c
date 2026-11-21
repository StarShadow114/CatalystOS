/*
 * kernel/trap.c — AArch64 异常分发 (stage 2B)
 *
 * ═══════════════════════════════════════════════════════════════════════
 *  五条结构纪律 —— 每一条都是今晚炸过至少一次换来的
 * ═══════════════════════════════════════════════════════════════════════
 *
 *  【1】异常路径零外部依赖
 *      所有输出走 raw_* (内联汇编直撸 PL011), 不调 uart.c 的任何函数.
 *      uart_* 隐含四个前提: init 跑过 / 全局标志有效 / 栈可用 / 无重入.
 *      而异常可以在这四个前提全不成立时发生 (包括 uart_init 之前).
 *      历史: [raw] 一行打不出来, 曾误判为 uart_hex64 炸了, 实际是
 *            trap_dump_raw 压根没被调用 (sed 的 \s 非 POSIX, 静默替换 0 处).
 *
 *  【2】static 函数一律在顶部声明区登记
 *      C99 禁隐式声明. 不登记则"定义顺序"变成隐式约束:
 *      调在前 + 定义在後 → "call to undeclared function",
 *      且若真定义带 static 会连带报 "static declaration follows non-static".
 *
 *  【3】★ 声明归属: 互补, 绝不重叠
 *          调用者只在本文件 → static + 本文件声明区
 *          调用者超出本文件 → include/kernel/trap.h 登记, 【不再进本表】
 *      同一个函数两处声明且链接属性不同 = 硬错. 今晚栽过一次.
 *      自查: tools/declcheck.sh
 *
 *  【4】2B 阶段所有 handler 必须 noreturn
 *      eret 会回到 ELR 那条出错指令; 2B 无修复逻辑, 返回 = 必然再炸 = 刷屏.
 *      三道保险:
 *        __attribute__((noreturn))        [编译期]
 *        for (;;) { asm volatile("wfi"); } [运行期 C 内]
 *        vectors.S 的 adr x30, vector_trap_return [运行期汇编, 物理兜底]
 *      2C 加了 trapframe + ELR+=4 之后才允许返回.
 *
 *  【5】★ 纯映射用表, 不用 switch
 *      "常量 → 字符串" 一律表驱动: 值和名字写在同一行,
 *      结构上不可能出现 "两个 case 同值".
 *      历史: vec_name 里 case 0x100 写了两遍 (架构偏移 FIQ vs 自创简编号),
 *            → duplicate case value; 修的时候又切坏了函数体 → 回声错三连.
 */

#include <kernel/trap.h>
#include <arch/aarch64/mmio.h>

/*══════════════════════════════════════════════════════════════════════
 * 内部函数前向声明区 —— 【只】放本文件私有的 static 函数
 *
 *  ⚠ trap_dump_raw 不在此列: 它已在 include/kernel/trap.h 登记为全局接口.
 *     再在这里写 static 就是自相矛盾 (static declaration follows
 *     non-static declaration). 详见纪律 3.
 *
 *  ⚠ 新增 static 函数, 第一动作是在这里登记一行 —— 不是写完再补.
 *════════════════════════════════════════════════════════════════════ */
static void raw_putc(char c);
static void raw_puts(const char *s);
static void raw_hex32(unsigned int v);
static void raw_hex64(unsigned long v);
static const char *vec_name(unsigned int vec);
static const char *ec_name(unsigned int ec);
static const char *dfsc_name(unsigned int dfsc);

/*──────────────────────────────────────────────────────────────────────
 * 异常计数器: 分辨"刷屏"是 handler 返回了, 还是被反复触发
 *   [seq] trap #1 只一次 = handler 吊死成功 ✓
 *   [seq] trap #2,#3... = 有路径跑出去了 ✗ 查 vectors.S 的 adr x30 展开
 * 放 .data (有初值), 不依赖 .bss 清零 —— 少一重依赖.
 *──────────────────────────────────────────────────────────────────── */
static volatile unsigned int g_trap_seq;

/*══════════════════════════════════════════════════════════════════════
 * 一、异常路径专用输出 —— 内联汇编直撸 PL011, 零依赖, 可重入
 *
 *  不用锁: 同一核重入时自旋锁 = 自死锁
 *  不用全局状态: 嵌套异常时标志可能是半写
 *  不碰栈: 异常可能由 SP 损坏触发
 *  只用 w2 且在 clobber 声明: 不踩 C 的寄存器分配
 *  volatile 必须有: 否则 -O2 可能把轮询循环优化掉
 *════════════════════════════════════════════════════════════════════ */
static void raw_putc(char c)
{
    __asm__ volatile (
        "1:  ldr  w2, [%0]            \n"
        "    tbz  w2, #5, 2f          \n"   /* bit5 = TXFF; 0 = FIFO 有空位 */
        "    b    1b                  \n"
        "2:  strb %w1, [%2]           \n"
        : : "r"((unsigned long)UART0_FR),
            "r"((unsigned long)(unsigned char)c),
            "r"((unsigned long)UART0_DR)
        : "w2", "memory"
    );
}

static void raw_puts(const char *s)
{
    while (*s) {
        raw_putc(*s);
        s++;
    }
}

/* 32 位: 8 轮, 一位一组.
 * ★ 必须定义在 raw_hex64 【之前】 —— 它被 hex64 调用.
 *   历史: 顺序反了 → "call to undeclared function" + "static declaration
 *         follows non-static declaration" (一个 bug 的两个回声). */
static void raw_hex32(unsigned int v)
{
    static const char hex[] = "0123456789abcdef";
    int i;

    for (i = 28; i >= 0; i -= 4)
        raw_putc(hex[(v >> i) & 0xF]);
}

/* 64 位: 拆两次 32 位调用, 避开 16 轮循环里的 %w 修饰符细节 */
static void raw_hex64(unsigned long v)
{
    raw_puts("0x");
    raw_hex32((unsigned int)(v >> 32));
    raw_hex32((unsigned int)(v & 0xffffffffUL));
}

/*══════════════════════════════════════════════════════════════════════
 * 二、查表 —— 把数字翻译成人话 (纪律 5: 纯映射用表)
 *
 *  ★ 这三张表是横幅能打出 "Data Abort, same EL" 的唯一来源.
 *    覆盖本文件时漏掉它们 = 编译链接全绿, 运行时横幅只打数字,
 *    然后你对着 "EC : 0x25" 看两小时. ← 覆盖的失败是安静的.
 *  ★ 全部 static + const, 留在 .rodata, 不占栈.
 *════════════════════════════════════════════════════════════════════ */

/* 向量偏移 = 组号×0x800 + 类型×0x80, 共 16 项; AArch64 用其中 8 项.
 * 组 0 = EL1h (用 SP_EL1), 组 1 = EL0/AArch64, 组 2/3 = AArch32 (不支持).
 * ★ 编号纪律: 一律用架构规定的完整偏移, 禁止自创简编号 (0x10 之类) ——
 *   0x10 会和组 0 的 FIQ (0x100) 在简写下混淆, 且无法对照 ARM ARM. */
static const char *vec_name(unsigned int vec)
{
    static const struct { unsigned int off; const char *name; } tab[] = {
        { 0x000, "SYNC   from EL1h (SP_EL1)" },
        { 0x080, "IRQ    from EL1h (SP_EL1)" },
        { 0x100, "FIQ    from EL1h (SP_EL1)" },
        { 0x180, "SERROR from EL1h (SP_EL1)" },
        { 0x200, "SYNC   from EL0  (AArch64)" },
        { 0x280, "IRQ    from EL0  (AArch64)" },
        { 0x300, "FIQ    from EL0  (AArch64)" },
        { 0x380, "SERROR from EL0  (AArch64)" },
    };
    unsigned int i;

    for (i = 0; i < sizeof(tab) / sizeof(tab[0]); i++) {
        if (tab[i].off == vec)
            return tab[i].name;
    }

    /* 走到这儿 = vec 不是 8 个合法偏移之一. 最常见原因:
     *   ① vectors.S 发的是自创简编号 (如 0x10 / 0x100 当 EL0 组)
     *   ② vectors.S 某项漏了 .align 7 → 偏移偏 128 字节
     *   ③ 向量表没按 2KB 对齐 → VBAR 低 11 位非 0, 取的根本不是这张表 */
    return "?? unknown vector (偏移非 0x80 倍数? 查 vectors.S 的 .align 7 与链接脚本对齐)";
}

/* ESR_EL1.EC — Exception Class, bit[31:26].
 * 这里用 switch 而非表: case 多 (60+), 且漏一项无害 —— 走 default 的
 * "?? reserved" 本身就是正确的兜底语义 (保留编码就该打 reserved).
 * 判据: 编译器能替我验"重复"(switch 能), 漏项由 default 兜住 → switch 够用. */
static const char *ec_name(unsigned int ec)
{
    switch (ec) {
    case 0x00: return "Unknown";
    case 0x01: return "Trapped WFI/WFE";
    case 0x03: return "Trapped MRS, CP15";
    case 0x07: return "Access SVE/SIMD/FP";
    case 0x0E: return "Illegal Execution state        ★ 切到 AArch32 了";
    case 0x11: return "SVC (AArch32)";
    case 0x15: return "SVC (AArch64)                   ← 2C 系统调用入口";
    case 0x18: return "Trapped MSR, CP15";
    case 0x1E: return "Trapped instruction";
    case 0x20: return "Instruction Abort, lower EL";
    case 0x21: return "Instruction Abort, same EL     ★ PC 跑到没映射的地方";
    case 0x22: return "PC alignment fault             ★ PSTATE.M 是垃圾的典型症状";
    case 0x24: return "Data Abort, lower EL";
    case 0x25: return "Data Abort, same EL            ★ 页表不存在 / 地址非法";
    case 0x26: return "SP alignment fault             ★ SP 未 16 字节对齐";
    case 0x28: return "Trapped FP exception (AArch32)";
    case 0x2A: return "Trapped FP exception (AArch64)";
    case 0x2C: return "SError (async, precise)";
    case 0x2D: return "SError (async, imprecise)";
    case 0x2E: return "SError (async, imprecise, from lower EL)";
    case 0x30: return "Breakpoint (lower EL, AArch32)";
    case 0x31: return "Breakpoint (lower EL, AArch64)  ← 2C 断点的常态";
    case 0x32: return "Breakpoint (same EL)";
    case 0x34: return "Software Step (lower EL)";
    case 0x35: return "Software Step (same EL)";
    case 0x38: return "Watchpoint (lower EL)";
    case 0x39: return "Watchpoint (same EL)";
    case 0x3A: return "BKPT (AArch32)";
    case 0x3C: return "BRK (AArch64)                  ← 2C 断点的常态";
    case 0x3D: return "DCPS1";
    case 0x3E: return "DCPS2";
    case 0x3F: return "DCPS0";
    default:   return "?? reserved (架构保留编码, 查 ARM ARM DDI 0487)";
    }
}

/* ESR_EL1 的 DFSC (Data Fault Status Code), bit[5:0], 仅 EC=0x24/0x25 有意义 */
static const char *dfsc_name(unsigned int dfsc)
{
    switch (dfsc & 0x3F) {
    case 0x00: return "Address size fault, L0";
    case 0x01: return "Address size fault, L1";
    case 0x02: return "Address size fault, L2";
    case 0x03: return "Address size fault, L3";
    case 0x04: return "Translation fault, L0         ★ 该级页表项全 0 (2B 常态)";
    case 0x05: return "Translation fault, L1";
    case 0x06: return "Translation fault, L2";
    case 0x07: return "Translation fault, L3";
    case 0x09: return "Access flag fault, L0";
    case 0x0A: return "Access flag fault, L1";
    case 0x0B: return "Access flag fault, L2";
    case 0x0C: return "Access flag fault, L3";
    case 0x0D: return "Permission fault, L0";
    case 0x0E: return "Permission fault, L1";
    case 0x0F: return "Permission fault, L2";
    case 0x10: return "Permission fault, L3           ← 页表有了但权限不对 (2D 常客)";
    case 0x11: return "Synchronous external abort";
    case 0x15: return "Sync external abort on translation table walk";
    case 0x18: return "Synchronous parity/ECC error";
    case 0x1C: return "Sync parity/ECC error on translation table walk";
    case 0x21: return "Alignment fault";
    case 0x23: return "Unsupported atomic/exclusive";
    case 0x24: return "Tag check fault (L0)";
    case 0x25: return "Tag check fault (L1)";
    case 0x26: return "Tag check fault (L2)";
    case 0x27: return "Tag check fault (L3)";
    case 0x2A: return "Address size fault, TT walk (L0)";
    case 0x2B: return "Address size fault, TT walk (L1)";
    case 0x2C: return "Address size fault, TT walk (L2)";
    case 0x2D: return "Address size fault, TT walk (L3)";
    case 0x35: return "Access flag fault, TT walk (L0)";
    case 0x36: return "Access flag fault, TT walk (L1)";
    case 0x37: return "Access flag fault, TT walk (L2)";
    case 0x38: return "Access flag fault, TT walk (L3)";
    case 0x39: return "Permission fault, TT walk (L0)";
    case 0x3A: return "Permission fault, TT walk (L1)";
    case 0x3B: return "Permission fault, TT walk (L2)";
    case 0x3C: return "Permission fault, TT walk (L3)";
    default:   return "?? reserved FSC";
    }
}

/*══════════════════════════════════════════════════════════════════════
 * 三、裸诊断 —— 全局可见 (trap.h), 最先打, 不做任何假设
 *
 *  为什么存在: ESR/ELR/FAR 曾整整两轮一行都打不出来, 根因不是
 *     uart_hex64 炸了, 是 trap_dump_raw 压根没被调用.
 *  为什么打 CurrentEL 和 SPSR.M: 分辨"软件以为在 EL1" vs "硬件记录 EL0".
 *     vec=0x200 (EL0 组) 与 CurrentEL=1 的矛盾, 只有 SPSR.M 能裁决:
 *       M=0b0101 (5) → EL1h, 向量的 vec 号判读错了
 *       M=0b0000 (0) → EL0t, PSTATE 摆位真的失败了
 *════════════════════════════════════════════════════════════════════ */
void trap_dump_raw(unsigned int vec)
{
    unsigned long esr, elr, far, spsr, cur;

    __asm__ volatile ("mrs %0, ESR_EL1  " : "=r"(esr));
    __asm__ volatile ("mrs %0, ELR_EL1  " : "=r"(elr));
    __asm__ volatile ("mrs %0, FAR_EL1  " : "=r"(far));
    __asm__ volatile ("mrs %0, SPSR_EL1 " : "=r"(spsr));
    __asm__ volatile ("mrs %0, CurrentEL" : "=r"(cur));

    raw_puts("\r\n[raw] vec=");   raw_hex32(vec);
    raw_puts("  CurrentEL=");     raw_hex32((unsigned int)(cur >> 2));
    raw_puts("\r\n[raw] ESR=");   raw_hex64(esr);
    raw_puts("  EC=");            raw_hex32((unsigned int)(esr >> 26));
    raw_puts("\r\n[raw] ELR=");   raw_hex64(elr);
    raw_puts("\r\n[raw] FAR=");   raw_hex64(far);
    raw_puts("\r\n[raw] SPSR=");  raw_hex64(spsr);
    raw_puts("  M=");             raw_hex32((unsigned int)(spsr & 0xF));
    raw_puts("  ");
    raw_puts((spsr & 0xF) == 0x5 ? "EL1h ✓"
           : (spsr & 0xF) == 0x0 ? "EL0t ✗ PSTATE 摆位失败"
           :                        "?? 异常值");
    raw_puts("\r\n");
}

/*══════════════════════════════════════════════════════════════════════
 * 四、分发核心 —— 2B: 打印后吊死, 绝不返回 (纪律 4)
 *════════════════════════════════════════════════════════════════════ */
__attribute__((noreturn)) void trap_entry(unsigned int vec)
{
    unsigned long esr, elr, far, spsr;
    unsigned int ec;

    g_trap_seq++;
    raw_puts("\r\n[seq] trap #");
    raw_hex32(g_trap_seq);
    raw_puts("\r\n");

    /* ★ 第一步就裸打寄存器 —— 哪怕后面全炸, 这几个数也已经在串口上了 */
    trap_dump_raw(vec);

    __asm__ volatile ("mrs %0, ESR_EL1 " : "=r"(esr));
    __asm__ volatile ("mrs %0, ELR_EL1 " : "=r"(elr));
    __asm__ volatile ("mrs %0, FAR_EL1 " : "=r"(far));
    __asm__ volatile ("mrs %0, SPSR_EL1" : "=r"(spsr));

    ec = (unsigned int)(esr >> 26);

    raw_puts("\r\n════════ FATAL TRAP ════════\r\n");
    raw_puts("vec : "); raw_hex64(vec);  raw_puts("  "); raw_puts(vec_name(vec));
    raw_puts("\r\nESR : "); raw_hex64(esr);
    raw_puts("\r\nELR : "); raw_hex64(elr);
    raw_puts("     (对到具体指令: make disasm FN=kernel_main)");
    raw_puts("\r\nFAR : "); raw_hex64(far);
    raw_puts("\r\nSPSR: "); raw_hex64(spsr);
    raw_puts("   M["); raw_hex32((unsigned int)(spsr & 0xF)); raw_puts("] = ");
    raw_puts((spsr & 0xF) == 0x5 ? "EL1h ✓"
           : (spsr & 0xF) == 0x0 ? "EL0t ✗ 摆位失败"
           :                        "?? 异常");
    raw_puts("\r\nEC  : "); raw_hex32(ec);  raw_puts("  "); raw_puts(ec_name(ec));

    /* DFSC 只有 Data/Instruction Abort 才有意义, 其余打出来是噪声 */
    if (ec == 0x25 || ec == 0x24 || ec == 0x21 || ec == 0x20) {
        raw_puts("\r\nDFSC: "); raw_hex32((unsigned int)(esr & 0x3F));
        raw_puts("  "); raw_puts(dfsc_name((unsigned int)(esr & 0x3F)));
        if (ec == 0x25 && (esr & 0x3F) == 0x04)
            raw_puts("     ← 2B 的常态: 根本没建页表, L0 项全 0");
    }

    raw_puts("\r\n════════════════════════════\r\n");
    raw_puts("2B 不返回: eret 会回到 ELR 那条指令, 无修复逻辑必然再炸.\r\n");
    raw_puts("2C 加 trapframe + ELR+=4 之后才允许返回.\r\n\r\n");

    for (;;) {
        __asm__ volatile ("wfi");
    }
}

/*──────────────────────────────────────────────────────────────────────
 * 五、各向量入口
 *   vectors.S 用 b 跳进来 (不是 bl), x30 是脏的 —— 所以 C 侧一律
 *   noreturn + for(;;), 汇编侧另有 adr x30, vector_trap_return 物理兜底.
 *   三道保险全失守时, ret 也只会落到死循环, 不会跳垃圾地址造成嵌套异常.
 *──────────────────────────────────────────────────────────────────── */
__attribute__((noreturn)) void trap_from_el0_sync(unsigned int vec)
{
    raw_puts("\r\n!!! SYNC from EL0 — 内核还没建用户态, 不该走到这儿 !!!\r\n");
    raw_puts("!!! 若 CurrentEL=1 却取到组1向量, 看上面 SPSR.M: 5=EL1h(编号判错) 0=EL0t(摆位失败) !!!\r\n");
    trap_entry(vec);
}

__attribute__((noreturn)) void trap_from_el0(unsigned int vec)
{
    raw_puts("\r\n!!! 异常来自 EL0, 但内核还没建用户态 !!!\r\n");
    trap_entry(vec);
}

__attribute__((noreturn)) void trap_bad_sp(unsigned int vec)
{
    raw_puts("\r\n!!! SP 配置错误 / 疑似掉进 AArch32 !!!\r\n");
    trap_entry(vec);
}

__attribute__((noreturn)) void trap_sync_el1(unsigned int vec)
{
    /* 2B 只诊断. 2C 起这里接 BRK (0x3C/0x32) 与 SVC (0x15):
     *   ELR += 4; 返回 eret —— 那是内核第一次"崩了还能回来". */
    trap_entry(vec);
}

__attribute__((noreturn)) void trap_irq_el1(unsigned int vec)
{
    raw_puts("\r\n[irq] EL1h IRQ — 2B 未接 GIC, 吊死\r\n");
    trap_entry(vec);
}

__attribute__((noreturn)) void trap_fiq_el1(unsigned int vec)
{
    raw_puts("\r\n[fiq] EL1h FIQ — 2B 未接, 吊死\r\n");
    trap_entry(vec);
}

__attribute__((noreturn)) void trap_serror_el1(unsigned int vec)
{
    raw_puts("\r\n[serror] EL1h SError — 通常是总线/设备配置错误, 最凶的一种\r\n");
    raw_puts("         常见来源: 访问未使能时钟的设备的寄存器、GIC 没配好、非法 MAIR 属性\r\n");
    trap_entry(vec);
}
