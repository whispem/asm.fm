; asm.fm — bitcrusher.asm
; Bitcrusher — crush the resolution, lo-fi and crunchy.
;
; A 16-bit sample can sit at any of 65,536 levels — smooth and clean.
; A bitcrusher throws most of those levels away. Snap every sample to
; the nearest of only a few dozen levels and the sound turns gritty,
; harsh, digital — the crunch of an old sampler or a cheap toy. (There's
; a lovely irony in degrading a synth that's already 8-bit at heart.)
;
; Two classic ways to crush, both here:
;   1. bit-depth reduction — quantise amplitude to fewer levels
;   2. sample-rate reduction — hold each value for N samples (aliasing)
;
; We play a clean triangle, then the crushed version, so you hear the
; same note fall apart into lo-fi grit.
;
;   nasm -f elf64 bitcrusher.asm -o bitcrusher.o && ld bitcrusher.o -o bitcrusher
;   ./bitcrusher > out.wav && aplay out.wav

section .data
    SR   equ 44100
    AMP  equ 9000

    PERIOD equ 150            ; ~294Hz triangle
    ONE    equ 44100          ; 1 second per pass

    ; bit-depth: keep only STEP-sized amplitude levels.
    ; Bigger STEP = coarser = crunchier. 2000 -> only ~9 levels across the range.
    CRUSH_STEP equ 2000

    ; sample-rate reduction: hold each computed sample for HOLD samples.
    ; HOLD=8 -> effective rate 44100/8 ≈ 5.5kHz (very lo-fi)
    HOLD equ 8

header:
    db "RIFF"
    dd 176436
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
    dd 176400
header_len equ $ - header

    audio: times 176400 db 0

section .text
    global _start

; helper: triangle sample for phase in r8, period PERIOD -> result in rax
tri_sample:
    mov r14, PERIOD
    shr r14, 1               ; half period
    cmp r8, r14
    jge .dn
    mov rax, r8
    imul rax, (2*AMP)
    xor rdx, rdx
    mov rbx, r14
    div rbx
    sub rax, AMP
    ret
.dn:
    mov rax, r8
    sub rax, r14
    imul rax, (2*AMP)
    xor rdx, rdx
    mov rbx, r14
    div rbx
    mov rbx, AMP
    sub rbx, rax
    mov rax, rbx
    ret

_start:
    lea rsi, [audio]

    ; ---- Pass 1: clean triangle ----
    xor rcx, rcx
    xor r8, r8
.clean:
    cmp rcx, ONE
    jge .crushed
    call tri_sample
    mov [rsi], ax
    add rsi, 2
    inc r8
    cmp r8, PERIOD
    jl .cw
    xor r8, r8
.cw:
    inc rcx
    jmp .clean

    ; ---- Pass 2: bit-crushed triangle ----
.crushed:
    xor rcx, rcx
    xor r8, r8
    xor r12, r12             ; hold counter
    xor r13, r13             ; held (crushed) sample value
.crush:
    cmp rcx, ONE
    jge .write

    ; sample-rate reduction: only recompute every HOLD samples
    test r12, r12
    jnz .use_held
    ; compute a fresh sample and crush its bit depth
    call tri_sample          ; rax = clean sample (signed)
    ; bit-depth crush: round to nearest multiple of CRUSH_STEP
    ; q = round(rax / STEP) * STEP  ; do signed division
    mov rbx, CRUSH_STEP
    cqo
    idiv rbx                 ; rax = rax / STEP (truncated toward zero)
    imul rax, CRUSH_STEP     ; back to amplitude, now quantised
    mov r13, rax             ; store held value
.use_held:
    mov ax, r13w
    mov [rsi], ax
    add rsi, 2

    ; advance hold counter (wraps every HOLD)
    inc r12
    cmp r12, HOLD
    jl .nohold
    xor r12, r12
.nohold:

    ; advance oscillator phase
    inc r8
    cmp r8, PERIOD
    jl .kw
    xor r8, r8
.kw:
    inc rcx
    jmp .crush

.write:
    mov rax, 1
    mov rdi, 1
    lea rsi, [header]
    mov rdx, header_len
    syscall
    mov rax, 1
    mov rdi, 1
    lea rsi, [audio]
    mov rdx, 176400
    syscall
    mov rax, 60
    xor rdi, rdi
    syscall
