; asm.fm — polyphony.asm
; Melody + bass + percussion, all at once. A tiny tracker.
;
; Until now: one note at a time. Now: several voices playing together.
; Sound is additive — to hear two notes at once, you ADD their samples.
; So we generate each voice independently, then mix (sum) them into the
; final buffer. Each voice is quieter (amplitude ~5000) so three of them
; summed stay within the 16-bit range and don't clip.
;
; Three tracks, each its own {period, duration, waveform} score,
; all the same total length (they play simultaneously):
;   - melody : triangle, the tune up top
;   - bass   : square, low notes underneath
;   - drums  : noise, a simple beat
;
;   nasm -f elf64 polyphony.asm -o polyphony.o && ld polyphony.o -o polyphony
;   ./polyphony > out.wav && aplay out.wav

section .data
    SQUARE   equ 0
    TRIANGLE equ 2
    NOISE    equ 3

    ; durations
    Q  equ 11025              ; quarter  (~0.25s)
    H  equ 22050              ; half
    E  equ 5512               ; eighth   (~0.125s)

    ; note periods (44100 / freq)
    ; low octave (bass):  C3=337 E3=268 G3=225
    ; mid octave (melody):C4=169 E4=134 G4=112 A4=100 C5=84
    AMP equ 5000             ; per-voice amplitude (lower, so the mix won't clip)

    ; total length of each track must match. We use 8 quarters = 88200 samples.
    TOTAL_SAMPLES equ 88200

    ; --- MELODY (triangle) : C5 G4 A4 G4 | E4 G4 C5 (rest) ---
    melody:
        dq 84,  Q, TRIANGLE
        dq 112, Q, TRIANGLE
        dq 100, Q, TRIANGLE
        dq 112, Q, TRIANGLE
        dq 134, Q, TRIANGLE
        dq 112, Q, TRIANGLE
        dq 84,  Q, TRIANGLE
        dq 0,   Q, TRIANGLE      ; rest (period 0 = silence)
    melody_notes equ 8

    ; --- BASS (square) : C3 held, G3 held, C3 held, C3 held ---
    bass:
        dq 337, H, SQUARE
        dq 225, H, SQUARE
        dq 337, H, SQUARE
        dq 337, H, SQUARE
    bass_notes equ 4

    ; --- DRUMS (noise) : a hit every eighth note (16 eighths total) ---
    ; alternate a short noise burst with a short rest to make a beat
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

    ; WAV header. data = TOTAL_SAMPLES * 2 = 176400 ; riff = 36 + 176400
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

    ; final mixed audio buffer (16-bit samples), zero-filled
    audio: times 176400 db 0

    lfsr: dq 0xACE1

section .text
    global _start

; ------------------------------------------------------------------
; render_track: mixes one track's samples INTO the audio buffer (adds).
;   input:  rdi = pointer to track score
;           rsi = number of notes in the track
; Uses the buffer `audio` as the shared mix target.
; ------------------------------------------------------------------
render_track:
    push rbp
    mov rbp, rsp
    ; r15 = score pointer, r12 = notes left
    mov r15, rdi
    mov r12, rsi
    lea rbx, [audio]         ; rbx = write/mix pointer into audio (resets per track)

.note_loop:
    test r12, r12
    jz .done

    mov r13, [r15]           ; period
    mov r10, [r15 + 8]       ; duration (samples)
    mov r11, [r15 + 16]      ; waveform
    add r15, 24

    mov r14, r13
    shr r14, 1               ; half period

    xor rcx, rcx             ; sample counter within note
    xor r8, r8              ; phase

.sample_loop:
    cmp rcx, r10
    jge .next_note

    ; produce this voice's sample in ax (signed 16-bit), amplitude AMP
    cmp r11, TRIANGLE
    je .v_triangle
    cmp r11, NOISE
    je .v_noise
    ; else square
.v_square:
    test r13, r13
    jz .v_silence
    cmp r8, r14
    jl .sq_hi
    mov ax, -AMP
    jmp .mix
.sq_hi:
    mov ax, AMP
    jmp .mix

.v_triangle:
    test r13, r13
    jz .v_silence
    cmp r8, r14
    jge .tri_dn
    ; up: -AMP -> +AMP over first half
    mov rax, r8
    imul rax, (2*AMP)
    xor rdx, rdx
    div r14
    sub rax, AMP
    jmp .mix
.tri_dn:
    mov rax, r8
    sub rax, r14
    imul rax, (2*AMP)
    xor rdx, rdx
    div r14
    mov r9, AMP
    sub r9, rax
    mov rax, r9
    jmp .mix

.v_noise:
    test r13, r13
    jz .v_silence
    mov rax, [lfsr]
    mov r9, rax
    and r9, 1
    shr rax, 1
    test r9, r9
    jz .n_noxor
    xor rax, 0xB400
.n_noxor:
    mov [lfsr], rax
    test rax, 1
    jz .n_lo
    mov ax, AMP
    jmp .mix
.n_lo:
    mov ax, -AMP
    jmp .mix

.v_silence:
    xor ax, ax

.mix:
    ; add this voice's sample (ax) to whatever is already in the buffer.
    ; read current 16-bit value, add, write back (signed).
    movsx edx, word [rbx]    ; current mixed value (sign-extended)
    movsx eax, ax            ; this voice's value
    add eax, edx             ; sum
    ; clamp to [-32768, 32767] to be safe
    cmp eax, 32767
    jle .no_hi
    mov eax, 32767
.no_hi:
    cmp eax, -32768
    jge .no_lo
    mov eax, -32768
.no_lo:
    mov [rbx], ax            ; store summed 16-bit sample
    add rbx, 2

    ; advance phase for pitched voices
    test r13, r13
    jz .skip_phase
    inc r8
    cmp r8, r13
    jl .skip_phase
    xor r8, r8
.skip_phase:

    inc rcx
    jmp .sample_loop

.next_note:
    dec r12
    jmp .note_loop

.done:
    pop rbp
    ret

; ------------------------------------------------------------------
_start:
    ; audio buffer starts zero-filled, so each render_track ADDS onto it.
    ; render all three voices into the same buffer -> they mix.

    lea rdi, [melody]
    mov rsi, melody_notes
    call render_track

    lea rdi, [bass]
    mov rsi, bass_notes
    call render_track

    lea rdi, [drums]
    mov rsi, drums_notes
    call render_track

    ; --- write WAV ---
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
