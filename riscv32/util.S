#include "base.h"
#include <asm/unistd.h>

.text

.global strlen
# a0: s: char*
strlen:
        mv t0, a0
.Lstrlen_loop:
        lb t1, (a0)
        addi a0, a0, 1
        bnez t1, .Lstrlen_loop
        sub a0, a0, t0 # a0 = &s[nul_byte + 1] - s
        addi a0, a0, -1
        ret

.global atoi
# a0: char * (number in decimal)
atoi:
	# a0 = p_cur
	lb t1, (a0) # t1: c = *p_cur
	beqz t1, .Latoi_malformed
	li t3, 10 # * 10
	li t4, '0' # - '0'
	li t5, 0 # >= 0
	li t6, 9 # <= 9
	li t0, 0
.Latoi_loop:
	mul t0, t0, t3 # acc = acc * 10

	sub t1, t1, t3 # t1 = c - '0'
	blt t1, t5, .Latoi_malformed
	bgt t1, t6, .Latoi_malformed
	add t0, t0, t1 # acc = acc * 10 + (c - '0')

	addi a0, a0, 1 # ++p_cur
	lb t1, (a0) # c = *p_cur
	bnez t1, .Latoi_loop # empty string = error
.Latoi_end:
	mv a0, t0
	ret
.Latoi_malformed:
	la t0, e_atoi_invalid
	la t1, last_error
	sw t0, (t1) # last_error = "atoi(): malformed ..."
	li a0, -1
	ret

.global die_if_error
die_if_error:
	la t0, last_error
	lw t0, (t0)
	bnez t0, .Ldie_with_error_print_error
	ret # The happy path
.global die_with_error
die_with_error:
	# No need to save anything, we're done after this
	la t0, last_error
	lw t0, (t0)
	beqz t0, .Ldie_with_error_skip_print
.Ldie_with_error_print_error:
	mv a0, t0 # we wan't to avoid clobbering a0 for die_if_error
	mv s0, t0
	jal strlen
	mv a2, a0 # size
	mv a1, s0 # buf
	li a0, 2 # fd
	li a7, __NR_write
	ecall
.Ldie_with_error_skip_print:
	mv a0, zero
	li a7, __NR_exit
	ecall
	NORETURN

BEGIN_RODATA
e_atoi_invalid: .string "atoi(): malformed input\n"

.bss
.global last_error
.lcomm last_error, 4
