; asm.fm — polyphony_adsr.asm
; The tracker, now with envelopes: melody + bass + drums, each note
; shaped by an ADSR envelope so nothing clicks.
;
; This is polyphony.asm and envelope.asm combined. Each voice is
; generated with its oscillator AND scaled by a per-note ADSR envelope,
; then summed into the shared buffer. The clicks from hard note edges
; are gone — the mix breathes.
;
;   nasm -f elf64 polyphony_adsr.asm -o polyphony_adsr.o && ld polyphony_adsr.o -o polyphony_adsr
;   ./polyphony_adsr > out.wav && aplay out.wav

section .data
    SQUARE   equ 0
    TRIANGLE equ 2
    NOISE    equ 3

    Q  equ 11025
    H  equ 22050
    E  equ 5512

    AMP equ 5000
    TOTAL_SAMPLES equ 88200

    ; ADSR (samples). Kept short relative to note length.
    ATTACK_LEN  equ 800
    DECAY_LEN   equ 1200
    SUSTAIN_LVL equ 190          ; out of 256
    RELEASE_LEN equ 1500

    ; --- MELODY (triangle) ---
    melody:
        dq 84,  Q, TRIANGLE
        dq 112, Q, TRIANGLE
        dq 100, Q, TRIANGLE
        dq 112, Q, TRIANGLE
        dq 134, Q, TRIANGLE
        dq 112, Q, TRIANGLE
        dq 84,  Q, TRIANGLE
        dq 0,   Q, TRIANGLE
    melody_notes equ 8

    ; --- BASS (square) ---
    bass:
        dq 337, H, SQUARE
        dq 225, H, SQUARE
        dq 337, H, SQUARE
        dq 337, H, SQUARE
    bass_notes equ 4

    ; --- DRUMS (noise) ---
    drums:
        dq 100, E, NOISE
        dq 0,   E, NOISE
        dq 100, E, NOISE
        dq 0,   E, NOISE
        dq 100, E, NOISE
        dq 0,   E, NOISE
        dq 100, E, NOISE
        dq 0,   E, NOISE
        dq 100, E, NOISE
        dq 0,   E, NOISE
        dq 100, E, NOISE
        dq 0,   E, NOISE
        dq 100, E, NOISE
        dq 0,   E, NOISE
        dq 100, E, NOISE
        dq 0,   E, NOISE
    drums_notes equ 16

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
    lfsr: dq 0xACE1

section .text
    global _start

; ------------------------------------------------------------------
; render_track: generate one voice (oscillator + ADSR) and MIX into audio.
;   rdi = score pointer, rsi = note count
; ------------------------------------------------------------------
render_track:
    push rbp
    mov rbp, rsp
    mov r15, rdi
    mov r12, rsi
    lea rbx, [audio]         ; mix pointer (resets per track)

.note_loop:
    test r12, r12
    jz .done

    mov r13, [r15]           ; period
    mov r10, [r15 + 8]       ; duration
    mov r11, [r15 + 16]      ; waveform
    add r15, 24

    mov r14, r13
    shr r14, 1

    ; release_start = duration - RELEASE_LEN  (kept in a scratch slot: use rbp-8)
    mov rax, r10
    sub rax, RELEASE_LEN
    mov [rbp-8], rax         ; store release_start

    xor rcx, rcx             ; sample index in note
    xor r8, r8              ; phase

.sample_loop:
    cmp rcx, r10
    jge .next_note

    ; ---- raw oscillator sample -> r9 (signed, range -AMP..+AMP) ----
    cmp r11, TRIANGLE
    je .o_tri
    cmp r11, NOISE
    je .o_noise
.o_square:
    test r13, r13
    jz .o_sil
    cmp r8, r14
    jl .sq_hi
    mov r9, -AMP
    jmp .have_osc
.sq_hi:
    mov r9, AMP
    jmp .have_osc
.o_tri:
    test r13, r13
    jz .o_sil
    cmp r8, r14
    jge .tri_dn
    mov rax, r8
    imul rax, (2*AMP)
    xor rdx, rdx
    div r14
    sub rax, AMP
    mov r9, rax
    jmp .have_osc
.tri_dn:
    mov rax, r8
    sub rax, r14
    imul rax, (2*AMP)
    xor rdx, rdx
    div r14
    mov rdi, AMP
    sub rdi, rax
    mov r9, rdi
    jmp .have_osc
.o_noise:
    test r13, r13
    jz .o_sil
    mov rax, [lfsr]
    mov rdi, rax
    and rdi, 1
    shr rax, 1
    test rdi, rdi
    jz .n_nox
    xor rax, 0xB400
.n_nox:
    mov [lfsr], rax
    test rax, 1
    jz .n_lo
    mov r9, AMP
    jmp .have_osc
.n_lo:
    mov r9, -AMP
    jmp .have_osc
.o_sil:
    xor r9, r9

.have_osc:
    ; ---- envelope level (0..256) in rax based on rcx ----
    mov rax, ATTACK_LEN
    cmp rcx, rax
    jl .e_att
    mov rax, ATTACK_LEN + DECAY_LEN
    cmp rcx, rax
    jl .e_dec
    mov rax, [rbp-8]         ; release_start
    cmp rcx, rax
    jge .e_rel
    mov rax, SUSTAIN_LVL
    jmp .have_env
.e_att:
    mov rax, rcx
    shl rax, 8
    xor rdx, rdx
    mov rdi, ATTACK_LEN
    div rdi
    jmp .have_env
.e_dec:
    mov rax, rcx
    sub rax, ATTACK_LEN
    mov rdi, (256 - SUSTAIN_LVL)
    imul rax, rdi
    xor rdx, rdx
    mov rdi, DECAY_LEN
    div rdi
    mov rdi, 256
    sub rdi, rax
    mov rax, rdi
    jmp .have_env
.e_rel:
    mov rax, rcx
    sub rax, [rbp-8]
    mov rdi, SUSTAIN_LVL
    imul rax, rdi
    xor rdx, rdx
    mov rdi, RELEASE_LEN
    div rdi
    mov rdi, SUSTAIN_LVL
    sub rdi, rax
    mov rax, rdi
    test rax, rax
    jns .have_env
    xor rax, rax

.have_env:
    ; scaled = r9 (raw) * rax (env) / 256
    imul r9, rax
    sar r9, 8               ; signed /256

    ; ---- mix into buffer with clamp ----
    movsx edx, word [rbx]
    mov eax, r9d
    add eax, edx
    cmp eax, 32767
    jle .no_hi
    mov eax, 32767
.no_hi:
    cmp eax, -32768
    jge .no_lo
    mov eax, -32768
.no_lo:
    mov [rbx], ax
    add rbx, 2

    test r13, r13
    jz .skip_ph
    inc r8
    cmp r8, r13
    jl .skip_ph
    xor r8, r8
.skip_ph:

    inc rcx
    jmp .sample_loop

.next_note:
    dec r12
    jmp .note_loop

.done:
    pop rbp
    ret

_start:
    ; reserve a little stack scratch (release_start) and align
    sub rsp, 16

    lea rdi, [melody]
    mov rsi, melody_notes
    call render_track

    lea rdi, [bass]
    mov rsi, bass_notes
    call render_track

    lea rdi, [drums]
    mov rsi, drums_notes
    call render_track

    add rsp, 16

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
