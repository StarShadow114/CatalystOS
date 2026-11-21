#ifndef CATALYST_KERNEL_TRAP_H
#define CATALYST_KERNEL_TRAP_H

/*===========================================================================
 * 异常入口 —— 被 arch/aarch64/vectors.S 用 `b` 跳转调用
 *
 * ⚠ 这些函数的唯一调用者是汇编, C 侧看不到任何调用点.
 *   所以 -Wmissing-prototypes 一定会喊, 但绝不能听它建议加 static:
 *   static 让符号不进符号表 → 链接期 undefined symbol (上一轮的坑).
 *   正确做法就是本文件: 把它们声明出来.
 *=========================================================================*/

void trap_entry(unsigned int vec);      /* 总入口: 打印 ESR/ELR/FAR 后吊死 */
void trap_dump_raw(unsigned int vec);   /* 裸诊断: 只打印关键寄存器 */
void trap_from_el0(unsigned int vec);   /* 组 1/3: 异常来自 EL0 */
void trap_from_el0_sync(unsigned int vec);  /* 组1 Sync: 带 ESR/ELR/FAR */
void trap_sync_el1(unsigned int vec);   /* 组 0 Sync: 主力入口 */
void trap_bad_sp(unsigned int vec);     /* 组 2: SP 配置错 / AArch32 不支持 */

/* 组 0 的 IRQ/FIQ/SError: 本课先挂着, 3B 接 GIC 后改成真处理 */
void trap_irq_el1(unsigned int vec);
void trap_fiq_el1(unsigned int vec);
void trap_serror_el1(unsigned int vec);

#endif /* CATALYST_KERNEL_TRAP_H */
