#pragma once

#define NORETURN ebreak
#define BEGIN_RODATA

#define ENTER(save) addi sp, sp, -(save * 4)
#define LEAVE(save) addi sp, sp, (save * 4)

#define SAVE(reg, n) sw reg, (n * 4)(sp)
#define REST(reg, n) lw reg, (n * 4)(sp)
