; asm.fm — vibrato.asm
; Vibrato: the pitch, wavering gently, for a voice that's alive.
;
; Every note so far held one exact frequency for its whole duration —
; mathematically perfect, and a little lifeless. Real singers and
; instruments waver the pitch slightly and steadily. That's vibrato.
;
; The trick: a second, SLOW oscillator (an LFO — low-frequency
; oscillator, ~5-6 Hz) nudges the note's frequency up and down a little,
; many times per second. Instead of a fixed period, the period breathes:
;
;   period(t) = base_period + depth * sin(2*pi * lfo_rate * t)
;
; We reuse the hand-built sine table idea from fm.asm for the LFO shape.
;
;   nasm -f elf64 vibrato.asm -o vibrato.o && ld vibrato.o -o vibrato
;   ./vibrato > out.wav && aplay out.wav

section .data
    ; a few sustained notes (triangle) so the vibrato is easy to hear.
    ; longer notes = more audible wavering.
    HALF equ 22050            ; 0.5s notes
    AMP  equ 9000

    ; base periods (44100 / freq): A4=100 C5=84 E5=67 A4=100
    base_periods: dq 100, 84, 67, 100
    notes    equ 4

    SR       equ 44100

    ; --- vibrato settings ---
    ; LFO rate ~5.5 Hz. In table terms: how far we step through the 1024-
    ; entry sine table per sample = rate * 1024 / SR.
    ; 5.5 * 1024 / 44100 ≈ 0.1277 ... we keep it in fixed point *1000.
    ; step_x1000 = 128  (≈0.128 entries/sample -> ~5.5 Hz)
    LFO_STEP_X1000 equ 128
    ; depth: how many "period units" the pitch swings by. Small = subtle.
    VIB_DEPTH equ 4          ; period wobbles +/- 4 -> a gentle vibrato

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

; build a 1024-entry sine table, values -1000..+1000 (Bhaskara approx)
build_sine:
    xor rcx, rcx
.loop:
    cmp rcx, SINE_LEN
    jge .done
    mov rax, rcx
    imul rax, 360
    xor rdx, rdx
    mov rbx, SINE_LEN
    div rbx                   ; degrees 0..359
    mov r8, 1
    cmp rax, 180
    jl .have
    sub rax, 180
    mov r8, -1
.have:
    mov r9, 180
    sub r9, rax
    mov r10, rax
    imul r10, r9              ; p = x*(180-x)
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

; sine lookup: phase index in rdi -> value in rax (wraps mod 1024)
sine_at:
    mov rax, rdi
    and rax, (SINE_LEN - 1)
    mov rax, [sine + rax*8]
    ret

_start:
    call build_sine

    lea rsi, [audio]
    xor r12, r12              ; note index
    xor r13, r13             ; LFO phase (persists across notes for a smooth waver)

.note_loop:
    cmp r12, notes
    jge .write

    mov rbp, [base_periods + r12*8]   ; base period for this note

    xor rcx, rcx             ; sample counter in note
    xor r8, r8              ; oscillator phase

.sample_loop:
    cmp rcx, HALF
    jge .next_note

    ; --- compute vibrato-modulated period ---
    ; lfo = sine(LFO phase)   (-1000..1000)
    mov rdi, r13
    call sine_at             ; rax = lfo value
    ; wobble = VIB_DEPTH * lfo / 1000   (signed, -DEPTH..+DEPTH)
    imul rax, VIB_DEPTH
    mov rbx, 1000
    cqo
    idiv rbx                 ; rax = period offset
    ; current period = base + wobble
    mov r14, rbp
    add r14, rax             ; r14 = wobbled period
    ; guard: keep period >= 2
    cmp r14, 2
    jge .period_ok
    mov r14, 2
.period_ok:
    mov r15, r14
    shr r15, 1               ; half period (for triangle)

    ; --- triangle sample at current phase, using wobbled period ---
    cmp r8, r15
    jge .tri_dn
    mov rax, r8
    imul rax, (2*AMP)
    xor rdx, rdx
    div r15
    sub rax, AMP
    jmp .have_s
.tri_dn:
    mov rax, r8
    sub rax, r15
    imul rax, (2*AMP)
    xor rdx, rdx
    div r15
    mov rbx, AMP
    sub rbx, rax
    mov rax, rbx
.have_s:
    mov [rsi], ax
    add rsi, 2

    ; advance oscillator phase, wrap at current (wobbled) period
    inc r8
    cmp r8, r14
    jl .no_wrap
    xor r8, r8
.no_wrap:

    ; advance LFO phase by LFO_STEP_X1000/1000 per sample.
    ; accumulate in fixed point: keep a *1000 accumulator in r13 low bits?
    ; Simpler: step the phase index by adding, using a separate fractional
    ; accumulator stored in r11.
    add r11d, LFO_STEP_X1000   ; fractional accumulator *1000
    cmp r11d, 1000
    jl .lfo_done
    sub r11d, 1000
    inc r13                    ; advance LFO table index by 1
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
