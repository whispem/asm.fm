; asm.fm — supersaw.asm
; Supersaw — many detuned saws stacked into one huge trance lead.
;
; A single sawtooth is thin. But stack seven of them, each tuned a tiny bit
; sharp or flat of the others, and they drift in and out of phase forever —
; the sound swells, shimmers, and becomes enormous. That's the supersaw,
; the sound that defined late-90s trance (the Roland JP-8000 made it famous).
;
; The trick is just running several saw oscillators at once at slightly
; different frequencies and summing them. The detune spreads them around a
; center pitch; the more voices and the wider the spread, the bigger and
; more restless the sound.
;
; Each voice uses a 16.16 fixed-point phase accumulator so the tiny detune
; ratios actually matter (integer periods are too coarse to detune). The
; LOW 16 bits of the accumulator are the position within the current cycle;
; that's what we turn into the sawtooth ramp.
;
;   nasm -f elf64 supersaw.asm -o supersaw.o && ld supersaw.o -o supersaw
;   ./supersaw > out.wav && aplay out.wav

section .data
    SR   equ 44100
    AMP  equ 2200            ; per-voice amp (x7 ~ 15400 peak, safe)

    N_VOICES equ 7
    TOTAL    equ 176400       ; 4 seconds

    ; per-voice 16.16 phase increments, detuned around 220 Hz.
    ; inc = round(freq * 65536 / SR). 220 Hz -> 327.
    ; detuned by roughly +/-3% in small steps:
    incs: dd 317, 320, 323, 327, 330, 333, 336

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
    ; 7 phase accumulators (16.16), started staggered so they don't all
    ; begin at the same point (avoids one big initial spike)
    phases: dd 0, 9000, 18000, 27000, 36000, 45000, 54000

section .text
    global _start

_start:
    lea rdi, [audio]
    xor rcx, rcx             ; sample index
.loop:
    cmp rcx, TOTAL
    jge .write

    xor r13d, r13d           ; sample accumulator (signed)

    ; --- sum all 7 detuned saw voices ---
    xor rbx, rbx             ; voice index
.voice:
    cmp rbx, N_VOICES
    jge .voices_done
    ; advance this voice's 16.16 phase
    mov eax, [phases + rbx*4]
    add eax, [incs + rbx*4]
    mov [phases + rbx*4], eax

    ; position within the current cycle = LOW 16 bits of phase (0..65535)
    and eax, 0xFFFF          ; <-- the fix: fractional part, not phase>>16
    ; map to -AMP..+AMP : saw = (pos * 2*AMP / 65536) - AMP
    imul eax, (2*AMP)
    shr eax, 16              ; / 65536
    sub eax, AMP             ; -AMP..+AMP
    add r13d, eax            ; accumulate

    inc rbx
    jmp .voice
.voices_done:
    ; clamp (safety) and write
    cmp r13d, 32767
    jle .no_hi
    mov r13d, 32767
.no_hi:
    cmp r13d, -32768
    jge .no_lo
    mov r13d, -32768
.no_lo:
    mov [rdi + rcx*2], r13w

    inc rcx
    jmp .loop

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