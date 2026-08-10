; asm.fm — fm.asm  ⭐ THE boss fight ⭐
; FM synthesis: the "fm" was never just about radio.
;
; Every oscillator so far had a FIXED frequency. FM synthesis wobbles
; one oscillator's frequency using ANOTHER oscillator. The result is a
; tone rich with harmonics — bells, electric pianos, metallic stabs.
; This is how the Yamaha DX7 and the Sega Genesis made their sounds.
;
; The math, per sample:
;   modulator = sin(2*pi * f_mod * t)
;   carrier   = sin(2*pi * f_car * t  +  I * modulator)
; The modulator is added INTO the carrier's phase. "I" is the modulation
; index — how much wobble. Small I = subtle. Large I = clangorous.
;
; We can't call libc's sin(), so we use a precomputed sine table (1024
; entries) and look values up. Phase is a fixed-point index into it.
;
;   nasm -f elf64 fm.asm -o fm.o && ld fm.o -o fm
;   ./fm > out.wav && aplay out.wav

section .data
    ; note periods -> we actually need frequencies here. carrier freq
    ; for each note (Hz). C4 E4 G4 C5 E5, quarter notes.
    ; freq table (integer Hz is fine for a demo)
    freqs:   dq 262, 330, 392, 523, 659
    notes    equ 5
    Q        equ 11025          ; samples per note

    SR       equ 44100          ; sample rate
    AMP      equ 9000

    ; FM parameters:
    ;   ratio = f_mod / f_car  (harmonic ratio; 1.0 = classic, 2.0 = brighter)
    ;   index = modulation depth
    ; We use ratio = 2 (modulator an octave up) for a bell-ish tone,
    ; and a modulation index that decays over each note (bells shimmer
    ; then settle). Stored as fixed-point *256.
    RATIO_NUM equ 2
    RATIO_DEN equ 1
    INDEX_MAX equ 900           ; peak modulation (in table-index units)

    ; total = 5 * Q = 55125 samples ; data = 110250 ; riff = 36+110250
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

    ; sine table: 1024 entries, amplitude +/-1000 (fixed point), filled at runtime
    SINE_LEN equ 1024
    sine: times SINE_LEN dq 0

section .text
    global _start

; ---- build a 1024-entry sine table, values in -1000..+1000 ----
; We approximate sin without libc using a polynomial (Bhaskara I's
; sine approximation) over 0..180deg and mirror for 180..360.
; Good enough for audio timbre.
build_sine:
    push rbp
    mov rbp, rsp
    xor rcx, rcx              ; i = 0
.loop:
    cmp rcx, SINE_LEN
    jge .done
    ; angle in degrees = i * 360 / 1024
    mov rax, rcx
    imul rax, 360
    xor rdx, rdx
    mov rbx, SINE_LEN
    div rbx                   ; rax = degrees (0..359)
    ; reduce to 0..180 with sign
    mov r8, 1                 ; sign = +1
    cmp rax, 180
    jl .have_angle
    sub rax, 180
    mov r8, -1                ; sign = -1 for 180..360
.have_angle:
    ; Bhaskara: sin(x) ≈ 4x(180-x) / (40500 - x(180-x)), x in degrees
    ; compute p = x*(180-x)
    mov r9, 180
    sub r9, rax               ; 180 - x
    mov r10, rax
    imul r10, r9              ; p = x*(180-x)
    ; numerator = 4 * p * 1000   (scale to +/-1000)
    mov rax, r10
    imul rax, 4000            ; 4*p*1000
    ; denominator = 40500 - p
    mov r11, 40500
    sub r11, r10
    ; value = numerator / denominator
    xor rdx, rdx
    div r11                   ; rax = |sin|*1000
    ; apply sign
    cmp r8, 0
    jg .store
    neg rax
.store:
    mov [sine + rcx*8], rax
    inc rcx
    jmp .loop
.done:
    pop rbp
    ret

; sine lookup: input phase index in rdi (can be big), returns value in rax
; wraps modulo SINE_LEN
sine_at:
    mov rax, rdi
    and rax, (SINE_LEN - 1)   ; mod 1024 (power of two)
    mov rax, [sine + rax*8]
    ret

_start:
    call build_sine

    lea rsi, [audio]          ; write pointer
    xor r12, r12              ; note index

.note_loop:
    cmp r12, notes
    jge .write

    mov r13, [freqs + r12*8]  ; carrier frequency (Hz)

    ; phase accumulators (fixed point *1024/SR handled via increments)
    ; carrier phase increment per sample = f_car * SINE_LEN / SR
    ; modulator phase increment        = f_mod * SINE_LEN / SR
    ;   with f_mod = f_car * RATIO_NUM / RATIO_DEN
    mov rax, r13
    imul rax, SINE_LEN
    xor rdx, rdx
    mov rbx, SR
    div rbx                   ; carrier inc = f_car*1024/SR
    mov r14, rax              ; r14 = carrier increment

    mov rax, r13
    imul rax, RATIO_NUM
    ; f_mod = f_car * ratio
    imul rax, SINE_LEN
    xor rdx, rdx
    mov rbx, SR
    div rbx
    mov r15, rax              ; r15 = modulator increment  (ratio_den=1)

    xor r10, r10             ; carrier phase
    xor r11, r11             ; modulator phase
    xor rcx, rcx             ; sample counter

.sample_loop:
    cmp rcx, Q
    jge .next_note

    ; --- modulation index decays over the note (bell shimmer) ---
    ; index = INDEX_MAX * (Q - rcx) / Q
    mov rax, Q
    sub rax, rcx
    imul rax, INDEX_MAX
    xor rdx, rdx
    mov rbx, Q
    div rbx
    mov r9, rax               ; r9 = current index

    ; --- modulator = sine(modulator_phase) ---
    mov rdi, r11
    call sine_at              ; rax = modulator value (-1000..1000)
    ; modulation offset = index * modulator / 1000  (phase units)
    imul rax, r9
    mov rbx, 1000
    cqo
    idiv rbx                  ; rax = index*mod/1000  (signed phase offset)
    mov r8, rax               ; r8 = phase offset

    ; --- carrier = sine(carrier_phase + offset) ---
    mov rdi, r10
    add rdi, r8               ; carrier phase + modulation
    call sine_at             ; rax = carrier sample (-1000..1000)

    ; scale to amplitude: sample = carrier * AMP / 1000
    imul rax, AMP
    mov rbx, 1000
    cqo
    idiv rbx                  ; rax = final sample (-AMP..AMP)

    mov [rsi], ax
    add rsi, 2

    ; advance phases
    add r10, r14              ; carrier phase += carrier inc
    add r11, r15              ; modulator phase += modulator inc

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
