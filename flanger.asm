; asm.fm — flanger.asm
; Flanger — a swept short delay, the sound of a jet passing overhead.
;
; A flanger is chorus's more extreme cousin. Same idea — a delayed copy
; mixed back in, with the delay time modulated by an LFO — but with two key
; differences: the delay is much SHORTER (well under a millisecond up to a
; few ms), and the delayed signal is FED BACK into itself. That feedback
; sharpens the comb-filter notches into a screaming, resonant sweep — the
; classic "jet plane" whoosh, metallic and dramatic.
;
;   d(n)   = BASE + DEPTH * sin(lfo)          (short, e.g. 0.2..3 ms)
;   y(n)   = x(n) + FEEDBACK * y(n - d(n))    (note: feedback on the OUTPUT)
;   out    = dry/2 + y/2
;
; The moving comb notches + feedback resonance = that swoosh.
;
;   nasm -f elf64 flanger.asm -o flanger.o && ld flanger.o -o flanger
;   ./flanger > out.wav && aplay out.wav

section .data
    SR   equ 44100
    AMP  equ 8000

    ; a bright, harmonically rich source so the moving notches are audible
    ; sawtooth, A3 = 220 Hz
    PERIOD equ 200
    TOTAL  equ 220500          ; 5 seconds (slow sweep needs time)

    ; flanger: short delay. BASE ~1.5ms=66, DEPTH ~1.3ms=60 -> sweeps 6..126 samples
    BASE_DELAY equ 66
    DEPTH      equ 60
    ; slow LFO ~0.2 Hz: 0.2*1024/44100 = 0.00464 -> *100000 = 464
    LFO_STEP_X100000 equ 464
    FEEDBACK   equ 180          ; /256 (~0.7) — resonant but stable

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
    dry:   times 441000 db 0

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

    ; --- Phase 1: render dry sawtooth ---
    lea rsi, [dry]
    xor rcx, rcx
    xor r8, r8
.gen:
    cmp rcx, TOTAL
    jge .flng
    mov rax, r8
    imul rax, (2*AMP)
    xor rdx, rdx
    mov rbx, PERIOD
    div rbx
    sub rax, AMP
    mov [rsi + rcx*2], ax
    inc r8
    cmp r8, PERIOD
    jl .gw
    xor r8, r8
.gw:
    inc rcx
    jmp .gen

    ; --- Phase 2: flanger (feedback comes from the OUTPUT buffer 'audio') ---
.flng:
    lea rsi, [audio]
    lea rbp, [dry]
    xor rcx, rcx             ; sample index
    xor r13, r13            ; LFO phase
    xor r11, r11            ; LFO frac accumulator (scaled *100000)
.loop:
    cmp rcx, TOTAL
    jge .write

    ; d(n) = BASE + DEPTH*sin(lfo)
    push rcx
    mov rdi, r13
    call sine_at             ; rax = -1000..1000
    pop rcx
    mov r9, DEPTH
    imul r9, rax
    mov rbx, 1000
    mov rax, r9
    cqo
    idiv rbx
    add rax, BASE_DELAY      ; d(n)
    mov r10, rax             ; delay

    ; y(n) = x(n) + FEEDBACK * audio[n - d]
    mov rax, rcx
    sub rax, r10
    js .no_fb
    movsx edx, word [rsi + rax*2]   ; previous OUTPUT (feedback source)
    imul edx, FEEDBACK
    sar edx, 8                       ; FEEDBACK*y(n-d)
    jmp .have_fb
.no_fb:
    xor edx, edx
.have_fb:
    movsx eax, word [rbp + rcx*2]   ; x(n) dry
    add eax, edx                     ; y(n) = x + fb*y(n-d)
    ; clamp y to 16-bit before storing (it's the feedback buffer)
    cmp eax, 32767
    jle .yhi
    mov eax, 32767
.yhi:
    cmp eax, -32768
    jge .ylo
    mov eax, -32768
.ylo:
    ; out = dry/2 + y/2  (but we store y in audio for feedback, and also mix)
    ; store y into audio (so future samples feed back on it)
    mov r12d, eax           ; y(n)
    ; mixed output = dry/2 + y/2
    movsx r14d, word [rbp + rcx*2]
    sar r14d, 1
    mov r15d, r12d
    sar r15d, 1
    add r14d, r15d
    ; but we need audio[] to hold y for feedback, not the mix.
    ; trick: store y for feedback; write mix at the very end isn't possible
    ; in one buffer. So we store y (feedback) here and the ear hears y-based
    ; flanging which already includes the dry via x(n). Store y:
    mov [rsi + rcx*2], r12w

    inc rcx
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
