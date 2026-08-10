; asm.fm — oscillators.asm
; All four oscillators: square, sawtooth, triangle, and noise.
;
; Same {period, duration} score as melody, but each note now also
; carries a WAVEFORM. The generator dispatches on it:
;   0 = square    (the 8-bit buzz you already know)
;   1 = sawtooth  (ramps up, snaps down — bright and harsh)
;   2 = triangle  (up then down — soft and round, good for bass)
;   3 = noise      (pseudo-random — no pitch, just percussion)
;
; Noise uses an LFSR (linear-feedback shift register) — the same trick
; the NES and Game Boy used for their drums and explosions.
;
;   nasm -f elf64 oscillators.asm -o oscillators.o && ld oscillators.o -o oscillators
;   ./oscillators > out.wav && aplay out.wav

section .data
    ; waveform ids
    SQUARE   equ 0
    SAW      equ 1
    TRIANGLE equ 2
    NOISE    equ 3

    ; note periods (44100 / freq)
    ; C4=169 D4=150 E4=134 F4=126 G4=112 A4=100 B4=89 C5=84
    QUARTER equ 11025
    HALF    equ 22050

    ; A short demo: the same four notes (C E G C) played on each
    ; waveform in turn, so you can hear the timbres side by side.
    ; Each row: period, duration, waveform
    score:
        ; --- square ---
        dq 169, QUARTER, SQUARE
        dq 134, QUARTER, SQUARE
        dq 112, QUARTER, SQUARE
        dq  84, QUARTER, SQUARE
        ; --- sawtooth ---
        dq 169, QUARTER, SAW
        dq 134, QUARTER, SAW
        dq 112, QUARTER, SAW
        dq  84, QUARTER, SAW
        ; --- triangle ---
        dq 169, QUARTER, TRIANGLE
        dq 134, QUARTER, TRIANGLE
        dq 112, QUARTER, TRIANGLE
        dq  84, QUARTER, TRIANGLE
        ; --- noise (pitch ignored — percussion) ---
        dq 100, QUARTER, NOISE
        dq 100, QUARTER, NOISE
        dq 100, QUARTER, NOISE
        dq 100, QUARTER, NOISE
    score_notes equ 16

    ; total samples = 16 notes * QUARTER = 16 * 11025 = 176400
    ; data bytes = 176400 * 2 = 352800 ; riff = 36 + 352800 = 352836
header:
    db "RIFF"
    dd 352836
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
    dd 352800
header_len equ $ - header

    audio: times 352800 db 0

    ; LFSR state for the noise generator (any non-zero seed)
    lfsr: dq 0xACE1

section .text
    global _start

_start:
    lea rsi, [audio]
    lea r15, [score]
    xor r12, r12              ; note index

.note_loop:
    cmp r12, score_notes
    jge .write

    mov r13, [r15]            ; period
    mov rbx, [r15 + 8]        ; duration
    mov r11, [r15 + 16]       ; waveform id
    add r15, 24               ; advance to next {period, duration, waveform}

    mov r14, r13
    shr r14, 1                ; half period

    xor rcx, rcx             ; sample counter
    xor r8, r8              ; phase (0 .. period-1)

.sample_loop:
    cmp rcx, rbx
    jge .next_note

    ; dispatch on waveform id in r11 -> produce sample in ax
    cmp r11, SQUARE
    je .w_square
    cmp r11, SAW
    je .w_saw
    cmp r11, TRIANGLE
    je .w_triangle
    ; else: noise
    jmp .w_noise

; --- SQUARE: high for first half, low for second ---
.w_square:
    cmp r8, r14
    jl .sq_high
    mov ax, -8000
    jmp .store
.sq_high:
    mov ax, 8000
    jmp .store

; --- SAW: ramp from -8000 to +8000 across the period ---
; value = -8000 + (phase / period) * 16000
;       = (phase * 16000 / period) - 8000
.w_saw:
    mov rax, r8
    imul rax, 16000
    xor rdx, rdx
    div r13                   ; rax = phase*16000 / period  (0 .. 16000)
    sub rax, 8000             ; shift to -8000 .. +8000
    jmp .store

; --- TRIANGLE: up over first half, down over second half ---
.w_triangle:
    cmp r8, r14
    jge .tri_down
.tri_up:
    ; first half: -8000 -> +8000 as phase goes 0 -> half
    ; value = (phase * 16000 / half) - 8000
    mov rax, r8
    imul rax, 16000
    xor rdx, rdx
    div r14                   ; / half
    sub rax, 8000
    jmp .store
.tri_down:
    ; second half: +8000 -> -8000 as phase goes half -> period
    ; let p2 = phase - half ; value = 8000 - (p2 * 16000 / half)
    mov rax, r8
    sub rax, r14              ; p2 = phase - half
    imul rax, 16000
    xor rdx, rdx
    div r14                   ; / half
    mov r9, 8000
    sub r9, rax
    mov rax, r9
    jmp .store

; --- NOISE: LFSR pseudo-random, scaled to +/-8000 ---
.w_noise:
    mov rax, [lfsr]
    ; 16-bit Galois LFSR, taps at bits 0,2,3,5 (0xB400)
    mov r9, rax
    and r9, 1                 ; lowest bit
    shr rax, 1
    test r9, r9
    jz .no_xor
    xor rax, 0xB400
.no_xor:
    mov [lfsr], rax
    ; map low bit of state to +8000 / -8000 (square-ish noise)
    test rax, 1
    jz .noise_low
    mov ax, 8000
    jmp .store
.noise_low:
    mov ax, -8000
    ; fall through to store

.store:
    mov [rsi], ax
    add rsi, 2

    ; advance phase (wrap at period). Noise ignores pitch but we still
    ; step phase harmlessly.
    inc r8
    cmp r8, r13
    jl .no_wrap
    xor r8, r8
.no_wrap:

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
    mov rdx, 352800
    syscall

    mov rax, 60
    xor rdi, rdi
    syscall
