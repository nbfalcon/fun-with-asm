#include "base.h"

#include <asm/unistd.h>

.text
.global _start
_start:
	la a0, s_message
	jal strlen
	mv a2, a0 # size
	
	li a0, 1 # fd
	la a1, s_message # buf
	li a7, __NR_write
	ecall

	li a0, 0
	li a7, __NR_exit
	ecall
	NORETURN

BEGIN_RODATA
s_message: .string "Hello, World!\n"
