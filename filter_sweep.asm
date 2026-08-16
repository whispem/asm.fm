; asm.fm — filter_sweep.asm
; A resonant filter sweep — the "wah" that opens and closes.
;
; The one-pole low-pass carved the highs, but gently. Real synth filters
; do two more things: they RESONATE (boost the frequencies right at the
; cutoff into a sharp peak), and they SWEEP (the cutoff moves over time).
; Together that's the "wah", the acid squelch, the sound opening up and
; closing down — the single most expressive gesture in electronic music.
;
; We use a state-variable filter: it keeps two running states (a low-pass
; and a band-pass) and feeds the band-pass back into itself. That feedback
; IS the resonance. An LFO sweeps the cutoff up and down:
;
;   lp += f * bp
;   hp  = in - lp - q * bp
;   bp += f * hp
; where f = cutoff (swept by the LFO) and q sets the resonance.
;
; A bright sawtooth drfrom the filter, cutoff sweeping ~0.5 Hz, high
; resonance — the classic acid line.
;
;   nasm -f elf64 filter_sweep.asm -o filter_sweep.o && ld filter_sweep.o -o filter_sweep
;   ./filter_sweep > out.wav && aplay out.wav

section .data
    SR   equ 44100
    AMP  equ 7000

    PERIOD equ 150            ; ~294 Hz sawtooth (bright source)
    TOTAL  equ 132300         ; 3 seconds (room for the sweep to breathe)

    ; state-variable filter params, fixed point *1000:
    ;   f (cutoff) is swept between F_MIN and F_MAX by the LFO
    ;   q (resonance damping): SMALLER q = MORE resonance. 120 ≈ strong.
    F_MIN equ 30              ; cutoff floor  (0.03)
    F_MAX equ 620             ; cutoff ceil   (0.62)
    Q_DAMP equ 120            ; resonance (out of 1000; smaller = squelchier)

    ; LFO sweep rate ~0.5 Hz : 0.5*1024/44100 ≈ 0.0116 -> *1000 = 12
    LFO_STEP_X1000 equ 12

header:
    db "RIFF"
    dd 264636
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
    dd 264600
header_len equ $ - header

    audio: times 264600 db 0
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

sine_at:
    mov rax, rdi
    and rax, (SINE_LEN - 1)
    mov rax, [sine + rax*8]
    ret

_start:
    call build_sine
    lea rsi, [audio]

    xor rcx, rcx             ; sample counter
    xor r8, r8              ; sawtooth phase
    xor r13, r13            ; LFO phase
    xor r11, r11            ; LFO frac accumulator
    ; filter states (signed, fixed point). kept in r14 (lp), r15 (bp)
    xor r14, r14
    xor r15, r15

.loop:
    cmp rcx, TOTAL
    jge .write

    ; --- input: sawtooth sample (-AMP..AMP) ---
    mov rax, r8
    imul rax, (2*AMP)
    xor rdx, rdx
    mov rbx, PERIOD
    div rbx
    sub rax, AMP
    mov r9, rax              ; r9 = input sample

    ; --- cutoff f, swept by LFO: f = mid + amp*sin ---
    mov rdi, r13
    call sine_at             ; rax = -1000..1000
    ; f = F_MIN + (F_MAX-F_MIN) * (sin+1000)/2000
    add rax, 1000            ; 0..2000
    mov rbx, (F_MAX - F_MIN)
    imul rax, rbx            ; (F_MAX-F_MIN)*(0..2000)
    mov rbx, 2000
    xor rdx, rdx
    div rbx                  ; scaled to 0..(F_MAX-F_MIN)
    add rax, F_MIN           ; rax = f (cutoff, *1000)
    mov r12, rax             ; r12 = f

    ; --- state-variable filter (all fixed point /1000) ---
    ; lp += f * bp / 1000
    mov rax, r12
    imul rax, r15            ; f * bp
    mov rbx, 1000
    cqo
    idiv rbx
    add r14, rax             ; lp += ...
    ; hp = in - lp - q*bp/1000
    mov rax, Q_DAMP
    imul rax, r15            ; q * bp
    mov rbx, 1000
    cqo
    idiv rbx                 ; q*bp/1000
    mov r10, r9              ; in
    sub r10, r14             ; in - lp
    sub r10, rax             ; - q*bp   => hp in r10
    ; bp += f * hp / 1000
    mov rax, r12
    imul rax, r10            ; f * hp
    mov rbx, 1000
    cqo
    idiv rbx
    add r15, rax             ; bp += ...

    ; output = lp (the low-pass tap), clamp to 16-bit
    mov rax, r14
    cmp rax, 32767
    jle .no_hi
    mov rax, 32767
.no_hi:
    cmp rax, -32768
    jge .no_lo
    mov rax, -32768
.no_lo:
    mov [rsi], ax
    add rsi, 2

    ; advance sawtooth phase
    inc r8
    cmp r8, PERIOD
    jl .nw
    xor r8, r8
.nw:
    ; advance LFO
    add r11d, LFO_STEP_X1000
    cmp r11d, 1000
    jl .lfod
    sub r11d, 1000
    inc r13
.lfod:
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
    mov rdx, 264600
    syscall
    mov rax, 60
    xor rdi, rdi
    syscall
