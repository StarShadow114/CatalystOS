#ifndef ARCH_AARCH64_SYSREGS_H
#define ARCH_AARCH64_SYSREGS_H

/*
 * C 侧系统寄存器封装
 * ⚠ 本文件含 C 语法, 不许被 .S include → 那边用 asm_macros.h
 */
#include <arch/aarch64/asm_macros.h>

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

static inline unsigned long get_current_el(void)
{
    return (read_sysreg(CurrentEL) >> CURRENT_EL_SHIFT) & CURRENT_EL_MASK;
}

static inline unsigned int esr_ec(unsigned long esr)
{
    return (unsigned int)((esr >> ESR_EC_SHIFT) & ESR_EC_MASK);
}

static inline void wfi(void)    { __asm__ volatile ("wfi" : : : "memory"); }
static inline void dsb_sy(void) { __asm__ volatile ("dsb sy" : : : "memory"); }
static inline void isb(void)    { __asm__ volatile ("isb" : : : "memory"); }

#endif /* ARCH_AARCH64_SYSREGS_H */
