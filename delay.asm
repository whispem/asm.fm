; asm.fm — delay.asm
; A delay/echo — the sound, coming back to you, fading each time.
;
; Every effect so far shaped a sample using only the present moment.
; A delay needs MEMORY: it plays each sample, then plays it again a
; fraction of a second later, quieter, and again quieter still — an echo.
;
; The trick is a circular buffer (a ring). We keep the last N samples of
; output. For each new sample we add, to the dry signal, a faded copy of
; what we wrote N samples ago:
;
;   out[i] = dry[i] + feedback * out[i - delay_samples]
;
; Reading our own delayed output back in is what makes the echo repeat
; and decay — one line of feedback, many repeats.
;
;   nasm -f elf64 delay.asm -o delay.o && ld delay.o -o delay
;   ./delay > out.wav && aplay out.wav

section .data
    SR   equ 44100
    AMP  equ 9000

    ; a few short, spaced notes so each echo is clearly heard between them
    ; period = 44100/freq : C5=84 E5=67 G5=56 C5=84
    ; short notes (0.15s) followed by the echoes filling the gaps
    QUARTER equ 6615          ; 0.15s note
    GAP     equ 15435         ; 0.35s silence after (room for echoes)
    periods: dq 84, 67, 56, 84
    notes    equ 4

    ; --- delay settings ---
    DELAY_MS   equ 180        ; echo spacing in milliseconds
    ; delay in samples = SR * DELAY_MS / 1000 = 44100*180/1000 = 7938
    DELAY_SAMPLES equ 7938
    ; feedback: how much of the delayed signal is fed back (0..256).
    ; 150/256 ≈ 0.59 -> each echo ~59% as loud, several audible repeats
    FEEDBACK equ 150          ; out of 256

    ; total length: 4 notes * (QUARTER+GAP) = 4 * 22050 = 88200
    TOTAL equ 88200

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

    ; output buffer (also serves as our delay memory — we read back from it)
    audio: times 176400 db 0

section .text
    global _start

_start:
    ; --- Phase 1: render the dry notes into the buffer ---
    lea rsi, [audio]
    xor r12, r12             ; note index

.note_loop:
    cmp r12, notes
    jge .apply_delay

    mov rbp, [periods + r12*8]
    mov r14, rbp
    shr r14, 1               ; half period (triangle)

    ; --- the note (QUARTER samples of triangle) ---
    xor rcx, rcx
    xor r8, r8
.tone:
    cmp rcx, QUARTER
    jge .silence
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
    inc r8
    cmp r8, rbp
    jl .nw
    xor r8, r8
.nw:
    inc rcx
    jmp .tone

.silence:
    ; --- the gap (GAP samples of silence, room for echoes) ---
    xor rcx, rcx
.sil:
    cmp rcx, GAP
    jge .next
    mov word [rsi], 0
    add rsi, 2
    inc rcx
    jmp .sil
.next:
    inc r12
    jmp .note_loop

.apply_delay:
    ; --- Phase 2: apply the echo in place ---
    ; for i from delay..TOTAL:
    ;   audio[i] += FEEDBACK * audio[i - DELAY_SAMPLES] / 256
    ; Processing forward and reading our updated output creates the
    ; repeating, decaying echoes (feedback).
    lea rsi, [audio]
    mov rcx, DELAY_SAMPLES   ; start index i
.echo_loop:
    cmp rcx, TOTAL
    jge .write

    ; delayed = audio[i - DELAY_SAMPLES]
    mov rax, rcx
    sub rax, DELAY_SAMPLES
    movsx edx, word [rsi + rax*2]   ; delayed sample (signed)
    ; faded = delayed * FEEDBACK / 256
    imul edx, FEEDBACK
    sar edx, 8
    ; out = audio[i] + faded  (clamp to 16-bit)
    movsx eax, word [rsi + rcx*2]
    add eax, edx
    cmp eax, 32767
    jle .no_hi
    mov eax, 32767
.no_hi:
    cmp eax, -32768
    jge .no_lo
    mov eax, -32768
.no_lo:
    mov [rsi + rcx*2], ax
    inc rcx
    jmp .echo_loop

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
