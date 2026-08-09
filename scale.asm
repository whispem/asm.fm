; asm.fm — scale.asm
; One octave, in tune. C D E F G A B C, each a quarter-second long.
;
; Same square wave as beep, but now driven by a table of periods:
; one entry per note. A note's period (in samples) is 44100 / frequency,
; so higher notes have shorter periods.
;
;   nasm -f elf64 scale.asm -o scale.o && ld scale.o -o scale
;   ./scale > out.wav && aplay out.wav

section .data
    ; --- note periods, in samples (44100 / frequency), rounded ---
    ; C4  D4   E4   F4   G4   A4   B4   C5
    ; 262 294  330  349  392  440  494  523  Hz
    periods:
        dq 169, 150, 134, 126, 112, 100, 89, 84
    note_count equ 8

    ; each note lasts 1/4 second = 11025 samples
    NOTE_SAMPLES equ 11025

    ; total audio = 8 notes * 11025 samples * 2 bytes = 176400 bytes
    ; riff_size   = 36 + 176400 = 176436
header:
    db "RIFF"
    dd 176436                 ; ChunkSize = 36 + data size
    db "WAVE"
    db "fmt "
    dd 16
    dw 1                      ; PCM
    dw 1                      ; mono
    dd 44100                  ; sample rate
    dd 88200                  ; byte rate
    dw 2                      ; block align
    dw 16                     ; bits per sample
    db "data"
    dd 176400                 ; data size in bytes
header_len equ $ - header

    ; audio buffer in .data (Rosetta-safe): 8 * 11025 * 2 = 176400 bytes
    audio: times 176400 db 0

section .text
    global _start

_start:
    ; --- outer loop: walk the notes ---
    ; r12 = note index (0 .. 7)
    ; rsi = write pointer into audio
    lea rsi, [audio]
    xor r12, r12

.note_loop:
    cmp r12, note_count
    jge .write

    ; load this note's period into r13, half-period into r14
    lea rax, [periods]
    mov r13, [rax + r12*8]    ; full period for this note
    mov r14, r13
    shr r14, 1                ; half period = period / 2

    ; --- inner loop: generate NOTE_SAMPLES samples for this note ---
    ; rcx = sample counter within the note (0 .. NOTE_SAMPLES-1)
    ; r8  = phase position within the period (0 .. period-1)
    xor rcx, rcx
    xor r8, r8

.sample_loop:
    cmp rcx, NOTE_SAMPLES
    jge .next_note

    ; high for first half of the period, low for the rest
    cmp r8, r14
    jl .high
.low:
    mov ax, -8000
    jmp .store
.high:
    mov ax, 8000
.store:
    mov [rsi], ax
    add rsi, 2

    inc r8                    ; advance phase
    cmp r8, r13               ; period complete?
    jl .no_wrap
    xor r8, r8               ; reset phase
.no_wrap:

    inc rcx
    jmp .sample_loop

.next_note:
    inc r12
    jmp .note_loop

.write:
    ; write header
    mov rax, 1
    mov rdi, 1
    lea rsi, [header]
    mov rdx, header_len
    syscall

    ; write audio
    mov rax, 1
    mov rdi, 1
    lea rsi, [audio]
    mov rdx, 176400
    syscall

    ; exit(0)
    mov rax, 60
    xor rdi, rdi
    syscall
