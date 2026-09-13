; asm.fm — slapback.asm
; Slapback delay — one short echo, rockabilly and immediate.
;
; Slapback is the sound of 1950s rock'n'roll — Elvis's voice, Scotty Moore's
; guitar. It's the simplest delay there is: a SINGLE echo, very short (about
; 80-140 ms), with no feedback. Long enough to hear as a distinct repeat, short
; enough to feel like it's slapping right back at you. No repeats trailing off —
; just one quick, punchy double.
;
; The whole trick: for each sample, add a scaled copy of the sample from ~110 ms
; ago. Because there's no feedback, the echo doesn't echo itself — it's clean and
; tight, which is exactly the rockabilly character.
;
;   delay = ~110 ms  -> 0.110 * 44100 ≈ 4851 samples
;   out[i] = dry[i] + 0.6 * dry[i - delay]
;
; A short plucked melody so you clearly hear the single slap on each note.
;
;   nasm -f elf64 slapback.asm -o slapback.o && ld slapback.o -o slapback
;   ./slapback > out.wav && aplay out.wav

section .data
    SR   equ 44100
    AMP  equ 8000

    DELAY equ 4851            ; ~110 ms in samples
    ECHO_NUM equ 6            ; echo gain = 6/10 = 0.6

    ; a little melody, 16.16 increments. A3=220, C4=262, E4=330, G4=392
    notes: dd 327, 389, 490, 583, 490, 389, 327, 0
    n_notes equ 8
    NOTE_LEN equ 22050        ; 0.5s per note
    TOTAL    equ 176400

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

    ; dry buffer (clean melody) and output buffer
    dry:   times 352800 db 0
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

    ; --- 1) render the dry plucked melody into `dry` ---
    xor rcx, rcx             ; global sample index
    xor r12, r12            ; note index
    xor r14, r14            ; phase
.note_loop:
    cmp r12, n_notes
    jge .apply
    mov r13d, [notes + r12*4]  ; this note's increment

    xor r8, r8               ; sample within note
.samp:
    cmp r8, NOTE_LEN
    jge .next_note
    ; skip silence note (inc=0)
    test r13d, r13d
    jz .write_dry

    add r14, r13
    mov rdi, r14
    shr rdi, 6
    call sine_at             ; -1000..1000
    ; pluck decay envelope: amplitude fades over the note
    ; env = (NOTE_LEN - r8) / NOTE_LEN
    mov r9, NOTE_LEN
    sub r9, r8               ; remaining
    imul rax, r9             ; sine * remaining
    mov r10, NOTE_LEN
    cqo
    idiv r10                 ; sine * env
    ; scale to AMP
    imul rax, AMP
    mov r10, 1000
    cqo
    idiv r10
    jmp .store_dry
.write_dry:
    xor rax, rax
.store_dry:
    mov [dry + rcx*2], ax
    inc rcx
    inc r8
    jmp .samp
.next_note:
    inc r12
    jmp .note_loop

    ; --- 2) apply single slapback echo: audio[i] = dry[i] + 0.6*dry[i-DELAY] ---
.apply:
    xor rcx, rcx
.mix:
    cmp rcx, TOTAL
    jge .write
    ; dry sample
    movsx eax, word [dry + rcx*2]
    ; delayed sample (if i >= DELAY)
    cmp rcx, DELAY
    jl .no_echo
    mov rbx, rcx
    sub rbx, DELAY
    movsx edx, word [dry + rbx*2]
    imul edx, ECHO_NUM
    mov ebx, 10
    push rax
    mov eax, edx
    cdq
    idiv ebx                 ; delayed * 0.6
    mov edx, eax
    pop rax
    add eax, edx             ; dry + echo
.no_echo:
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
    jmp .mix

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
