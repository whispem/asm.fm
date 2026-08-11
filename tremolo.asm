; asm.fm — tremolo.asm
; Tremolo: the volume, pulsing, like a heartbeat under the note.
;
; Vibrato wavered the PITCH. Tremolo is its sibling: it wavers the
; VOLUME instead. The frequency stays rock steady, but the amplitude
; rises and falls a few times per second, so the note seems to pulse
; or shimmer. It's the wobble in old guitar amps and organ stops.
;
; Same LFO idea as vibrato, but instead of nudging the period, the LFO
; scales the output amplitude between full and (full - depth).
;
;   nasm -f elf64 tremolo.asm -o tremolo.o && ld tremolo.o -o tremolo
;   ./tremolo > out.wav && aplay out.wav

section .data
    HALF equ 22050            ; 0.5s notes, so the pulsing is audible
    AMP  equ 9000

    ; sustained notes (triangle): A4 C5 E5 A4
    periods: dq 100, 84, 67, 100
    notes    equ 4

    SR       equ 44100

    ; --- tremolo settings ---
    ; LFO rate ~6 Hz -> step through 1024-table/sample = 6*1024/44100
    ; ≈ 0.139 -> fixed point *1000 = 139
    LFO_STEP_X1000 equ 139
    ; depth 0..256: how deeply the volume dips. 256 = full on/off,
    ; 180 ≈ dips to ~30% and back. A clear, musical tremolo.
    TREM_DEPTH equ 180        ; out of 256

    ; total = 4 * HALF = 88200 ; data = 176400 ; riff = 36+176400
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

sine_at:
    mov rax, rdi
    and rax, (SINE_LEN - 1)
    mov rax, [sine + rax*8]
    ret

_start:
    call build_sine

    lea rsi, [audio]
    xor r12, r12             ; note index
    xor r13, r13            ; LFO phase (persists for smooth pulsing)

.note_loop:
    cmp r12, notes
    jge .write

    mov rbp, [periods + r12*8]
    mov r14, rbp
    shr r14, 1               ; half period (triangle)

    xor rcx, rcx             ; sample counter
    xor r8, r8              ; oscillator phase
    xor r11, r11            ; LFO fractional accumulator

.sample_loop:
    cmp rcx, HALF
    jge .next_note

    ; --- raw triangle sample in r10 (-AMP..+AMP) ---
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
    mov r10, rax             ; raw sample

    ; --- tremolo gain from LFO ---
    ; lfo in -1000..1000 -> map to u = 0..1000 : u = (lfo+1000)/2
    mov rdi, r13
    call sine_at             ; rax = lfo (-1000..1000)
    add rax, 1000
    shr rax, 1               ; u = 0..1000 (0 = quietest point)
    ; gain(0..256) = (256 - TREM_DEPTH) + TREM_DEPTH * u / 1000
    mov r9, TREM_DEPTH
    imul r9, rax             ; depth * u
    mov rbx, 1000
    mov rax, r9
    xor rdx, rdx
    div rbx                  ; rax = depth*u/1000
    add rax, (256 - TREM_DEPTH)  ; + floor -> gain in 0..256
    mov r9, rax              ; r9 = gain

    ; apply gain: sample = raw * gain / 256
    mov rax, r10
    imul rax, r9
    sar rax, 8               ; signed /256
    mov [rsi], ax
    add rsi, 2

    ; advance oscillator phase
    inc r8
    cmp r8, rbp
    jl .no_wrap
    xor r8, r8
.no_wrap:

    ; advance LFO (fractional accumulator)
    add r11d, LFO_STEP_X1000
    cmp r11d, 1000
    jl .lfo_done
    sub r11d, 1000
    inc r13
.lfo_done:

    inc rcx
    jmp .sample_loop

.next_note:
    inc r12
    jmp .note_loop

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
