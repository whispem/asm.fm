; asm.fm — melody_smooth.asm  (comparison B: strong ADSR)
; The same solo melody, but each note has a LONG attack and release,
; so you clearly hear it swell in and fade out. No clicks. Compare
; with melody_hard.asm — the difference should be obvious now.
;
;   nasm -f elf64 melody_smooth.asm -o melody_smooth.o && ld melody_smooth.o -o melody_smooth
;   ./melody_smooth > out.wav

section .data
    HALF equ 22050
    AMP  equ 9000
    ; strong, obvious envelope
    ATTACK_LEN  equ 6000         ; ~136 ms swell-in (long, audible)
    DECAY_LEN   equ 2000
    SUSTAIN_LVL equ 200
    RELEASE_LEN equ 9000         ; ~200 ms fade-out (long, audible)
    score:
        dq 169, HALF
        dq 134, HALF
        dq 112, HALF
        dq  84, HALF
        dq  67, HALF
        dq  56, HALF
    notes equ 6
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
section .text
    global _start
_start:
    lea rsi, [audio]
    lea r15, [score]
    xor r12, r12
.nl:
    cmp r12, notes
    jge .w
    mov r13, [r15]
    mov r10, [r15+8]
    add r15, 16
    mov r14, r13
    shr r14, 1
    ; release_start = duration - RELEASE_LEN  -> keep in r9
    mov r9, r10
    sub r9, RELEASE_LEN
    xor rcx, rcx
    xor r8, r8
.sl:
    cmp rcx, r10
    jge .nn
    ; --- raw triangle in r11 ---
    cmp r8, r14
    jge .dn
    mov rax, r8
    imul rax, (2*AMP)
    xor rdx, rdx
    div r14
    sub rax, AMP
    jmp .hr
.dn:
    mov rax, r8
    sub rax, r14
    imul rax, (2*AMP)
    xor rdx, rdx
    div r14
    mov rbx, AMP
    sub rbx, rax
    mov rax, rbx
.hr:
    mov r11, rax
    ; --- envelope level (0..256) in rax ---
    mov rax, ATTACK_LEN
    cmp rcx, rax
    jl .att
    mov rax, ATTACK_LEN+DECAY_LEN
    cmp rcx, rax
    jl .dec
    cmp rcx, r9
    jge .rel
    mov rax, SUSTAIN_LVL
    jmp .he
.att:
    mov rax, rcx
    shl rax, 8
    xor rdx, rdx
    mov rbx, ATTACK_LEN
    div rbx
    jmp .he
.dec:
    mov rax, rcx
    sub rax, ATTACK_LEN
    mov rbx, (256 - SUSTAIN_LVL)
    imul rax, rbx
    xor rdx, rdx
    mov rbx, DECAY_LEN
    div rbx
    mov rbx, 256
    sub rbx, rax
    mov rax, rbx
    jmp .he
.rel:
    mov rax, rcx
    sub rax, r9
    mov rbx, SUSTAIN_LVL
    imul rax, rbx
    xor rdx, rdx
    mov rbx, RELEASE_LEN
    div rbx
    mov rbx, SUSTAIN_LVL
    sub rbx, rax
    mov rax, rbx
    test rax, rax
    jns .he
    xor rax, rax
.he:
    ; scaled = r11 * env / 256
    imul r11, rax
    sar r11, 8
    mov ax, r11w
    mov [rsi], ax
    add rsi, 2
    inc r8
    cmp r8, r13
    jl .nw
    xor r8, r8
.nw:
    inc rcx
    jmp .sl
.nn:
    inc r12
    jmp .nl
.w:
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
