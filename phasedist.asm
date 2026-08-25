; asm.fm — phasedist.asm
; Phase distortion synthesis — the Casio CZ trick, bending the read-through
; of a wave.
;
; Casio's CZ synths of the 1980s needed a cheaper alternative to Yamaha's FM.
; Their answer: phase distortion. Take a plain sine oscillator, but instead
; of reading the sine table at a STEADY rate, warp the phase as you go —
; speed through part of the cycle, crawl through another. The output is still
; built from a sine, but the warping bends its shape toward a saw or a
; resonant pulse, and sweeping the warp amount morphs the timbre. It's a
; close cousin of FM: both distort phase to enrich the spectrum, but this one
; is a single reshaped read.
;
; The warp: split the phase at a moveable "knee". Below the knee, run fast;
; above it, run slow (or vice versa). As the knee moves, the waveform
; smoothly deforms. We sweep the knee with an LFO so you hear the morph.
;
;   nasm -f elf64 phasedist.asm -o phasedist.o && ld phasedist.o -o phasedist
;   ./phasedist > out.wav && aplay out.wav

section .data
    SR   equ 44100
    AMP  equ 11000

    ; 130 Hz. phase increment (16.16) = 130*65536/44100 = 193
    FREQ_INC equ 193
    TOTAL equ 176400          ; 4 seconds

    ; the knee position is swept by an LFO between KNEE_MIN and KNEE_MAX
    ; (expressed as a fraction of the cycle, out of 65536)
    KNEE_MIN equ 8000
    KNEE_MAX equ 58000
    LFO_STEP_X100000 equ 464   ; ~0.2 Hz morph

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

sine_lfo:
    ; sine of phase in rdi (for LFO), returns -1000..1000 in rax
    mov rax, rdi
    and rax, (SINE_LEN - 1)
    mov rax, [sine + rax*8]
    ret

_start:
    call build_sine

    xor rcx, rcx             ; sample index
    xor r14, r14            ; main phase (16.16), 0..65535 in top of low word
    xor r13, r13            ; LFO phase
    xor r11, r11            ; LFO frac accumulator
.loop:
    cmp rcx, TOTAL
    jge .write

    ; --- sweep the knee with LFO ---
    push rcx
    mov rdi, r13
    call sine_lfo             ; rax = -1000..1000
    pop rcx
    ; knee = (KNEE_MIN+KNEE_MAX)/2 + (KNEE_MAX-KNEE_MIN)/2 * sin/1000
    add rax, 1000            ; 0..2000
    mov rbx, (KNEE_MAX - KNEE_MIN)
    imul rax, rbx
    mov rbx, 2000
    cqo
    idiv rbx                 ; (KNEE_MAX-KNEE_MIN)*(sin+1000)/2000
    add rax, KNEE_MIN        ; knee in KNEE_MIN..KNEE_MAX
    mov r12, rax             ; r12 = knee (0..65535)

    ; --- advance main phase ---
    add r14d, FREQ_INC
    ; take the position within the cycle: low 16 bits
    mov r8d, r14d
    and r8d, 0xFFFF          ; p in 0..65535

    ; --- phase distortion: warp p through the knee into p' ---
    ; if p < knee:   p' = p * 32768 / knee                (fast first half)
    ; else:          p' = 32768 + (p-knee)*32768/(65536-knee)   (slow second half)
    ; p' spans 0..65535 but non-linearly -> reshapes the sine read
    cmp r8d, r12d
    jge .above
    ; below knee
    mov eax, r8d
    imul eax, 32768
    cdq
    idiv r12d                ; p*32768/knee
    jmp .have_pp
.above:
    mov eax, r8d
    sub eax, r12d            ; p - knee
    imul eax, 32768
    mov r9d, 65536
    sub r9d, r12d            ; 65536 - knee
    cdq
    idiv r9d                 ; (p-knee)*32768/(65536-knee)
    add eax, 32768           ; + 32768
.have_pp:
    ; eax = p' (0..65535). read sine at (p' >> 6) & 1023
    shr eax, 6
    and eax, (SINE_LEN - 1)
    mov rax, [sine + rax*8]   ; -1000..1000
    ; scale to amplitude
    imul rax, AMP
    mov rbx, 1000
    cqo
    idiv rbx
    ; clamp
    cmp rax, 32767
    jle .no_hi
    mov rax, 32767
.no_hi:
    cmp rax, -32768
    jge .no_lo
    mov rax, -32768
.no_lo:
    mov [audio + rcx*2], ax

    inc rcx
    add r11, LFO_STEP_X100000
    cmp r11, 100000
    jl .loop
    sub r11, 100000
    inc r13
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
