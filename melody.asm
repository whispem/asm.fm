; asm.fm — melody.asm
; A real melody, sequenced by hand: "Au clair de la lune".
;
; Now each note carries a duration as well as a pitch. The tune is a
; list of {period, duration} pairs — a hand-written score. The player
; walks it, and for each note fills `duration` samples of square wave.
;
;   nasm -f elf64 melody.asm -o melody.o && ld melody.o -o melody
;   ./melody > out.wav && aplay out.wav

section .data
    ; --- note periods (44100 / frequency), rounded ---
    ; C4=169  D4=150  E4=134  F4=126  G4=112  A4=100  B4=89  C5=84
    ; a rest is period 0 (silence)

    ; durations in samples: a quarter note = 11025 (~0.25s), half = 22050
    QUARTER equ 11025
    HALF    equ 22050

    ; "Au clair de la lune" — first phrase
    ; C  C  C  D  | E (long) D | C  E  D  D | C (long)
    ; do do do ré | mi         ré| do mi ré ré| do
    ; Each row below is: period, duration
    score:
        dq 169, QUARTER      ; Do
        dq 169, QUARTER      ; Do
        dq 169, QUARTER      ; Do
        dq 150, QUARTER      ; Ré
        dq 134, HALF         ; Mi (long)
        dq 150, HALF         ; Ré (long)
        dq 169, QUARTER      ; Do
        dq 134, QUARTER      ; Mi
        dq 150, QUARTER      ; Ré
        dq 150, QUARTER      ; Ré
        dq 169, HALF         ; Do (long)
    score_notes equ 11

    ; --- WAV header. Data size gets patched at runtime (varies with tune),
    ; but we can precompute it: total samples =
    ;   8*QUARTER + 3*HALF = 8*11025 + 3*22050 = 88200 + 66150 = 154350
    ;   data bytes = 154350 * 2 = 308700
    ;   riff size  = 36 + 308700 = 308736
header:
    db "RIFF"
    dd 308736
    db "WAVE"
    db "fmt "
    dd 16
    dw 1                      ; PCM
    dw 1                      ; mono
    dd 44100
    dd 88200
    dw 2
    dw 16
    db "data"
    dd 308700
header_len equ $ - header

    ; audio buffer in .data (Rosetta-safe): 308700 bytes
    audio: times 308700 db 0

section .text
    global _start

_start:
    ; r12 = note index, rsi = write pointer, r15 = pointer into score
    lea rsi, [audio]
    lea r15, [score]
    xor r12, r12

.note_loop:
    cmp r12, score_notes
    jge .write

    mov r13, [r15]           ; period for this note
    mov rbx, [r15 + 8]       ; duration (samples) for this note
    add r15, 16              ; advance to next {period, duration} pair

    ; half-period in r14 (for the square wave)
    mov r14, r13
    shr r14, 1

    ; inner loop: emit `rbx` samples of this note
    xor rcx, rcx             ; sample counter
    xor r8, r8              ; phase

.sample_loop:
    cmp rcx, rbx
    jge .next_note

    ; if period is 0 -> rest (silence), just write 0
    test r13, r13
    jz .silence

    cmp r8, r14
    jl .high
.low:
    mov ax, -8000
    jmp .store
.high:
    mov ax, 8000
    jmp .store
.silence:
    xor ax, ax               ; 0 = silence

.store:
    mov [rsi], ax
    add rsi, 2

    ; advance phase only for real notes
    test r13, r13
    jz .skip_phase
    inc r8
    cmp r8, r13
    jl .skip_phase
    xor r8, r8
.skip_phase:

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
    mov rdx, 308700
    syscall

    mov rax, 60
    xor rdi, rdi
    syscall
