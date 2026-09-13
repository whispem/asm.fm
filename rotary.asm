; asm.fm — rotary.asm
; Rotary speaker (Leslie) — a spinning voice, the swirl of a Hammond organ.
;
; A Leslie cabinet spins its speakers physically, so the sound reaches your ears
; with a constantly shifting Doppler pitch-wobble AND a tremolo (it gets louder
; as the horn points at you, quieter as it points away). Combine those two — a
; small pitch modulation and an amplitude modulation, both driven by the same
; rotation — and you get that unmistakable swirling, three-dimensional organ
; sound.
;
; Here we simulate one rotor:
;   - a vibrato (Doppler): the read position wobbles with the rotation
;   - a tremolo: the amplitude swells and dips with the same rotation
;   - the amplitude peak is slightly phase-shifted from the pitch peak, which is
;     what makes it feel like it's moving through space rather than just wobbling
;
;   nasm -f elf64 rotary.asm -o rotary.o && ld rotary.o -o rotary
;   ./rotary > out.wav && aplay out.wav

section .data
    SR   equ 44100
    AMP  equ 9000

    ; a sustained organ-ish tone (two detuned-ish partials) at ~220 Hz
    TONE_INC equ 327          ; 16.16 phase inc for ~220 Hz
    TOTAL equ 220500          ; 5 seconds

    ; rotation ~5.5 Hz (typical Leslie "tremolo/fast" speed)
    ; LFO step per sample for the rotation
    ROT_STEP_X100000 equ 12766   ; ~5.5 Hz

    ; depth of the Doppler pitch wobble and the tremolo
    PITCH_DEPTH equ 22        ; how much the phase inc wobbles (16.16 units)
    TREM_DEPTH  equ 380       ; amplitude swing (out of 1000)

header:
    db "RIFF"
    dd 441036
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
    dd 441000
header_len equ $ - header

    audio: times 441000 db 0

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

; sine lookup: rdi = index (any), returns rax in -1000..1000
sine_at:
    mov rax, rdi
    and rax, (SINE_LEN - 1)
    mov rax, [sine + rax*8]
    ret

_start:
    call build_sine

    xor rcx, rcx             ; sample index
    xor r14, r14            ; tone phase (16.16)
    xor r13, r13            ; rotation LFO phase
    xor r11, r11            ; rotation frac accumulator
.loop:
    cmp rcx, TOTAL
    jge .write

    ; --- rotation LFO value (for pitch/Doppler) ---
    push rcx
    mov rdi, r13
    call sine_at             ; rax = -1000..1000  (pitch modulator)
    mov r15, rax             ; save pitch LFO
    ; amplitude LFO: same rotation but phase-shifted by a quarter (256 of 1024)
    mov rdi, r13
    add rdi, 256
    call sine_at             ; rax = -1000..1000 (amp modulator, 90° shifted)
    pop rcx
    mov r12, rax             ; save amp LFO

    ; --- wobble the tone's phase increment (Doppler pitch) ---
    ; inc = TONE_INC + PITCH_DEPTH * pitchLFO / 1000
    mov rax, PITCH_DEPTH
    imul rax, r15
    mov rbx, 1000
    cqo
    idiv rbx
    add rax, TONE_INC        ; wobbled increment
    add r14, rax             ; advance tone phase by wobbled inc

    ; --- generate the tone (a couple of partials for an organ-ish timbre) ---
    ; fundamental
    mov rdi, r14
    shr rdi, 6               ; 16.16 -> table index scale
    call sine_at
    mov r8, rax              ; fundamental
    ; octave partial (2x), quieter
    mov rdi, r14
    shr rdi, 5               ; 2x frequency
    call sine_at
    sar rax, 1               ; half amplitude
    add r8, rax              ; r8 = combined tone (-1500..1500 approx)

    ; scale by AMP/1000 base
    mov rax, r8
    imul rax, AMP
    mov rbx, 1500
    cqo
    idiv rbx                 ; base sample amplitude

    ; --- apply tremolo: amp *= (1000 + TREM_DEPTH*ampLFO/1000) / 1000 ---
    mov r9, TREM_DEPTH
    imul r9, r12             ; TREM_DEPTH * ampLFO
    mov rbx, 1000
    mov r10, r9
    mov rax, r10
    cqo
    idiv rbx                 ; TREM_DEPTH*ampLFO/1000
    add rax, 1000            ; 1000 +/- depth
    mov rbx, rax             ; tremolo factor (around 1000)
    ; sample already in rax? no—reload: we stored base amp; recompute
    ; recompute base amp into r10
    mov rax, r8
    imul rax, AMP
    mov r10, 1500
    cqo
    idiv r10                 ; base amp again
    imul rax, rbx            ; * tremolo factor
    mov rbx, 1000
    cqo
    idiv rbx                 ; /1000

    ; clamp & write
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
    ; advance rotation LFO
    add r11, ROT_STEP_X100000
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
    mov rdx, 441000
    syscall
    mov rax, 60
    xor rdi, rdi
    syscall
