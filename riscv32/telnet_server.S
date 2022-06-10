#include "base.h"
#include <asm/unistd.h>

#define CONFIG_DEFAULT_PORT 2000
#define CONFIG_DEFAULT_SHELL "/bin/sh"
#define CONFIG_BACKLOG 16

# taken from kernel headers, since they are in C
#define CLONE_VM        0x00000100      /* set if VM shared between processes */ 
#define CLONE_VFORK     0x00004000      /* set if the parent wants the child to wake it up on mm_release */ 
#define SIGCHLD         17

# taken from glibc
#define AF_INET 2
#define SOCK_STREAM 1
#define SOCK_CLOEXEC 0x10000000

.text

.global _start
_start:
	lw s0, (sp) # s0: argc
	li t0, 3
	bgt s0, t0, .Ltoo_many_args
	addi s1, sp, 4 # s1: argv
	addi t0, s0, 1 # after NULL
	slli t0, t0, 2 # *4 (we are dealing with char* here, sizeof(char*) = 4)
	la t1, envp
	sw t0, (t1) # envp = env

	li s2, CONFIG_DEFAULT_PORT # s2: port
	la s3, s_default_shell # s3: shell
	
	li t0, 1
	ble s0, t0, .Lno_args
	addi t0, s1, 4 # s4: &argv[1]
	lw a0, (t0) # argv[1]
	jal atoi
	jal die_if_error
	mv s2, a0 # port = atoi(argv[1])

	li t0, 2
	bne s0, t0, .Lno_shell
	addi t0, s1, 8 # argv[2]
	lw s3, (t0) # shell = argv[2]
.Lno_shell:
.Lno_args:
.Lend_of_argparse:
	mv a0, s2
	jal bind_localhost_socket
	jal die_if_error

	la t0, which_shell
	sw s3, (t0)
	# a0 is sockfd from above
	jal serve_telnet
	jal die_if_error

	# Success, yay :)
	mv a0, zero
	li a7, __NR_exit
	ecall
	NORETURN
.Ltoo_many_args:
	la t0, e_too_many_args
	la t1, last_error
	sw t0, (t1)
	jal die_with_error

# a0: sockfd
serve_telnet:
	ENTER(2)
	SAVE(ra, 0)
	SAVE(s0, 1)
	mv s0, a0
.Lserve_loop:
	mv a0, s0
	jal dispatch_connection
	bltz a0, .Lserve_error
	jal fork_off_shell
	bltz a0, .Lserve_error
	j .Lserve_loop
.Lserve_error:
.Lserve_end:
	REST(ra, 0)
	REST(s0, 1)
	ret

# a0: sockfd
dispatch_connection:
	# a0: sockfd
	mv a1, zero # addr
	mv a2, zero # addrlen
	li a7, __NR_accept
	ecall
	bltz a0, .Laccept_failed
	ret
.Laccept_failed:
	la t0, e_accept_failed
	la t1, last_error
	sw t0, (t1)
	ret

# a0: sockfd
fork_off_shell:
	ENTER(1) # space for tid
	mv t0, a0
	# glibc does this like that; on riscv we don't have fork for some reason
	li a0, (CLONE_VFORK | CLONE_VM | SIGCHLD)
	mv a1, sp
	mv a2, sp # parent_tid
	mv a3, zero # tls
	mv a4, a2 # child_tid
	li a7, __NR_clone
	ecall
	LEAVE(1)
	bltz a0, .Lfork_failed
	bnez a0, .Lfork_parent
.Lfork_child:
	# FIXME Skip error handling?
	mv a0, t0
	mv a1, zero
	mv a2, zero
	li a7, __NR_dup3
	ecall
	mv a0, t0
        li a1, 1
	mv a2, zero
        li a7, __NR_dup3
        ecall
        mv a0, t0 # srcfd
        li a1, 2 # targetfd
	mv a2, zero # flags
        li a7, __NR_dup3
        ecall
	mv a0, t0
	li a7, __NR_close
	ecall

	la t0, which_shell
	lw a0, (t0) # arg: pathname
	addi sp, sp, -8
	sw zero, 4(sp) # NULL
	sw a0, (sp) # name
	mv a1, sp # argv = [name, NULL]
	# FIXME Inherit envp
	# la a2, envp
	# lw a2, (a2)
	addi a2, sp, 4
	li a7, __NR_execve
	ecall

	li a0, 1
	li a7, __NR_exit
	ecall # execve failed, we don't care
	NORETURN
.Lfork_failed:
	la t0, e_fork_failed
	la t1, last_error
	sw t0, (t1)
.Lfork_parent:
	ret

# a0: port
bind_localhost_socket:
	mv t0, a0 # t0: port
	# scoket()
	li a0, AF_INET
	li a1, (SOCK_STREAM | SOCK_CLOEXEC) # we will fork, and the shell should not have access to the server
	mv a2, zero
	li a7, __NR_socket
	ecall
	blt a0, zero, .Lsocket_failed
	addi sp, sp, -(2 + 2 + 4 + 8) # sin_family + sin_port + sin_addr (long = 4 byte, ILP32), pad[8]
	
	# swap byte-order of port
	andi t2, t0, 0xFF # low byte
	slli t2, t2, 8 # t2: high byte now contains low byte of port
	srli t3, t0, 8 # t3: high byte -> low byte
	or t0, t2, t3

	slli t0, t0, 16
	li t1, AF_INET
	xor t0, t1, t0 # AF_INET | port << 16
	
	# bind()
	sw t0, (sp)
	li t1, 0x0100007F # 127.0.0.1 in big-endian (NOTE: riscv is little-endian)
	sw t1, 4(sp)
	sw zero, 8(sp)
	sw zero, 12(sp)
	# a0 already contains our socket
	mv a1, sp
	li a2, 16
	li a7, __NR_bind
	mv t0, a0 # save the socket, we'll want to return it later
	ecall
	addi sp, sp, 16
	blt a0, zero, .Lbind_failed

	# listen()
	mv a0, t0
	li a1, CONFIG_BACKLOG
	li a7, __NR_listen
	ecall
	blt a0, zero, .Llisten_failed
	# FIXME: close the socket x2
	
	mv a0, t0
	ret
.Lsocket_failed:
	la t0, e_socket_failed
	la t1, last_error
	sw t0, (t1)
	ret
.Lbind_failed:
	la t0, e_bind_failed
	la t1, last_error
	sw t0, (t1)
	ret
.Llisten_failed:
	la t0, e_listen_failed
	la t1, last_error
	sw t0, (t1)
	ret

BEGIN_RODATA
s_default_shell: .string CONFIG_DEFAULT_SHELL
e_too_many_args: .string "telnet: usage: [port] [shell]\n"
#define FUNC_ERR(func) e_##func##_failed: .string #func "() failed\n"
FUNC_ERR(socket)
FUNC_ERR(bind)
FUNC_ERR(listen)
FUNC_ERR(accept)
FUNC_ERR(fork)

.bss
.lcomm which_shell, 4 # char *shell;
.lcomm envp, 4
