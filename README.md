# About

This repository hosts a few assembly programs I wrote as an excercise, in RV32IM and i386 assembly.

## RISC-V (riscv32/)

- A simple TCP server (`riscv32/telnet_server.S`) that spawns a shell for each new connection
  + CLI Arguments (optional): [port (defaults to 2000)] [shell (defaults to /bin/sh)]
  + Requires RV32IM
- "Hello World" (`riscv32/hello_world.S`)

## i386

- A version of "echo" that also prints argv[0], without argument parsing (`i386/echo`)

# Building

```shell
$ cd $ARCH
$ make all
```

- Each architecture-subdirectory contains a Makefile, which will compile the executables for that architecture
- i386 requires `gcc` and GNU `ld`
- RISC-V requires `riscv64-linux-gnu-` `gcc` and `binutils`
