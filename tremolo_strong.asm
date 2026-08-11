; asm.fm — tremolo_strong.asm  (exaggerated, to hear it clearly)
; Same as tremolo.asm but with MAXIMUM depth (volume drops almost to
; silence) and a slower, very obvious pulse. One long held note so the
; heartbeat is unmistakable.

section .data
    AMP  equ 10000
    SR   equ 44100
    ; ONE long note (A4) held for 3 seconds, so the pulsing is all you hear
    PERIOD equ 100            ; A4
    DURATION equ 132300       ; 3 seconds

    ; strong tremolo: slow (~4 Hz) and DEEP (drops to near silence)
    LFO_STEP_X1000 equ 93     ; ~4 Hz  (4*1024/44100 ≈ 0.093)
    TREM_DEPTH equ 250        ; out of 256 -> almost full on/off

    ; data = 132300*2 = 264600 ; riff = 36+264600
header:
    db "RIFF"
    dd 264636
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
    dd 264600
header_len equ $ - header
    audio: times 264600 db 0
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
    lea rsi, [audio]

    mov r14, PERIOD
    shr r14, 1               ; half period

    xor rcx, rcx             ; sample counter
    xor r8, r8              ; osc phase
    xor r13, r13            ; LFO phase
    xor r11, r11            ; LFO frac accumulator

.sample_loop:
    cmp rcx, DURATION
    jge .write

    ; raw triangle in r10
    cmp r8, r14
    jge .tri_dn
    mov rax, r8
    imul rax, (2*AMP)
    xor rdx, rdx
    div r14
    sub rax, AMP
    jmp .have_raw
.tri_dn:
    mov rax, r8
    sub rax, r14
    imul rax, (2*AMP)
    xor rdx, rdx
    div r14
    mov rbx, AMP
    sub rbx, rax
    mov rax, rbx
.have_raw:
    mov r10, rax

    ; tremolo gain
    mov rdi, r13
    call sine_at
    add rax, 1000
    shr rax, 1               ; u = 0..1000
    mov r9, TREM_DEPTH
    imul r9, rax
    mov rbx, 1000
    mov rax, r9
    xor rdx, rdx
    div rbx
    add rax, (256 - TREM_DEPTH)
    mov r9, rax              ; gain 0..256

    mov rax, r10
    imul rax, r9
    sar rax, 8
    mov [rsi], ax
    add rsi, 2

    inc r8
    cmp r8, PERIOD
    jl .nw
    xor r8, r8
.nw:
    add r11d, LFO_STEP_X1000
    cmp r11d, 1000
    jl .lfod
    sub r11d, 1000
    inc r13
.lfod:
    inc rcx
    jmp .sample_loop

.write:
    mov rax, 1
    mov rdi, 1
    lea rsi, [header]
    mov rdx, header_len
    syscall
    mov rax, 1
    mov rdi, 1
    lea rsi, [audio]
    mov rdx, 264600
    syscall
    mov rax, 60
    xor rdi, rdi
    syscall
