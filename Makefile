# asm.fm — build all .asm sources into bin/
NASM    := nasm
NASMFLAGS := -f elf64
LD      := ld

SRCS := $(wildcard *.asm)
BINS := $(patsubst %.asm,bin/%,$(SRCS))

all: $(BINS)

bin/%: %.o | bin
	$(LD) $< -o $@

%.o: %.asm
	$(NASM) $(NASMFLAGS) $< -o $@

bin:
	mkdir -p bin

clean:
	rm -f *.o
	rm -rf bin

.PHONY: all clean
