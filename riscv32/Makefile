CC=riscv64-linux-gnu-gcc
LD=riscv64-linux-gnu-ld

.PHONY: all
all: hello_world telnet_server

telnet_server: util.o telnet_server.o
	$(LD) -m elf32lriscv_ilp32 telnet_server.o --gc-sections util.o -o telnet_server

hello_world: util.o hello_world.o
	$(LD) -m elf32lriscv_ilp32 hello_world.o --gc-sections util.o -o hello_world

%.o: %.S base.h
	$(CC) -g3 -c $< -o $@ -mabi=ilp32 -march=rv32im -I./include/

.PHONY: clean
clean:
	rm -f *.o
	rm -f hello_world telnet_server
