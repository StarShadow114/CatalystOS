#include <arch/aarch64/asm_macros.h>

/*===========================================================================
 * 异常向量表 — 16 项 × 128 字节 = 2048 字节, 必须 2KB 对齐
 *
 * 硬件取向量地址: VBAR_EL1 + (组 << 9) + (类型 << 7)
 *   组:   0=EL1h(用SP_EL1)  1=EL0(64位)  2=EL1h(用SP_EL0)  3=EL0(32位)
 *   类型: 0=Sync  1=IRQ  2=FIQ  3=SError
 *
 * 它直接把 VBAR 低 11 位当 0 用, 不检查. 低 11 位非 0 → 跳野地址 → 静默死.
 *=========================================================================*/

.section .text.vectors, "ax"
.global exception_vectors

.align 11                       /* 2^11 = 2048. 写成 10 就是 1KB, 差一位全盘崩 */
exception_vectors:

    /*-------- 组 0: 当前 EL (EL1), 使用 SP_EL1 — 我们唯一会走的路 --------*/
    mov     x0, #0
    adr    x30, vector_trap_return
    b       trap_sync_el1
    .align 7                    /* 2^7 = 128, 一项的大小 */
    mov     x0, #1
    adr    x30, vector_trap_return
    b       trap_irq_el1
    .align 7
    mov     x0, #2
    adr    x30, vector_trap_return
    b       trap_fiq_el1
    .align 7
    mov     x0, #3
    adr    x30, vector_trap_return
    b       trap_serror_el1

    /*-------- 组 1: EL0 (64 位用户态) — 现在没用户态, 占位而已 --------*/
    .rept   4
    mov     x0, #0x10
    adr    x30, vector_trap_return
    b       trap_from_el0
    .align  7
    .endr

    /*-------- 组 2: 当前 EL, 但用 SP_EL0 — 不该发生 --------*/
    .rept   4
    mov     x0, #0x20
    adr    x30, vector_trap_return
    b       trap_bad_sp
    .align  7
    .endr

    /*-------- 组 3: EL0 32 位兼容 — 我们不支持 AArch32 --------*/
    .rept   4
    mov     x0, #0x30
    adr    x30, vector_trap_return
    b       trap_bad_sp
    .align  7
    .endr

/*---------------------------------------------------------------------------
 * ★ C 异常 handler 的"假返回地址"
 *   vectors.S 用 b 进 C (不是 bl): 向量表每项只有 128B, 且不能覆盖 x30
 *   (x30 可能存着被中断程序的返回地址). 代价是被 b 进来的 C 函数 x30 是脏的,
 *   任何 ret 都跳垃圾地址 → 乱执行 → 嵌套异常 → 无限刷屏.
 *   这道保险让 ret 落到这儿的死循环, 而不是垃圾地址.
 *   历史: 没有它时刷屏 1000+ 行, 且顺序错乱 (grep -n -A12 'void trap_dump_raw' kernel/trap.c! 出现在 ═══ 之后).
 *-------------------------------------------------------------------------*/
vector_trap_return:
    wfi
    b       vector_trap_return
