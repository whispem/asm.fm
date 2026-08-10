; asm.fm — melody_hard.asm  (comparison A: NO envelope)
; A solo triangle melody with hard note edges. Listen for the clicks
; at every note change. Compare with melody_smooth.asm.
;
;   nasm -f elf64 melody_hard.asm -o melody_hard.o && ld melody_hard.o -o melody_hard
;   ./melody_hard > out.wav

section .data
    HALF equ 22050            ; long notes (0.5s) so edges are obvious
    AMP  equ 9000
    ; C4 E4 G4 C5 E5 G5, half notes
    score:
        dq 169, HALF
        dq 134, HALF
        dq 112, HALF
        dq  84, HALF
        dq  67, HALF
        dq  56, HALF
    notes equ 6
    ; total = 6*22050 = 132300 ; data = 264600 ; riff = 36+264600
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
    xor rcx, rcx
    xor r8, r8
.sl:
    cmp rcx, r10
    jge .nn
    ; triangle, full amplitude, no envelope
    cmp r8, r14
    jge .dn
    mov rax, r8
    imul rax, (2*AMP)
    xor rdx, rdx
    div r14
    sub rax, AMP
    jmp .st
.dn:
    mov rax, r8
    sub rax, r14
    imul rax, (2*AMP)
    xor rdx, rdx
    div r14
    mov rbx, AMP
    sub rbx, rax
    mov rax, rbx
.st:
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
