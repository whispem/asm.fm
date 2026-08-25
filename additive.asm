; asm.fm — additive.asm
; Additive synthesis — building a tone by stacking dozens of sines,
; one harmonic at a time.
;
; Subtractive synthesis starts with a rich waveform and carves it down with
; filters. Additive does the opposite: it BUILDS a sound from nothing but
; pure sine waves, one per harmonic. The fundamental sets the pitch; each
; harmonic above it (2x, 3x, 4x... the frequency) is added in at its own
; amplitude. Choose those amplitudes and you sculpt the timbre directly —
; this is Fourier synthesis, additive from the ground up.
;
; Here we build a sawtooth-like tone the honest way: harmonic n at amplitude
; 1/n (that's literally the Fourier series of a sawtooth). Stack 16 of them
; and a pile of sine waves becomes a bright, buzzy tone — assembled by hand.
;
;   out(t) = sum over n of  (AMP/n) * sin(2*pi*n*f*t)
;
; Each harmonic is just another read into the same sine table at n times
; the phase rate. 16.16 fixed-point phase per harmonic.
;
;   nasm -f elf64 additive.asm -o additive.o && ld additive.o -o additive
;   ./additive > out.wav && aplay out.wav

section .data
    SR   equ 44100
    N_HARM equ 16            ; number of harmonics stacked
    BASE_AMP equ 12000       ; overall amplitude budget (divided among harmonics)

    ; fundamental 110 Hz. base phase increment (16.16) = 110*65536/44100 = 163
    FUND_INC equ 163
    TOTAL equ 176400          ; 4 seconds

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

    SINE_LEN equ 1024
    sine: times SINE_LEN dq 0
    ; one 16.16 phase accumulator per harmonic
    phases: times N_HARM dq 0

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
    mov [sine + rcx*8], rax     ; sine value in -1000..1000
    inc rcx
    jmp .loop
.done:
    ret

_start:
    call build_sine

    xor rcx, rcx             ; sample index
.loop:
    cmp rcx, TOTAL
    jge .write

    xor r13, r13            ; sample accumulator (signed)

    ; --- sum N_HARM harmonics ---
    xor rbx, rbx             ; harmonic index (0-based; harmonic number = rbx+1)
.harm:
    cmp rbx, N_HARM
    jge .harm_done
    ; harmonic number h = rbx+1
    lea r8, [rbx+1]
    ; advance this harmonic's phase by FUND_INC * h
    mov rax, FUND_INC
    imul rax, r8             ; increment for this harmonic
    add [phases + rbx*8], rax
    ; read sine at (phase >> 6) & 1023  -> map 16-bit fractional to 1024-entry table
    mov rax, [phases + rbx*8]
    shr rax, 6               ; 65536 -> 1024 range (16.16 frac has 16 bits; /64 = 10 bits)
    and rax, (SINE_LEN - 1)
    mov r9, [sine + rax*8]   ; sine value -1000..1000
    ; amplitude for this harmonic = BASE_AMP / h  (1/n Fourier weighting)
    mov rax, BASE_AMP
    xor rdx, rdx
    div r8                   ; BASE_AMP / h
    ; contribution = sine * (BASE_AMP/h) / 1000
    imul rax, r9             ; sine * amp
    mov r10, 1000
    mov r11, rax             ; keep
    mov rax, r11
    cqo
    idiv r10                 ; /1000
    add r13, rax             ; accumulate

    inc rbx
    jmp .harm
.harm_done:
    ; clamp & write
    cmp r13, 32767
    jle .no_hi
    mov r13, 32767
.no_hi:
    cmp r13, -32768
    jge .no_lo
    mov r13, -32768
.no_lo:
    mov [audio + rcx*2], r13w

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
