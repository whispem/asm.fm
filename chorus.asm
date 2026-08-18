; asm.fm — chorus.asm
; Chorus — one voice becoming many, wide and shimmering.
;
; A delay with a fixed time gives an echo. But if you make the delay very
; short (a few milliseconds) and slowly WOBBLE its length with an LFO, the
; delayed copy drifts slightly sharp then slightly flat against the dry
; signal. Mixed together, the tiny, shifting detune sounds like several
; players on the same note — never perfectly in sync, and that's the
; richness. That's chorus: it takes one voice and makes it a small crowd.
;
;   dry[n]           the original sample
;   delayed[n]       dry[n - d(n)], where d(n) wobbles ~5..15 ms via an LFO
;   out[n] = dry[n]/2 + delayed[n]/2
;
; The wobbling read position is the whole trick — a modulated delay line.
;
;   nasm -f elf64 chorus.asm -o chorus.o && ld chorus.o -o chorus
;   ./chorus > out.wav && aplay out.wav

section .data
    SR   equ 44100
    AMP  equ 8000

    PERIOD equ 200
    TOTAL  equ 132300         ; 3 seconds

    BASE_DELAY equ 441        ; ~10 ms
    DEPTH      equ 220        ; ~5 ms wobble
    LFO_STEP_X1000 equ 19     ; ~0.8 Hz

header:
    db "RIFF"
    dd 264636
    db "WAVE"
    db "fmt "
    dd 16
    dw 1
    dw 1
    dd 44100
    dd 88200
    dw 2
    dw 16
    db "data"
    dd 264600
header_len equ $ - header

    audio: times 264600 db 0
    dry: times 264600 db 0

    SINE_LEN equ 1024
    sine: times SINE_LEN dq 0

section .text
    global _start

build_sine:
    xor rcx, rcx
.loop:
    cmp rcx, SINE_LEN
    jge .done
    mov rax, rcx
    imul rax, 360
    xor rdx, rdx
    mov rbx, SINE_LEN
    div rbx
    mov r8, 1
    cmp rax, 180
    jl .have
    sub rax, 180
    mov r8, -1
.have:
    mov r9, 180
    sub r9, rax
    mov r10, rax
    imul r10, r9
    mov rax, r10
    imul rax, 4000
    mov r11, 40500
    sub r11, r10
    xor rdx, rdx
    div r11
    cmp r8, 0
    jg .store
    neg rax
.store:
    mov [sine + rcx*8], rax
    inc rcx
    jmp .loop
.done:
    ret

sine_at:
    mov rax, rdi
    and rax, (SINE_LEN - 1)
    mov rax, [sine + rax*8]
    ret

_start:
    call build_sine

    ; --- Phase 1: render the dry sawtooth into dry[] ---
    lea rsi, [dry]
    xor rcx, rcx
    xor r8, r8
.gen:
    cmp rcx, TOTAL
    jge .mix
    mov rax, r8
    imul rax, (2*AMP)
    xor rdx, rdx
    mov rbx, PERIOD
    div rbx
    sub rax, AMP
    mov [rsi + rcx*2], ax
    inc r8
    cmp r8, PERIOD
    jl .gw
    xor r8, r8
.gw:
    inc rcx
    jmp .gen

    ; --- Phase 2: chorus — mix dry with a wobbling delayed copy ---
.mix:
    lea rsi, [audio]
    lea rbp, [dry]           ; dry base ptr (kept in rbp, preserved across calls)
    xor rcx, rcx             ; sample index
    xor r13, r13             ; LFO phase
    xor r11, r11             ; LFO frac accumulator
.loop:
    cmp rcx, TOTAL
    jge .write

    ; --- compute wobbling delay d(n) = BASE_DELAY + DEPTH*sin(lfo) ---
    push rcx
    mov rdi, r13
    call sine_at             ; rax = -1000..1000
    pop rcx
    mov r9, DEPTH
    imul r9, rax
    mov rbx, 1000
    mov rax, r9
    cqo
    idiv rbx                 ; rax = DEPTH*sin/1000
    add rax, BASE_DELAY      ; d(n)
    mov r10, rax             ; delay in samples

    ; --- read delayed dry sample: dry[n - d(n)] ---
    mov rax, rcx
    sub rax, r10
    js .silent_delay
    movsx edx, word [rbp + rax*2]
    jmp .have_delay
.silent_delay:
    xor edx, edx
.have_delay:
    movsx eax, word [rbp + rcx*2]
    sar eax, 1
    sar edx, 1
    add eax, edx
    cmp eax, 32767
    jle .no_hi
    mov eax, 32767
.no_hi:
    cmp eax, -32768
    jge .no_lo
    mov eax, -32768
.no_lo:
    mov [rsi + rcx*2], ax

    add r11d, LFO_STEP_X1000
    cmp r11d, 1000
    jl .lfod
    sub r11d, 1000
    inc r13
.lfod:
    inc rcx
    jmp .loop

.write:
    mov rax, 1
    mov rdi, 1
    lea rsi, [header]
    mov rdx, header_len
    syscall
    mov rax, 1
    mov rdi, 1
    lea rsi, [audio]
    mov rdx, 264600
    syscall
    mov rax, 60
    xor rdi, rdi
    syscall
