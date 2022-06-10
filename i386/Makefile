all: echo

echo: echo.S
	gcc -m32 -c echo.S -o echo.o
	ld -m elf_i386 echo.o -o echo

.PHONY: clean
clean:
	rm -f echo.o echo
