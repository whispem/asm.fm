; asm.fm — pwm.asm
; PWM — pulse-width modulation, the square wave that shivers.
;
; A square wave splits each period into "high" and "low". So far that
; split was always 50/50 — a perfectly even pulse. PWM slowly moves the
; split: 50/50, then 30/70, then 70/30, back and forth. The pitch stays
; the same, but the TIMBRE shifts and shimmers, thick and hollow by turns.
; It's one of the most recognisable analog-synth and chiptune textures.
;
; An LFO (slow sine, reused from the vibrato idea) drives the duty cycle:
;   duty(t) = 50% + depth * sin(2*pi * lfo_rate * t)
; and each sample is "high" if phase < duty*period, else "low".
;
;   nasm -f elf64 pwm.asm -o pwm.o && ld pwm.o -o pwm
;   ./pwm > out.wav && aplay out.wav

section .data
    HALF equ 22050
    AMP  equ 8000

    periods: dq 100, 84, 67, 100
    notes    equ 4

    SR       equ 44100

    LFO_STEP_X1000 equ 70
    DUTY_SWING equ 300

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

    lea rsi, [audio]
    xor r12, r12
    xor r13, r13

.note_loop:
    cmp r12, notes
    jge .write

    mov rbp, [periods + r12*8]

    xor rcx, rcx
    xor r8, r8
    xor r11, r11

.sample_loop:
    cmp rcx, HALF
    jge .next_note

    mov rdi, r13
    call sine_at
    mov r9, DUTY_SWING
    imul r9, rax
    mov rbx, 1000
    mov rax, r9
    cqo
    idiv rbx
    add rax, 500
    mov rbx, rbp
    imul rax, rbx
    mov rbx, 1000
    cqo
    idiv rbx
    mov r10, rax

    cmp r8, r10
    jl .hi
    mov ax, -AMP
    jmp .st
.hi:
    mov ax, AMP
.st:
    mov [rsi], ax
    add rsi, 2

    inc r8
    cmp r8, rbp
    jl .nw
    xor r8, r8
.nw:

    add r11d, LFO_STEP_X1000
    cmp r11d, 1000
    jl .lfod
    sub r11d, 1000
    inc r13
.lfod:

    inc rcx
    jmp .sample_loop

.next_note:
    inc r12
    jmp .note_loop

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
