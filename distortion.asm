; asm.fm — distortion.asm
; Distortion / overdrive — push the signal past its limits, crunchy and hot.
;
; A clean wave stays within its range. Distortion deliberately overdrives
; it — multiply it up so it slams into the ceiling, and reshape the peaks
; instead of letting them clip harshly. That reshaping (waveshaping) adds
; harmonics: the more you push, the richer and grittier it gets. It's the
; sound of electric guitars, of overdriven synths, of everything that wants
; to sound HOT rather than polite.
;
; We drive hard, then apply a tanh-like soft clip via a simple curve:
; small signals pass almost linearly, large ones get squashed toward the
; rails — rounding the peaks and generating harmonics. Two passes on one
; note (clean, then driven) so you hear it go from smooth to snarling.
;
;   nasm -f elf64 distortion.asm -o distortion.o && ld distortion.o -o distortion
;   ./distortion > out.wav && aplay out.wav

section .data
    SR   equ 44100
    AMP  equ 7000

    PERIOD equ 150            ; ~294 Hz triangle
    ONE    equ 44100

    ; drive multiplier *256. 256=x1. Big drive -> heavy saturation.
    DRIVE equ 2048            ; x8 — pushes well past the knee for obvious grit
    OUT_AMP equ 9000          ; output ceiling after shaping

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

tri_sample:
    mov r14, PERIOD
    shr r14, 1
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
    jge .driven
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

    ; ---- Pass 2: driven + soft-clipped ----
.driven:
    xor rcx, rcx
    xor r8, r8
.dist:
    cmp rcx, ONE
    jge .write
    call tri_sample          ; rax = clean (-AMP..AMP)

    ; drive: x = x * DRIVE / 256
    imul rax, DRIVE
    sar rax, 8               ; heavily overdriven

    ; soft clip toward +/- OUT_AMP:
    ;   if x >  OUT_AMP  -> pull it back with a rounded knee
    ;   we use: y = OUT_AMP * x / (|x| + OUT_AMP)   (a smooth saturating curve)
    ; this is a classic cheap soft-clipper: linear near 0, asymptotes to rails.
    mov r10, rax             ; x (signed)
    mov r11, rax
    ; |x| in r11
    cmp r11, 0
    jge .abs_ok
    neg r11
.abs_ok:
    ; denom = |x| + OUT_AMP
    add r11, OUT_AMP
    ; num = OUT_AMP * x
    mov rax, OUT_AMP
    imul rax, r10
    ; y = num / denom
    cqo
    idiv r11
    ; clamp (safety)
    cmp rax, 32767
    jle .no_hi
    mov rax, 32767
.no_hi:
    cmp rax, -32768
    jge .no_lo
    mov rax, -32768
.no_lo:
    mov [rsi], ax
    add rsi, 2
    inc r8
    cmp r8, PERIOD
    jl .dw
    xor r8, r8
.dw:
    inc rcx
    jmp .dist

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
