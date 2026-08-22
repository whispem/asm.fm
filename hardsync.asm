; asm.fm — hardsync.asm
; Hard sync — one oscillator resetting another, tearing and aggressive.
;
; Two oscillators: a "master" and a "slave". The slave runs at its own
; (usually higher) frequency, BUT every time the master completes a cycle,
; it forcibly resets the slave's phase back to zero. The slave never gets
; to finish its own cycle — it keeps getting yanked back — and that abrupt
; discontinuity injects a burst of harmonics. The pitch you hear is the
; master's, but the timbre is shaped by the slave's frequency. Sweep the
; slave frequency and you get that screaming, tearing lead — the sound of
; aggressive synth solos and classic hard techno.
;
;   master: fixed frequency, its cycle boundary is the "sync" trigger
;   slave:  higher frequency; on master wrap -> slave phase forced to 0
;   the slave frequency is swept over time so the tearing evolves
;
; 16.16 fixed-point phases for both.
;
;   nasm -f elf64 hardsync.asm -o hardsync.o && ld hardsync.o -o hardsync
;   ./hardsync > out.wav && aplay out.wav

section .data
    SR   equ 44100
    AMP  equ 9000

    TOTAL equ 176400          ; 4 seconds

    MASTER_INC equ 163        ; 110 Hz (the pitch you hear)
    SLAVE_BASE equ 490        ; ~330 Hz center
    SLAVE_SWEEP equ 400
    LFO_STEP_X100000 equ 580  ; ~0.25 Hz slave sweep

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

sine_at:
    mov rax, rdi
    and rax, (SINE_LEN - 1)
    mov rax, [sine + rax*8]
    ret

_start:
    call build_sine

    xor rcx, rcx             ; sample index
    xor r14, r14            ; master phase (16.16)
    xor r15, r15            ; slave phase (16.16)
    xor r13, r13            ; LFO phase
    xor r11, r11            ; LFO frac accumulator
.loop:
    cmp rcx, TOTAL
    jge .write

    ; --- swept slave increment (sine_at uses rdi; we don't keep audio ptr in rdi) ---
    push rcx
    mov rdi, r13
    call sine_at             ; rax = -1000..1000
    pop rcx
    mov r9, SLAVE_SWEEP
    imul r9, rax
    mov rbx, 1000
    mov rax, r9
    cqo
    idiv rbx
    add rax, SLAVE_BASE
    mov r10, rax             ; slave increment this sample

    ; --- advance master; detect cycle wrap (sync trigger) ---
    mov r8d, r14d
    shr r8d, 16              ; old master cycle count
    add r14d, MASTER_INC
    mov r9d, r14d
    shr r9d, 16              ; new master cycle count
    cmp r9d, r8d
    je .no_sync
    xor r15d, r15d           ; SYNC: reset slave phase
.no_sync:

    ; --- advance slave ---
    add r15d, r10d

    ; --- slave sawtooth output (low 16 bits of slave phase) ---
    mov eax, r15d
    and eax, 0xFFFF
    imul eax, (2*AMP)
    shr eax, 16
    sub eax, AMP

    ; clamp & write directly to [audio + rcx*2]
    cmp eax, 32767
    jle .no_hi
    mov eax, 32767
.no_hi:
    cmp eax, -32768
    jge .no_lo
    mov eax, -32768
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
