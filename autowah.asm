; asm.fm — autowah.asm
; Auto-wah — a filter that follows the signal's own energy, funky and alive.
;
; A wah pedal sweeps a resonant filter with your foot. An AUTO-wah does it
; automatically: it listens to how loud the signal is right now (an
; "envelope follower") and moves the filter cutoff to match. Loud notes
; snap the filter open and bright; as they fade, the filter closes and
; darkens. The filter tracks the playing itself — that's the funk guitar
; "quack", the envelope-following squelch, alive and responsive.
;
;   env[n]  = envelope follower of |x[n]| (fast attack, slow release)
;   cutoff  = base + env * amount
;   y[n]    = resonant state-variable low-pass at that cutoff
;
; Reuses the state-variable filter from the sweep, but the cutoff comes
; from the signal's OWN loudness instead of an LFO. Each plucked note
; that decays makes the filter open then close — the classic wah quack.
;
;   nasm -f elf64 autowah.asm -o autowah.o && ld autowah.o -o autowah
;   ./autowah > out.wav && aplay out.wav

section .data
    SR   equ 44100
    AMP  equ 7000

    ; plucked notes: a hard attack that DECAYS over the note (so the
    ; envelope — and thus the filter — clearly opens then closes)
    PERIOD equ 150            ; ~294 Hz sawtooth
    NOTE_LEN equ 8820         ; 0.2s note (with internal decay)
    GAP      equ 2205         ; 0.05s gap
    n_pulses equ 8
    TOTAL    equ 88200

    ; envelope follower coefficients (/256): fast attack, slow-ish release
    ENV_ATTACK  equ 40
    ENV_RELEASE equ 6

    F_BASE   equ 25
    F_AMOUNT equ 950
    Q_DAMP   equ 140

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
    dry:   times 176400 db 0

section .text
    global _start

_start:
    ; --- Phase 1: render plucked, decaying notes ---
    lea rsi, [dry]
    xor r12, r12
.pulse_loop:
    cmp r12, n_pulses
    jge .process
    xor r13, r13             ; note sample counter
    xor r8, r8               ; phase
.tone:
    cmp r13, NOTE_LEN
    jge .gap
    ; sawtooth sample
    mov rax, r8
    imul rax, (2*AMP)
    xor rdx, rdx
    mov rbx, PERIOD
    div rbx
    sub rax, AMP             ; raw saw (-AMP..AMP)
    ; apply a linear decay envelope over the note: gain = (NOTE_LEN - r13)/NOTE_LEN
    mov r9, rax              ; saved sample
    mov rax, NOTE_LEN
    sub rax, r13             ; remaining
    imul rax, r9             ; sample * remaining
    xor rdx, rdx
    mov rbx, NOTE_LEN
    ; signed divide
    mov r10, rax
    mov rax, r10
    cqo
    idiv rbx                 ; decayed sample
    mov [rsi], ax
    add rsi, 2
    inc r8
    cmp r8, PERIOD
    jl .nw
    xor r8, r8
.nw:
    inc r13
    jmp .tone
.gap:
    xor r13, r13
.gaploop:
    cmp r13, GAP
    jge .nextp
    mov word [rsi], 0
    add rsi, 2
    inc r13
    jmp .gaploop
.nextp:
    inc r12
    jmp .pulse_loop

    ; --- Phase 2: auto-wah ---
.process:
    xor rcx, rcx
    xor r13, r13            ; envelope
    xor r14, r14            ; lp state
    xor r15, r15            ; bp state
.loop:
    cmp rcx, TOTAL
    jge .write

    movsx r9d, word [dry + rcx*2]

    ; envelope follower
    mov eax, r9d
    cmp eax, 0
    jge .abs_ok
    neg eax
.abs_ok:
    mov r10d, eax           ; |x|
    sub eax, r13d           ; diff
    cmp r10d, r13d
    jg .use_attack
    imul eax, ENV_RELEASE
    sar eax, 8
    jmp .env_upd
.use_attack:
    imul eax, ENV_ATTACK
    sar eax, 8
.env_upd:
    add r13d, eax

    ; cutoff from envelope: f = F_BASE + env*F_AMOUNT/7000
    mov eax, r13d
    imul eax, F_AMOUNT
    mov ebx, 7000
    cdq
    idiv ebx
    add eax, F_BASE
    cmp eax, 950
    jle .f_ok
    mov eax, 950
.f_ok:
    mov r11d, eax

    ; state-variable low-pass
    mov eax, r11d
    imul eax, r15d
    mov ebx, 1000
    cdq
    idiv ebx
    add r14d, eax
    mov eax, Q_DAMP
    imul eax, r15d
    mov ebx, 1000
    cdq
    idiv ebx
    mov r10d, r9d
    sub r10d, r14d
    sub r10d, eax
    mov eax, r11d
    imul eax, r10d
    mov ebx, 1000
    cdq
    idiv ebx
    add r15d, eax
    mov eax, r14d
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
    mov rdx, 176400
    syscall
    mov rax, 60
    xor rdi, rdi
    syscall
