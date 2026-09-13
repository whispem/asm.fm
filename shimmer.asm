; asm.fm — shimmer.asm
; Shimmer reverb — reflections rising into the light, ambient and celestial.
;
; A normal reverb feeds a decaying echo back on itself to build a tail. Shimmer
; does one magical extra thing: as the reverb tail feeds back, part of it is
; PITCH-SHIFTED UP an octave. So each generation of reflections is higher than
; the last, and the tail doesn't just fade — it rises, blooming into a glowing,
; angelic halo above the note. It's the sound of ambient music, of Eno, of vast
; cathedral-of-light pads.
;
; The octave-up is done cheaply: the shimmer feedback tap reads the reverb buffer
; at HALF the index rate (src = (i - delay)/2), so the stored material plays back
; twice as fast — an octave higher — and feeds back in, climbing each pass.
;
; Feedback gains are kept in check so the tail blooms without running away.
;
;   nasm -f elf64 shimmer.asm -o shimmer.o && ld shimmer.o -o shimmer
;   ./shimmer > out.wav && aplay out.wav

section .data
    SR   equ 44100
    AMP  equ 7000
    TOTAL equ 264600          ; 6 seconds

    notes: dd 327, 490        ; A3, E4 (16.16 incs)
    n_notes equ 2
    NOTE_LEN equ 26460        ; 0.6s pluck each

    REV_DELAY equ 11025       ; 250 ms reverb delay
    REV_FB    equ 820         ; reverb feedback 0.82 (long tail)
    SHIM_DELAY equ 11025      ; shimmer tap delay
    SHIM_FB   equ 520         ; shimmer feedback 0.52 (rising bloom)
    WET       equ 650         ; wet 0.65
    DRY       equ 600         ; dry 0.6

header:
    db "RIFF"
    dd 529236
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
    dd 529200
header_len equ $ - header

    dry:    times 529200 db 0
    audio:  times 529200 db 0
    revbuf: times 529200 db 0
    SINE_LEN equ 1024
    sine: times SINE_LEN dq 0

section .text
    global _start

build_sine:
    xor rcx, rcx
.bl:
    cmp rcx, SINE_LEN
    jge .bd
    mov rax, rcx
    imul rax, 360
    xor rdx, rdx
    mov rbx, SINE_LEN
    div rbx
    mov r8, 1
    cmp rax, 180
    jl .bh
    sub rax, 180
    mov r8, -1
.bh:
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
    jg .bs
    neg rax
.bs:
    mov [sine + rcx*8], rax
    inc rcx
    jmp .bl
.bd:
    ret

sine_at:
    mov rax, rdi
    and rax, (SINE_LEN - 1)
    mov rax, [sine + rax*8]
    ret

_start:
    call build_sine

    ; --- 1) dry plucked notes ---
    xor rcx, rcx
    xor r12, r12
    xor r14, r14
.nl:
    cmp r12, n_notes
    jge .reverb
    mov r13d, [notes + r12*4]
    xor r8, r8
.sp:
    cmp r8, NOTE_LEN
    jge .nn
    add r14, r13
    mov rdi, r14
    shr rdi, 6
    call sine_at
    mov r9, NOTE_LEN
    sub r9, r8
    imul rax, r9
    mov r10, NOTE_LEN
    cqo
    idiv r10
    imul rax, AMP
    mov r10, 1000
    cqo
    idiv r10
    mov [dry + rcx*2], ax
    inc rcx
    inc r8
    jmp .sp
.nn:
    inc r12
    jmp .nl

    ; --- 2) shimmer reverb ---
.reverb:
    xor rcx, rcx
.rl:
    cmp rcx, TOTAL
    jge .mix
    movsx r10, word [dry + rcx*2]  ; acc = dry (sign-extended to 64-bit)

    ; reverb feedback: revbuf[i - REV_DELAY] * REV_FB
    cmp rcx, REV_DELAY
    jl .no_rev
    mov rbx, rcx
    sub rbx, REV_DELAY
    movsx edx, word [revbuf + rbx*2]
    imul edx, REV_FB
    mov edi, 1000
    mov eax, edx
    cdq
    idiv edi
    movsxd rax, eax              ; sign-extend result to 64-bit
    add r10, rax
.no_rev:

    ; shimmer feedback: revbuf[(i - SHIM_DELAY)/2] * SHIM_FB  (octave up)
    cmp rcx, SHIM_DELAY
    jl .no_shim
    mov rbx, rcx
    sub rbx, SHIM_DELAY
    shr rbx, 1                   ; half-rate read => octave up
    movsx edx, word [revbuf + rbx*2]
    imul edx, SHIM_FB
    mov edi, 1000
    mov eax, edx
    cdq
    idiv edi
    movsxd rax, eax             ; sign-extend result to 64-bit
    add r10, rax
.no_shim:

    ; clamp and store
    mov rax, r10
    cmp rax, 32767
    jle .rc_hi
    mov rax, 32767
.rc_hi:
    cmp rax, -32768
    jge .rc_lo
    mov rax, -32768
.rc_lo:
    mov [revbuf + rcx*2], ax
    inc rcx
    jmp .rl

    ; --- 3) final mix ---
.mix:
    xor rcx, rcx
.ml:
    cmp rcx, TOTAL
    jge .write
    movsx eax, word [dry + rcx*2]
    imul eax, DRY
    mov edi, 1000
    cdq
    idiv edi
    mov r10d, eax

    movsx eax, word [revbuf + rcx*2]
    imul eax, WET
    mov edi, 1000
    cdq
    idiv edi
    add r10d, eax

    mov eax, r10d
    cmp eax, 32767
    jle .m_hi
    mov eax, 32767
.m_hi:
    cmp eax, -32768
    jge .m_lo
    mov eax, -32768
.m_lo:
    mov [audio + rcx*2], ax
    inc rcx
    jmp .ml

.write:
    mov rax, 1
    mov rdi, 1
    lea rsi, [header]
    mov rdx, header_len
    syscall
    mov rax, 1
    mov rdi, 1
    lea rsi, [audio]
    mov rdx, 529200
    syscall
    mov rax, 60
    xor rdi, rdi
    syscall