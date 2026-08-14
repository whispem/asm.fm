; asm.fm — lowpass.asm
; A low-pass filter — carve the highs, warm and mellow.
;
; Every waveform so far was bright and buzzy — a square wave is packed
; with high harmonics. A low-pass filter lets the low frequencies through
; and softens the highs, turning something harsh into something round and
; warm. It's THE synth filter: almost every synth sound passes through one.
;
; The simplest possible version is a one-pole filter — each output sample
; is nudged toward the input, only partway:
;
;   y[n] = y[n-1] + alpha * (x[n] - y[n-1])
;
; alpha in 0..1 is the cutoff. alpha = 1 -> no filtering (output = input).
; alpha small -> the output can only change slowly, so fast wiggles (high
; frequencies) get smoothed away. That's a low-pass.
;
; We demo it on a bright sawtooth: first raw, then filtered, so you hear
; the exact same note lose its harsh edge.
;
;   nasm -f elf64 lowpass.asm -o lowpass.o && ld lowpass.o -o lowpass
;   ./lowpass > out.wav && aplay out.wav

section .data
    SR   equ 44100
    AMP  equ 9000

    ; sawtooth (bright, lots of harmonics -> filter is obvious)
    ; A3 = 246Hz-ish, period 179. One long note, played twice.
    PERIOD equ 179
    ONE    equ 44100          ; 1 second per pass

    ; alpha as a fraction *256. 256 = no filtering. Smaller = more filtering.
    ; 40/256 ≈ 0.156 -> a clearly audible low-pass
    ALPHA equ 40              ; out of 256

    ; total = 2 seconds = 88200 samples ; data = 176400
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

section .text
    global _start

_start:
    lea rsi, [audio]

    ; ---- Pass 1: raw sawtooth (no filter) ----
    xor rcx, rcx
    xor r8, r8               ; phase
.raw:
    cmp rcx, ONE
    jge .filtered
    ; sawtooth: ramps from -AMP to +AMP across the period
    ; sample = (phase * 2*AMP / period) - AMP
    mov rax, r8
    imul rax, (2*AMP)
    xor rdx, rdx
    mov rbx, PERIOD
    div rbx
    sub rax, AMP
    mov [rsi], ax
    add rsi, 2
    inc r8
    cmp r8, PERIOD
    jl .rw
    xor r8, r8
.rw:
    inc rcx
    jmp .raw

    ; ---- Pass 2: same sawtooth, low-pass filtered ----
.filtered:
    xor rcx, rcx
    xor r8, r8               ; phase
    xor r9, r9               ; y[n-1] = filter state (starts at 0)
.filt:
    cmp rcx, ONE
    jge .write
    ; x[n] = raw sawtooth sample
    mov rax, r8
    imul rax, (2*AMP)
    xor rdx, rdx
    mov rbx, PERIOD
    div rbx
    sub rax, AMP             ; rax = x[n] (signed)
    ; y[n] = y[n-1] + alpha*(x[n] - y[n-1])
    ;      = y[n-1] + (ALPHA/256)*(x - y)
    mov r10, rax
    sub r10, r9              ; diff = x - y[n-1]
    imul r10, ALPHA
    sar r10, 8               ; (x-y)*ALPHA/256  (signed)
    add r9, r10              ; y[n] = y[n-1] + that
    ; write y[n]
    mov ax, r9w
    mov [rsi], ax
    add rsi, 2
    inc r8
    cmp r8, PERIOD
    jl .fw
    xor r8, r8
.fw:
    inc rcx
    jmp .filt

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
