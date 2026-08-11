; asm.fm — tempo.asm
; Configurable tempo (BPM): the same tune, fast or slow.
;
; So far every note length was written in raw samples (11025 = a quarter
; note = 0.25s), which quietly hard-codes the tempo at 120 BPM. Real
; music thinks in beats per minute. This version derives sample counts
; from a BPM value, so one number controls the whole speed.
;
; The arithmetic:
;   a quarter note lasts one beat.
;   seconds per beat = 60 / BPM
;   samples per beat  = SR * 60 / BPM
; then eighth = beat/2, half = beat*2, etc.
;
; Change BPM below and the whole melody speeds up or slows down, in tune,
; with all note ratios preserved.
;
;   nasm -f elf64 tempo.asm -o tempo.o && ld tempo.o -o tempo
;   ./tempo > out.wav && aplay out.wav

section .data
    SR   equ 44100
    AMP  equ 9000

    ; >>> the one knob that controls speed <<<
    BPM  equ 140              ; try 80 (slow) or 200 (fast)

    ; A short tune stored as {period, beats_x4} — beats_x4 is the length
    ; in sixteenths (so 4 = a quarter, 2 = an eighth, 8 = a half).
    ; This keeps note lengths as musical fractions, independent of tempo.
    ; Melody: C4 C4 G4 G4 A4 A4 G4(half)  ("Twinkle" opening)
    ; period = 44100/freq : C4=169 G4=112 A4=100
    score:
        dq 169, 4
        dq 169, 4
        dq 112, 4
        dq 112, 4
        dq 100, 4
        dq 100, 4
        dq 112, 8
    notes equ 7

    ; We size the audio buffer generously and track how many bytes we
    ; actually wrote, then patch the WAV sizes at the end.
    MAXBYTES equ 2000000      ; plenty for a short tune at any sane BPM
    audio: times MAXBYTES db 0

    ; WAV header with placeholder sizes (patched before writing)
header:
    db "RIFF"
riff_size: dd 0
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
data_size: dd 0
header_len equ $ - header

section .text
    global _start

_start:
    ; --- samples per sixteenth note = (SR * 60 / BPM) / 4 ---
    ; = SR * 60 / (BPM * 4) = SR * 15 / BPM
    mov rax, SR
    imul rax, 15
    xor rdx, rdx
    mov rbx, BPM
    div rbx                   ; rax = samples per sixteenth
    mov r9, rax               ; r9 = samples per sixteenth unit

    lea rsi, [audio]
    xor r12, r12             ; note index
    xor r13, r13            ; total samples written (for header)

.note_loop:
    cmp r12, notes
    jge .finish

    ; compute score entry address: score + r12*16 (done via add, scale 16 is invalid)
    mov rax, r12
    shl rax, 4                        ; r12 * 16
    lea rbx, [score]
    add rbx, rax                      ; rbx -> current score entry
    mov rbp, [rbx]                    ; period
    mov r10, [rbx + 8]               ; length in sixteenths

    ; duration in samples = length_sixteenths * samples_per_sixteenth
    mov rax, r10
    imul rax, r9
    mov r10, rax                     ; r10 = note duration in samples

    mov r14, rbp
    shr r14, 1                       ; half period (triangle)

    xor rcx, rcx
    xor r8, r8

.sample_loop:
    cmp rcx, r10
    jge .next_note

    ; triangle sample
    cmp r8, r14
    jge .tri_dn
    mov rax, r8
    imul rax, (2*AMP)
    xor rdx, rdx
    div r14
    sub rax, AMP
    jmp .st
.tri_dn:
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
    add r13, 2               ; count bytes written

    inc r8
    cmp r8, rbp
    jl .nw
    xor r8, r8
.nw:
    inc rcx
    jmp .sample_loop

.next_note:
    inc r12
    jmp .note_loop

.finish:
    ; patch WAV sizes: data_size = r13 ; riff_size = 36 + r13
    mov eax, r13d
    mov [data_size], eax
    add eax, 36
    mov [riff_size], eax

    ; write header
    mov rax, 1
    mov rdi, 1
    lea rsi, [header]
    mov rdx, header_len
    syscall

    ; write audio (r13 bytes)
    mov rax, 1
    mov rdi, 1
    lea rsi, [audio]
    mov rdx, r13
    syscall

    mov rax, 60
    xor rdi, rdi
    syscall
