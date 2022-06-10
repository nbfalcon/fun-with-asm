# poor nymph
# This version of echo also prints argv[0], that is the invocation name
# There is no fancy glibc-style argument parsing

#include <sys/syscall.h>

#define BUF_BUF(src, dest) leal 12(src), dest
#define BUF_FD(src) 0(src)
#define BUF_CAPACITY(src) 4(src)
#define BUF_NBYTES(src) 8(src)

#define SAVE(reg) push reg
#define REST(reg) pop reg
#define SYSCALL int $0x80

#define NORETURN int $0x3

#define ENTER pushl %ebp; movl %esp, %ebp
# x86-leave + ret
#define LEAVE movl %ebp, %esp; pop %ebp; ret
# LEAVE and pop nArgs WORD-sized arguments
#define LEAVEP(nArgs) LEAVE $(nArgs * 4)

# name is just for documentation
#define PUSHARG(value, name) push value
#define POPRM(unused_reg) pop unused_reg
#define RVAL(value) movl value, %eax
#define ARGL(n) (8 + (n) * 4)(%ebp)

.text
.global _start
# __cdecl
# 1. argc
# 2. argv...
# 3. envp...
_start:
	ENTER
	movl 4(%ebp), %esi # %esi: argc
	leal 8(%ebp), %edi # %edi: argv (vararg)
	andl $~0xF, %esp # align the stack

	# stack-allocated, 4096-byte buffer
	subl $4108, %esp
	movl %esp, %ebx # %ebx: buf*

	PUSHARG($4096, capacity)
	PUSHARG($1, fd)
	PUSHARG(%ebx, buf)
	call buf_init
	
.L_main_print_argv_loop:
	PUSHARG((%edi), s)
	call strlen
	PUSHARG(%eax, write_size)
	PUSHARG((%edi), write_me)
	PUSHARG(%ebx, buf)
	call buf_write
	
	decl %esi # --argc;
	test %esi, %esi
	jz .Lmain_print_argv_loop_end
	# this is not the last argument, so add a space
	pushl $' ' # arg: write_me
	PUSHARG(%ebx, buf)
	call buf_writec
	addl $4, %edi # argv += 1; pointers are 4-byte sized
	jmp .L_main_print_argv_loop
.Lmain_print_argv_loop_end:

	# Append newline
	pushl $'\n' # write_me
	PUSHARG(%ebx, buf)
	call buf_writec

	# flush()
	PUSHARG(%ebx, buf)
	call buf_flush

	movl $0, %ebx
	movl $SYS_exit, %eax
	SYSCALL
	NORETURN

# __stdcall
# 1. buf: struct buf *
# 2. fd: int > 0
# 3. capacity: uint
buf_init:
	ENTER
	# We don't touch %ebp, no need to save it
	movl ARGL(0), %eax # buf
	movl ARGL(1), %ecx # fd
	movl ARGL(2), %edx # capacity

	movl %ecx, BUF_FD(%eax) # buf->fd = fd
	movl %edx, BUF_CAPACITY(%eax) # buf->capacity = capacity
	movl $0, BUF_NBYTES(%eax)
	
	LEAVEP(3)

# __cdecl
# 1. buf: struct buf *
buf_capacity:
	movl 4(%esp), %ecx
	movl BUF_CAPACITY(%ecx), %eax
	subl BUF_NBYTES(%ecx), %eax
	ret

# __stdcall
# 1. buf: struct buf *
# 2. write_me: byte[]
# 3. write_size: uint
buf_write:
	ENTER
	SAVE(%edi)
	SAVE(%ebx)
	SAVE(%esi)

	movl ARGL(0), %edi # %edi: buf*
	movl ARGL(1), %ebx # %ebx: write_me
	movl ARGL(2), %esi # %esi: write_size

	PUSHARG(%edi, buf)
	call buf_capacity
	POPRM(%ecx)

	test %eax, %esi # capacity vs how much write?
	jl .Lbuf_write_too_large
.Lbuf_write_append_case:
	# capacity is still in %eax
	BUF_BUF(%edi, %ecx) # start of buffer
	movl BUF_NBYTES(%edi), %edx
	addl %edx, %ecx # start of free region
	addl %esi, %edx # nbytes += write_size
	movl %edx, BUF_NBYTES(%edi)

	PUSHARG(%esi, count)
	PUSHARG(%ecx, dest)
	PUSHARG(%ebx, src)	
	call memcpy
	xorl %eax, %eax # success
	jmp .Lbuf_write_end

.Lbuf_write_too_large:
	# writev trick taken from musl libc; this makes the assembler much simpler than an append-write loop
	# 1. buffer iovec (remember: reverse order, since push subtracts from sp)
	movl BUF_NBYTES(%edi), %eax
	pushl %eax # iov_len
	BUF_BUF(%edi, %eax)
	pushl %eax # *iov_base
	# 2. write_me iovec
	pushl %esi
	pushl %ebx
	# writev(args)
	movl BUF_FD(%edi), %ebx # fd
	movl %esp, %ecx # *iov
	movl $2, %edx # iovcnt
	movl $SYS_writev, %eax
	SYSCALL
	# FIXME: return needs to be checked; we at least have a status in %eax
	movl $0, BUF_NBYTES(%edi)

.Lbuf_write_end:
	REST(%esi)
	REST(%ebx)
	REST(%edi)
	LEAVEP(3)

# 1. buf*
# 2. write_me: int
buf_writec:
	ENTER
	movl ARGL(0), %eax

	movl BUF_CAPACITY(%eax), %ecx
	movl BUF_NBYTES(%eax), %edx
	subl %edx, %ecx # free
	jl .Lbuf_writec_flush_path

	# We have some free space to append directly	
	incl BUF_NBYTES(%eax)
	BUF_BUF(%eax, %ecx)
	movl ARGL(1), %eax
	movl %eax, (%ecx, %edx)
	xorl %eax, %eax # return 0
	LEAVEP(2)
.Lbuf_writec_flush_path:
	pushl ARGL(1) # push the char as a 1-byte-buffer
	movl %esp, %ecx # ecx points to char, since this is little-endian mode
	PUSHARG($1, write_size)
	PUSHARG(%ecx, write_me)
	PUSHARG(%eax, buf)
	call buf_write
	LEAVEP(3) # we've pushed ARGL(1)

# __stdcall
# 1. buf: struct buf*
buf_flush:
	ENTER
	movl ARGL(0), %eax
	movl BUF_NBYTES(%eax), %edx # count
	test %edx, %edx
	jz .Lbuf_flush_skip

	SAVE(%ebx)
	BUF_BUF(%eax, %ecx) # *buf
	movl BUF_FD(%eax), %ebx # fd

	SAVE(%eax)
	movl $SYS_write, %eax
	SYSCALL
	# FIXME: error checking?
	REST(%eax)
	movl $0, BUF_NBYTES(%eax) # nbytes = 0, since the buffer should now be empty

	REST(%ebx)
.Lbuf_flush_skip:
	LEAVEP(1)

# __stdcall
# 1. src: byte*
# 2. dest: byte*
# 3. count: uint
memcpy:
	ENTER
	SAVE(%esi)
	SAVE(%edi)

	movl ARGL(0), %esi
	movl ARGL(1), %edi
	movl ARGL(2), %ecx
	rep movsb

	REST(%edi)
	REST(%esi)
	LEAVEP(3)

# __stdcall
# 1. s: char* (byte)
strlen:
	ENTER
	SAVE(%edi)
	
	movl ARGL(0), %edi # %edi: s
	movl %edi, %edx
	movl $0xFFFFFFFF, %ecx # we don't place a bound on strlen (security)
	xorb %al, %al # find nul byte
	cld
	repne scasb # %edi = s + strlen(s)

	# negl %ecx # INT_MAX - %ecx = INT_MAX + -%ecx
	# addl $0xFFFFFFFF, %ecx # INT_MAX - %ecx = how many bytes were scanned
	# decl %ecx
	# movl %ecx, %eax # return strlen(s)
	subl %edx, %edi # s_past_nul - s
	decl %edi # off-by-one
	RVAL(%edi) # return strlen(s)

	REST(%edi)
	LEAVEP(1)
