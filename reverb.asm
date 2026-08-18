; asm.fm — reverb.asm
; Reverb — a room built from math, so notes have somewhere to ring.
;
; A delay gives you a few distinct echoes. A real room gives you thousands,
; overlapping and blurring into a smooth wash that slowly fades. We can't
; store thousands of taps by hand, so we use the classic Schroeder trick:
;
;   - a few COMB filters in parallel (each a delay with feedback), whose
;     different lengths create dense, colourless-ish repeating echoes
;   - then a couple of ALLPASS filters in series, which smear those echoes
;     in time without changing the tone — turning a "boing" into a "shhh"
;
; Sum the combs, run through the allpasses, mix with the dry signal, and a
; short note suddenly sounds like it was played in a hall.
;
;   nasm -f elf64 reverb.asm -o reverb.o && ld reverb.o -o reverb
;   ./reverb > out.wav && aplay out.wav

section .data
    SR   equ 44100
    AMP  equ 9000

    ; a few short notes with gaps, so the tail rings out audibly between them
    ; triangle, C5=84 E5=67 G5=56 (period), each short then silence
    NOTE_LEN equ 4410         ; 0.1s note
    GAP      equ 22050        ; 0.5s gap (hear the tail)
    periods: dq 84, 67, 56
    n_notes  equ 3
    TOTAL    equ 79380        ; 3*(4410+22050) = 79380

    ; --- comb filter delay lengths (samples) & feedback ---
    ; classic Schroeder-ish prime-ish lengths for density
    COMB1 equ 1557
    COMB2 equ 1617
    COMB3 equ 1491
    COMB4 equ 1422
    COMB_FB equ 195           ; feedback /256 (~0.76 -> medium-long tail)

    ; --- allpass filter params ---
    AP1 equ 225
    AP2 equ 556
    AP_G equ 128              ; allpass coefficient /256 (0.5)

    WET equ 140               ; wet mix /256
    DRY equ 160               ; dry mix /256

header:
    db "RIFF"
    dd 158796
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
    dd 158760
header_len equ $ - header

    audio: times 158760 db 0
    dry:   times 158760 db 0

    ; comb + allpass delay buffers (zeroed)
    cb1: times 6400 db 0
    cb2: times 6400 db 0
    cb3: times 6400 db 0
    cb4: times 6400 db 0
    ap1b: times 2400 db 0
    ap2b: times 2400 db 0

section .text
    global _start

_start:
    ; --- Phase 1: render dry notes ---
    lea rsi, [dry]
    xor r12, r12
.note_loop:
    cmp r12, n_notes
    jge .reverb
    mov rbp, [periods + r12*8]
    mov r14, rbp
    shr r14, 1
    ; note
    xor rcx, rcx
    xor r8, r8
.tone:
    cmp rcx, NOTE_LEN
    jge .sil
    cmp r8, r14
    jge .dn
    mov rax, r8
    imul rax, (2*AMP)
    xor rdx, rdx
    div r14
    sub rax, AMP
    jmp .st
.dn:
    mov rax, r8
    sub rax, r14
    imul rax, (2*AMP)
    xor rdx, rdx
    div r14
    mov rbx, AMP
    sub rbx, rax
    mov rax, rbx
.st:
    mov [rsi], ax
    add rsi, 2
    inc r8
    cmp r8, rbp
    jl .nw
    xor r8, r8
.nw:
    inc rcx
    jmp .tone
.sil:
    xor rcx, rcx
.silence:
    cmp rcx, GAP
    jge .nextn
    mov word [rsi], 0
    add rsi, 2
    inc rcx
    jmp .silence
.nextn:
    inc r12
    jmp .note_loop

    ; --- Phase 2: reverb ---
    ; For each sample: run 4 combs in parallel on dry[n], sum them,
    ; then pass through 2 allpasses in series, then mix wet+dry.
.reverb:
    xor rcx, rcx             ; sample index
.loop:
    cmp rcx, TOTAL
    jge .write

    movsx r15d, word [dry + rcx*2]   ; x = dry input (signed)

    xor r13d, r13d           ; accumulator for comb outputs

    ; ---- COMB 1 ----
    ; idx = rcx mod COMB1 ; y = buf[idx] ; buf[idx] = x + y*FB/256 ; acc += y
    mov rax, rcx
    xor rdx, rdx
    mov rbx, COMB1
    div rbx
    mov r8, rdx              ; idx
    movsx r9d, word [cb1 + r8*2]     ; y
    add r13d, r9d
    mov eax, r9d
    imul eax, COMB_FB
    sar eax, 8
    add eax, r15d            ; x + y*FB
    mov [cb1 + r8*2], ax

    ; ---- COMB 2 ----
    mov rax, rcx
    xor rdx, rdx
    mov rbx, COMB2
    div rbx
    mov r8, rdx
    movsx r9d, word [cb2 + r8*2]
    add r13d, r9d
    mov eax, r9d
    imul eax, COMB_FB
    sar eax, 8
    add eax, r15d
    mov [cb2 + r8*2], ax

    ; ---- COMB 3 ----
    mov rax, rcx
    xor rdx, rdx
    mov rbx, COMB3
    div rbx
    mov r8, rdx
    movsx r9d, word [cb3 + r8*2]
    add r13d, r9d
    mov eax, r9d
    imul eax, COMB_FB
    sar eax, 8
    add eax, r15d
    mov [cb3 + r8*2], ax

    ; ---- COMB 4 ----
    mov rax, rcx
    xor rdx, rdx
    mov rbx, COMB4
    div rbx
    mov r8, rdx
    movsx r9d, word [cb4 + r8*2]
    add r13d, r9d
    mov eax, r9d
    imul eax, COMB_FB
    sar eax, 8
    add eax, r15d
    mov [cb4 + r8*2], ax

    ; average the 4 combs (divide by 4)
    sar r13d, 2              ; r13 = comb sum /4  -> this is our wet signal so far

    ; ---- ALLPASS 1 ----
    ; idx = rcx mod AP1 ; buffered = buf[idx]
    ; out = -g*in + buffered ; buf[idx] = in + g*out   (in = r13)
    mov rax, rcx
    xor rdx, rdx
    mov rbx, AP1
    div rbx
    mov r8, rdx
    movsx r10d, word [ap1b + r8*2]   ; buffered
    ; out = buffered - g*in/256
    mov eax, r13d
    imul eax, AP_G
    sar eax, 8              ; g*in
    mov r11d, r10d
    sub r11d, eax           ; out = buffered - g*in
    ; buf = in + g*out/256
    mov eax, r11d
    imul eax, AP_G
    sar eax, 8
    add eax, r13d          ; in + g*out
    mov [ap1b + r8*2], ax
    mov r13d, r11d          ; carry out forward

    ; ---- ALLPASS 2 ----
    mov rax, rcx
    xor rdx, rdx
    mov rbx, AP2
    div rbx
    mov r8, rdx
    movsx r10d, word [ap2b + r8*2]
    mov eax, r13d
    imul eax, AP_G
    sar eax, 8
    mov r11d, r10d
    sub r11d, eax
    mov eax, r11d
    imul eax, AP_G
    sar eax, 8
    add eax, r13d
    mov [ap2b + r8*2], ax
    mov r13d, r11d          ; r13 = wet output

    ; ---- mix wet + dry ----
    mov eax, r13d
    imul eax, WET
    sar eax, 8              ; wet*WET/256
    mov edx, r15d
    imul edx, DRY
    sar edx, 8              ; dry*DRY/256
    add eax, edx
    ; clamp
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
    mov rdx, 158760
    syscall
    mov rax, 60
    xor rdi, rdi
    syscall
