#include <arch/aarch64/asm_macros.h>
#include <arch/aarch64/mmio.h>

/*===========================================================================
 * CatalystOS 入口 — EL 降权 + VBAR 安装 + 跳 kernel_main
 *
 * ★ 结构铁律 (违反过的每一条都炸过):
 *   1. el1_common 从标号到 bl kernel_main 是【一条无分支直线】.
 *      诊断校验 (验 EL) 排在全部初始化之后 —— 因为校验失败时的
 *      处置 (panic_hang 打印错误码) 本身依赖 VBAR/栈/UART.
 *      历史: b.eq 夹在 msr vbar 之前 → VBAR 永远 =0 → 黑屏.
 *   2. 碰任何系统寄存器: read-modify-write, 只动理解的位域.
 *      历史: mov x0,#0 覆盖 HCR.RW; 直接写 0 清 SCTLR 踩 RES1.
 *   3. 寄存器分配: x0 = 跨步骤要用的值 (HCR), 换用 x1 做临时.
 *=========================================================================*/

.section .text.boot, "ax"
.global _start

_start:
    msr     DAIFSet, #0xF           /* 关全部异常: 降权途中被 IRQ 打断 = 死 */

    mrs     x0, CurrentEL
    and     x0, x0, #(0x3 << CURRENT_EL_SHIFT)   /* 取 bit[3:2], 不移位: EL1=0x4 EL2=0x8 EL3=0xC */
    cmp     x0, #0xC
    b.eq    drop_from_el3
    cmp     x0, #0x8
    b.eq    drop_from_el2
    cmp     x0, #0x4
    b.eq    el1_common              /* 已在 EL1: 直接进直线初始化 */
    b       panic_bad_el            /* EL0 或乱值 */

/*===========================================================================
 * EL3 → EL2  (QEMU virt 默认不走; 真硬件/ATF 会把你扔在 EL3)
 *=========================================================================*/
drop_from_el3:
    mov     x0, #(1 << 10)          /* SCR_EL3.RW: 低 EL 是 AArch64 */
    orr     x0, x0, #(1 << 0)       /* SCR_EL3.NS: 非安全态 */
    msr     SCR_EL3, x0

    mov     x0, #0x3cd              /* SPSR_EL3: EL2h (M=0b1001) + DAIF 掩码 */
    msr     SPSR_EL3, x0
    adr     x0, drop_from_el2
    msr     ELR_EL3, x0
    isb
    eret

/*===========================================================================
 * EL2 → EL1  — 2B 最凶险的 20 行
 *=========================================================================*/
drop_from_el2:
    /* 第 1 步: 先告诉硬件 "EL1 是 AArch64".
     * ★ 漏了它 eret 后掉进 AArch32, 连报错都没有, 黑屏. */
    mrs     x0, HCR_EL2
    orr     x0, x0, #HCR_RW         /* bit31 */
    msr     HCR_EL2, x0

    /* 第 2 步: EL1 配裸机干净态.
     * ★ 用 x1! x0 里存着刚写好的 HCR, 后面还要用.
     * ★ 读写改写: SCTLR 有 RES1 位, 直接写 0 在真 CPU 上 UNPREDICTABLE. */
    mrs     x1, SCTLR_EL1
    bic     x1, x1, #(SCTLR_M | SCTLR_A | SCTLR_C | SCTLR_SA)
    bic     x1, x1, #SCTLR_I
    msr     SCTLR_EL1, x1

    /* 允许 EL1 用 FP/SIMD, 否则第一条浮点就 trap 回 EL2 */
    msr     CPTR_EL2, xzr

    /* 第 3 步: 返回状态. M[3:0]=0b0101 = EL1h + DAIF 全掩码 */
    mov     x1, #SPSR_EL1h
    msr     SPSR_EL2, x1
    adr     x1, el1_common
    msr     ELR_EL2, x1

    dsb     sy                      /* 保证上面所有 msr 落成 */
    isb                             /* 冲刷流水线, eret 才看得到新值 */
    eret

/*===========================================================================
 * el1_common — ★ 无分支直线, 顺序不可调换
 *=========================================================================*/
el1_common:
    /* ★ 无论从哪条路径进来 (EL3降权/EL2降权/硬件直接给EL1),
     *  都必须显式把 PSTATE 摆成 EL1h + DAIF 全掩码.
     *  历史: 硬件直接给 EL1 时没走 drop_from_el2, SPSR/PSTATE 是复位残值,
     *  第一次异常取到 组1(EL0) 向量, vec=0x10 无限刷屏. */
    msr     DAIFSet, #0xF           /* 再关一次: 降权路径可能已开过 */
    mov     x0, #SPSR_EL1h          /* M[3:0]=0b0101 = EL1h + DAIF 掩码 */
    msr     SPSR_EL1, x0            /* 给"将来从 EL0 返回"打底, 也记录当前态 */

    /* 显式声明当前是 EL1h: 用 eret 自我确认一次 (最稳的摆正手法) */
    adr     x0, 1f
    msr     ELR_EL1, x0
    isb
    eret
1:
    /* ---- ① 装异常向量表: 之后任何指令都可能异常, 所以最先做 ---- */
    ldr     x0, =exception_vectors
    msr     VBAR_EL1, x0
    isb                             /* ★ 漏了它后续取指可能用旧 VBAR(=0) */

    /* ---- ② 清 EL1 状态: 复位值是 IMPLEMENTATION DEFINED ----
     * 实测 QEMU 给 0xc50838 (SA=1, I=1 ...). 不清 = 赌.
     * 没页表却开 M → 取指即炸; 开 A → 莫名的 alignment fault. */
    mrs     x1, SCTLR_EL1
    bic     x1, x1, #(SCTLR_M | SCTLR_A | SCTLR_C | SCTLR_SA)
    msr     SCTLR_EL1, x1
    isb

    /* ---- ③ 设栈: 设完才允许碰栈 / 调 C 函数 ---- */
    ldr     x0, =STACK_TOP
    mov     sp, x0

    /* ---- ④ 点灯: VBAR 的同位探针. 灯亮 = ①②③ 全跑完 ---- */
    mov     x0, #'1'
    bl      uart_putc_fast

    /* ---- ⑤ 验 EL: 纯诊断, 放到最后, 绝不许挡住上面任何一步 ---- */
    mrs     x0, CurrentEL
    and     x0, x0, #(0x3 << CURRENT_EL_SHIFT)
    cmp     x0, #(0x1 << CURRENT_EL_SHIFT)   /* EL1 = 0b01 << 2 = 0x4 */
    b.eq    1f
    ldr     x0, =0xdead0001         /* 不该到 EL1 以外的地方 */
    b       panic_hang
1:
    bl      kernel_main

    /* kernel_main 不该返回 */
    ldr     x0, =0xdead0002
    b       panic_hang

halt:
    wfi
    b       halt

/*---------------------------------------------------------------------------
 * 死在这儿: x0 = 错误码, make trace 能在 qemu.log 里找到
 *   0xdead0001 = EL 校验没过 (不在 EL1)
 *   0xdead0002 = kernel_main 竟然返回了
 *   0xdead0003 = 落到了 EL0
 *-------------------------------------------------------------------------*/
.global panic_hang
panic_hang:
    wfi
    b       panic_hang

panic_bad_el:
    ldr     x0, =0xdead0003
    b       panic_hang

/*---------------------------------------------------------------------------
 * 极简串口输出: 只用 x0/x1/x2, 不碰栈, 不调函数
 *   "没有调试器时的唯一眼睛", 必须绝对安全
 *   ★ tbz #5 = TXFF (Transmit FIFO full); 写成 #4(RXFE) 就丢字符
 *-------------------------------------------------------------------------*/
.global uart_putc_fast
uart_putc_fast:
    ldr     x1, =UART0_FR
1:  ldr     w2, [x1]
    tbz     w2, #5, 2f              /* TXFF=0 → FIFO 有空位 */
    b       1b
2:  ldr     x1, =UART0_DR
    strb    w0, [x1]
    ret
