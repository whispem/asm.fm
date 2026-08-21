; asm.fm — phaser.asm
; Phaser — moving notches drifting through the spectrum, swirling and psychedelic.
;
; A phaser sounds a bit like a flanger, but it's built completely differently.
; Instead of a delay, it uses a chain of ALLPASS filters — filters that pass
; every frequency at full volume but shift each one's PHASE by a different
; amount. Mix that phase-shifted copy back with the dry signal, and wherever
; they're out of phase they cancel: you get notches in the spectrum. Sweep
; the allpass filters with an LFO and those notches glide up and down — the
; swirling, watery, psychedelic phaser sound (think funk guitar, 70s).
;
; Each allpass stage:  y = -g*x + xh ; xh = x + g*y   (g swept by LFO)
; Chain several stages, mix with dry.
;
;   nasm -f elf64 phaser.asm -o phaser.o && ld phaser.o -o phaser
;   ./phaser > out.wav && aplay out.wav

section .data
    SR   equ 44100
    AMP  equ 8000

    PERIOD equ 200
    TOTAL  equ 220500

    N_STAGES equ 4
    G_MIN equ 100
    G_MAX equ 900
    LFO_STEP_X100000 equ 696

header:
    db "RIFF"
    dd 441036
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
    dd 441000
header_len equ $ - header

    audio: times 441000 db 0
    dry:   times 441000 db 0

    SINE_LEN equ 1024
    sine: times SINE_LEN dq 0
    apx: dq 0, 0, 0, 0

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

    ; --- Phase 1: render dry sawtooth ---
    lea rsi, [dry]
    xor rcx, rcx
    xor r8, r8
.gen:
    cmp rcx, TOTAL
    jge .phase
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

    ; --- Phase 2: phaser (chain of swept allpass stages) ---
    ; register plan (kept stable across the stage loop):
    ;   rcx = sample index      r13 = LFO phase       r11 = LFO frac
    ;   r12 = g (coefficient)   esi/r9 = running signal value
    ;   r8  = stage index       (div uses eax/edx only)
.phase:
    xor rcx, rcx
    xor r13, r13
    xor r11, r11
.loop:
    cmp rcx, TOTAL
    jge .write

    ; --- swept coefficient g from LFO ---
    push rcx
    mov rdi, r13
    call sine_at
    pop rcx
    add rax, 1000
    mov rbx, (G_MAX - G_MIN)
    imul rax, rbx
    mov rbx, 2000
    cqo
    idiv rbx
    add rax, G_MIN
    mov r12, rax             ; g

    ; --- input sample into r9 (running value through the chain) ---
    movsx r9d, word [dry + rcx*2]

    ; --- run through N allpass stages ---
    xor r8, r8               ; stage index
.stage:
    cmp r8, N_STAGES
    jge .stages_done
    ; xh = apx[stage]
    mov r10, [apx + r8*8]    ; xh (previous), signed
    ; y = -g*x/1000 + xh    (x = r9)
    mov eax, r12d
    imul eax, r9d
    mov r14d, 1000
    cdq
    idiv r14d               ; g*x/1000
    neg eax                 ; -g*x/1000
    add eax, r10d           ; y = -g*x/1000 + xh
    mov r15d, eax           ; y (this becomes the stage output)
    ; xh_next = x + g*y/1000
    mov eax, r12d
    imul eax, r15d
    mov r14d, 1000
    cdq
    idiv r14d               ; g*y/1000
    add eax, r9d            ; x + g*y/1000
    mov [apx + r8*8], rax   ; store new xh (sign-extended via rax)
    ; running value for next stage = y
    mov r9d, r15d
    inc r8
    jmp .stage
.stages_done:
    ; output = dry/2 + processed/2   (processed = r9)
    movsx eax, word [dry + rcx*2]
    sar eax, 1
    mov edx, r9d
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
    mov [audio + rcx*2], ax

    inc rcx
    add r11, LFO_STEP_X100000
    cmp r11, 100000
    jl .loop
    sub r11, 100000
    inc r13
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
    mov rdx, 441000
    syscall
    mov rax, 60
    xor rdi, rdi
    syscall
