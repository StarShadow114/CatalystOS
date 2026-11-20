#ifndef ARCH_AARCH64_SYSREGS_H
#define ARCH_AARCH64_SYSREGS_H

/*---------------------------------------------------------------------------
 * 系统寄存器访问封装
 *   "memory" clobber = 编译器屏障: 告诉编译器这条指令可能影响内存,
 *   别把前后的访存乱序挪过去. 碰系统寄存器几乎总要加.
 *-------------------------------------------------------------------------*/

#define read_sysreg(reg)                                \
    ({                                                  \
        unsigned long __v;                              \
        __asm__ volatile ("mrs %0, " #reg : "=r"(__v)); \
        __v;                                            \
    })

#define write_sysreg(reg, val)                          \
    do {                                                \
        __asm__ volatile ("msr " #reg ", %0"            \
                          : : "r"(val) : "memory");     \
    } while (0)

/*---- CurrentEL: EL 域在 bit[3:2] ----*/
#define CURRENT_EL_SHIFT   2
#define CURRENT_EL_MASK    0x3
static inline unsigned long get_current_el(void)
{
    return (read_sysreg(CurrentEL) >> CURRENT_EL_SHIFT) & CURRENT_EL_MASK;
}

/*---- SCTLR_EL1: 总开关 ----*/
#define SCTLR_M    (1UL << 0)     /* MMU enable */
#define SCTLR_A    (1UL << 1)     /* Alignment check */
#define SCTLR_C    (1UL << 2)     /* Data cache */
#define SCTLR_SA   (1UL << 3)     /* Stack alignment check */
#define SCTLR_I    (1UL << 12)    /* Instruction cache */

/*---- HCR_EL2: 虚拟化控制 ----*/
#define HCR_RW     (1UL << 31)    /* 0=EL1 是 AArch32, 1=EL1 是 AArch64 */
#define HCR_TGE    (1UL << 27)    /* Trap general exceptions */

/*---- SPSR_EL2 / SPSR_EL1: 异常返回状态 ----*/
#define SPSR_M_EL1h  0x5          /* EL1, 用 SP_EL1 */
#define SPSR_M_EL0t  0x0          /* EL0, 用 SP_EL0 (t=from AArch32) */
#define SPSR_D       (1UL << 9)   /* Debug 掩码 */
#define SPSR_A       (1UL << 8)   /* SError 掩码 */
#define SPSR_I       (1UL << 7)   /* IRQ 掩码 */
#define SPSR_F       (1UL << 6)   /* FIQ 掩码 */
#define SPSR_DIAGF   (SPSR_D | SPSR_A | SPSR_I | SPSR_F)

/*---- ESR_EL1: 异常综合寄存器 ----*/
#define ESR_EC_SHIFT     26
#define ESR_EC_MASK      0x3F
#define ESR_IL          (1UL << 25)   /* 指令长度: 0=16bit, 1=32bit */
#define ESR_ISS         0x00FFFFFFUL

/* EC 编码表 (常用 7 个, 剩下的遇到再查 ARM ARM D7-2120) */
#define EC_UNKNOWN       0x00
#define EC_WFI_WFE       0x01
#define EC_MRC           0x05
#define EC_SVC_32        0x11
#define EC_SVC_64        0x15
#define EC_HVC_64        0x16
#define EC_IABORT_LOWER  0x20     /* 指令中止, 来自低 EL */
#define EC_IABORT_CUREL  0x21     /* 指令中止, 同一 EL */
#define EC_PC_ALIGN      0x22     /* PC 未对齐 */
#define EC_DABORT_LOWER  0x24     /* 数据中止, 来自低 EL */
#define EC_DABORT_CUREL  0x25     /* 数据中止, 同一 EL */
#define EC_SP_ALIGN      0x26     /* SP 未对齐 */
#define EC_FP_TRAP       0x2C
#define EC_SERROR        0x2F
#define EC_BRK           0x3C     /* 软件断点 */
#define EC_BRK_LOWER     0x38

static inline unsigned int esr_ec(unsigned long esr)
{
    return (unsigned int)((esr >> ESR_EC_SHIFT) & ESR_EC_MASK);
}

/*---- 小而有用的原语 ----*/
static inline void wfi(void)
{
    __asm__ volatile ("wfi" : : : "memory");
}

static inline void dsb_sy(void)
{
    __asm__ volatile ("dsb sy" : : : "memory");
}

static inline void isb(void)
{
    __asm__ volatile ("isb" : : : "memory");
}

#endif /* ARCH_AARCH64_SYSREGS_H */
