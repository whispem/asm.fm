; asm.fm — ringmod.asm
; Ring modulation — two signals multiplied, metallic and strange.
;
; Most effects add to or reshape a wave. Ring modulation MULTIPLIES two
; waves together, sample by sample. The math is almost nothing:
;
;   out[n] = carrier[n] * modulator[n]
;
; but the result is uncanny. Multiplying two frequencies produces their
; SUM and DIFFERENCE — new tones with no simple harmonic relationship to
; the originals. That's why ring mod sounds metallic, clangorous, robotic:
; it's the sound of Daleks, of sci-fi machines, of bells that shouldn't be.
;
; Here a 440 Hz tone is ring-modulated by a lower 80 Hz sine. We play the
; plain tone first, then the ring-modulated version, to hear it transform.
;
;   nasm -f elf64 ringmod.asm -o ringmod.o && ld ringmod.o -o ringmod
;   ./ringmod > out.wav && aplay out.wav

section .data
    SR   equ 44100
    AMP  equ 9000

    ONE  equ 44100           ; 1 second per pass

    ; carrier: 440 Hz sine (via table). period in table steps handled below.
    ; modulator: 80 Hz sine — low, for a rich clangorous result.
    ; carrier phase inc  = 440 * 1024 / 44100 ≈ 10  (we use *1000 fixed pt)
    ; modulator phase inc =  80 * 1024 / 44100 ≈ 1.857
    CAR_INC_X1000 equ 10217   ; 440*1024*1000/44100
    MOD_INC_X1000 equ 1857    ;  80*1024*1000/44100

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

; sine lookup: phase index in rdi -> value (-1000..1000) in rax
sine_at:
    mov rax, rdi
    and rax, (SINE_LEN - 1)
    mov rax, [sine + rax*8]
    ret

_start:
    call build_sine
    lea rsi, [audio]

    ; ---- Pass 1: plain 440 Hz carrier ----
    xor rcx, rcx
    xor r10, r10             ; carrier phase accumulator (*1000)
.plain:
    cmp rcx, ONE
    jge .ringmod
    ; carrier sample from table
    mov rax, r10
    mov rbx, 1000
    xor rdx, rdx
    div rbx                  ; phase index = accumulator / 1000
    mov rdi, rax
    call sine_at             ; rax = -1000..1000
    ; scale to amplitude
    imul rax, AMP
    mov rbx, 1000
    cqo
    idiv rbx
    mov [rsi], ax
    add rsi, 2
    add r10, CAR_INC_X1000
    inc rcx
    jmp .plain

    ; ---- Pass 2: carrier * modulator (ring modulation) ----
.ringmod:
    xor rcx, rcx
    xor r10, r10             ; carrier phase
    xor r11, r11             ; modulator phase
.ring:
    cmp rcx, ONE
    jge .write
    ; carrier value
    mov rax, r10
    mov rbx, 1000
    xor rdx, rdx
    div rbx
    mov rdi, rax
    call sine_at
    mov r12, rax             ; carrier (-1000..1000)
    ; modulator value
    mov rax, r11
    mov rbx, 1000
    xor rdx, rdx
    div rbx
    mov rdi, rax
    call sine_at
    mov r13, rax             ; modulator (-1000..1000)
    ; out = carrier * modulator / 1000, then scale to amplitude
    mov rax, r12
    imul rax, r13            ; carrier*modulator  (-1e6..1e6)
    mov rbx, 1000
    cqo
    idiv rbx                 ; /1000 -> back to -1000..1000
    ; scale to amplitude
    imul rax, AMP
    mov rbx, 1000
    cqo
    idiv rbx
    mov [rsi], ax
    add rsi, 2
    add r10, CAR_INC_X1000
    add r11, MOD_INC_X1000
    inc rcx
    jmp .ring

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
