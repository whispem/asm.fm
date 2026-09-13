; asm.fm — harmonictrem.asm
; Harmonic tremolo — lows and highs pulsing against each other, liquid and vintage.
;
; A normal tremolo just turns the whole signal up and down. Harmonic tremolo (the
; famous "brownface" Fender circuit) is stranger and lovelier: it splits the sound
; into a low band and a high band, then fades between them out of phase. When the
; lows swell, the highs dip; when the highs swell, the lows dip. The result is a
; watery, phasey pulse that feels like the tone itself is rocking back and forth —
; much more three-dimensional than plain tremolo.
;
;   - split the tone into "lows" (fundamental) and "highs" (upper partials)
;   - one LFO fades them in opposition: low_gain = 0.5+0.5*sin, high_gain = 0.5-0.5*sin
;   - sum them back together
;
;   nasm -f elf64 harmonictrem.asm -o harmonictrem.o && ld harmonictrem.o -o harmonictrem
;   ./harmonictrem > out.wav && aplay out.wav

section .data
    SR   equ 44100
    AMP  equ 8000

    TONE_INC equ 245          ; ~165 Hz fundamental (16.16)
    TOTAL equ 220500          ; 5 seconds

    ; tremolo LFO ~4 Hz
    LFO_STEP_X100000 equ 9286

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

sine_at:
    mov rax, rdi
    and rax, (SINE_LEN - 1)
    mov rax, [sine + rax*8]
    ret

_start:
    call build_sine

    xor rcx, rcx             ; sample index
    xor r14, r14            ; tone phase (16.16)
    xor r13, r13            ; LFO phase
    xor r11, r11            ; LFO frac
.loop:
    cmp rcx, TOTAL
    jge .write

    ; --- build the tone: lows (fundamental) and highs (3rd+5th partials) ---
    ; lows = fundamental
    mov rdi, r14
    shr rdi, 6
    call sine_at
    mov r8, rax              ; lows (-1000..1000)

    ; highs = 3rd partial + 5th partial (brighter content)
    mov rdi, r14
    imul rdi, 3
    shr rdi, 6
    call sine_at
    mov r9, rax
    mov rdi, r14
    imul rdi, 5
    shr rdi, 6
    call sine_at
    add r9, rax
    sar r9, 1                ; average the two highs -> r9 = highs

    ; --- LFO for the opposing fade ---
    push rcx
    mov rdi, r13
    call sine_at             ; rax = -1000..1000
    pop rcx
    mov r15, rax             ; LFO

    ; low_gain  = 500 + LFO/2   (0..1000)
    ; high_gain = 500 - LFO/2
    mov rax, r15
    sar rax, 1               ; LFO/2
    mov rbx, 500
    add rbx, rax             ; low_gain
    mov r10, 500
    sub r10, rax             ; high_gain

    ; lows * low_gain
    mov rax, r8
    imul rax, rbx
    mov rdi, 1000
    cqo
    idiv rdi
    mov r12, rax             ; scaled lows

    ; highs * high_gain
    mov rax, r9
    imul rax, r10
    mov rdi, 1000
    cqo
    idiv rdi
    add r12, rax             ; lows_scaled + highs_scaled

    ; scale to output amplitude
    mov rax, r12
    imul rax, AMP
    mov rdi, 1000
    cqo
    idiv rdi

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
    ; advance tone phase (fixed)
    add r14, TONE_INC
    ; advance LFO
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
    mov rdx, 441000
    syscall
    mov rax, 60
    xor rdi, rdi
    syscall
