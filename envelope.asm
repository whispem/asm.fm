; asm.fm — envelope.asm
; ADSR envelopes: notes that breathe instead of clicking.
;
; Until now every note was full volume from its first sample to its last,
; so notes started and stopped with an audible click. Real instruments
; shape their volume over time. That shape is the ADSR envelope:
;
;   Attack  : 0 -> full        (the note fades in)
;   Decay   : full -> sustain   (settles down a bit)
;   Sustain : held at sustain    (the body of the note)
;   Release : sustain -> 0      (the note fades out)
;
; We compute an envelope level (0..256) for each sample, then scale the
; oscillator output by it: sample = raw * level / 256. No more clicks.
;
;   nasm -f elf64 envelope.asm -o envelope.o && ld envelope.o -o envelope
;   ./envelope > out.wav && aplay out.wav

section .data
    TRIANGLE equ 2

    ; a short tune, all triangle, so the envelope is easy to hear
    ; C4 E4 G4 C5 E5, quarter notes
    Q equ 11025
    score:
        dq 169, Q, TRIANGLE
        dq 134, Q, TRIANGLE
        dq 112, Q, TRIANGLE
        dq  84, Q, TRIANGLE
        dq  67, Q, TRIANGLE
    score_notes equ 5

    AMP equ 9000

    ; --- ADSR times, in samples (per note) ---
    ; a quarter note is 11025 samples; carve it into phases.
    ATTACK_LEN  equ 1200         ; ~27 ms fade-in
    DECAY_LEN   equ 1800         ; ~40 ms settle
    SUSTAIN_LVL equ 180          ; sustain level out of 256 (~70%)
    RELEASE_LEN equ 2500         ; ~57 ms fade-out
    ; (sustain phase fills whatever time remains before release)

    ; total samples = 5 * Q = 55125 ; data = 110250 ; riff = 36 + 110250
header:
    db "RIFF"
    dd 110286
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
    dd 110250
header_len equ $ - header

    audio: times 110250 db 0

section .text
    global _start

_start:
    lea rsi, [audio]
    lea r15, [score]
    xor r12, r12

.note_loop:
    cmp r12, score_notes
    jge .write

    mov r13, [r15]           ; period
    mov r10, [r15 + 8]       ; duration
    add r15, 24              ; (waveform ignored here; all triangle)

    mov r14, r13
    shr r14, 1

    ; precompute the sample index where release begins:
    ; release_start = duration - RELEASE_LEN
    mov r9, r10
    sub r9, RELEASE_LEN      ; r9 = release_start

    xor rcx, rcx             ; sample index within note
    xor r8, r8              ; oscillator phase

.sample_loop:
    cmp rcx, r10
    jge .next_note

    ; ---- 1) raw triangle sample in eax (range -AMP..+AMP) ----
    cmp r8, r14
    jge .tri_dn
    mov rax, r8
    imul rax, (2*AMP)
    xor rdx, rdx
    div r14
    sub rax, AMP
    jmp .have_raw
.tri_dn:
    mov rax, r8
    sub rax, r14
    imul rax, (2*AMP)
    xor rdx, rdx
    div r14
    mov rbx, AMP
    sub rbx, rax
    mov rax, rbx
.have_raw:
    ; rax = raw sample (signed). keep it in r11.
    mov r11, rax

    ; ---- 2) envelope level (0..256) for this sample index rcx ----
    ; Attack:  rcx < ATTACK_LEN              -> level = rcx*256/ATTACK_LEN
    ; Decay:   rcx < ATTACK_LEN+DECAY_LEN    -> 256 down to SUSTAIN_LVL
    ; Release: rcx >= release_start          -> SUSTAIN_LVL down to 0
    ; Sustain: otherwise                     -> SUSTAIN_LVL
    mov rbx, ATTACK_LEN
    cmp rcx, rbx
    jl .env_attack

    mov rbx, ATTACK_LEN + DECAY_LEN
    cmp rcx, rbx
    jl .env_decay

    cmp rcx, r9              ; release_start
    jge .env_release

    ; sustain
    mov rax, SUSTAIN_LVL
    jmp .have_env

.env_attack:
    ; level = rcx * 256 / ATTACK_LEN
    mov rax, rcx
    shl rax, 8               ; * 256
    xor rdx, rdx
    mov rbx, ATTACK_LEN
    div rbx
    jmp .have_env

.env_decay:
    ; progress p = rcx - ATTACK_LEN, over DECAY_LEN
    ; level = 256 - p*(256 - SUSTAIN_LVL)/DECAY_LEN
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
    jmp .have_env

.env_release:
    ; p = rcx - release_start, over RELEASE_LEN
    ; level = SUSTAIN_LVL - p*SUSTAIN_LVL/RELEASE_LEN  (down to 0)
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
    ; guard against going negative
    test rax, rax
    jns .have_env
    xor rax, rax

.have_env:
    ; rax = envelope level (0..256). scale raw sample: r11 * level / 256
    mov rbx, rax             ; env level
    mov rax, r11             ; raw sample (signed)
    imul rax, rbx            ; raw * level  (signed)
    sar rax, 8               ; / 256  (arithmetic shift keeps sign)

    ; store as 16-bit
    mov [rsi], ax
    add rsi, 2

    ; advance oscillator phase
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
    mov rdx, 110250
    syscall

    mov rax, 60
    xor rdi, rdi
    syscall
