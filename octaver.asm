; asm.fm — octaver.asm
; Octaver — a copy an octave below, thick and heavy like a synth bass.
;
; An octaver takes what you play and adds a copy one octave down (and
; sometimes one up too), fattening the sound with sub-bass weight. An
; octave down is exactly half the frequency — so the sub-oscillator
; advances its phase at half the rate of the main one. Mix the two and
; a thin lead becomes a heavy, chest-thumping bass. (Classic on funk
; basslines and everywhere in electronic music that wants low-end power.)
;
;   main:  plays the note at frequency f
;   sub1:  same waveform at f/2  (one octave down) -> phase increment / 2
;   sub2:  optional f/4 (two octaves down) for even more weight
;   out = main/2 + sub1/2   (balanced so the low end doesn't dominate)
;
; A short melody so you hear the octave-down tracking each note.
;
;   nasm -f elf64 octaver.asm -o octaver.o && ld octaver.o -o octaver
;   ./octaver > out.wav && aplay out.wav

section .data
    SR   equ 44100
    AMP  equ 7000

    ; a little bassline-ish melody. 16.16 increments for each note.
    ; A2=110, C3=131, E3=165, A3=220 -> incs = f*65536/44100
    ; 110->163, 131->195, 165->245, 220->327
    notes: dd 163, 195, 245, 327, 245, 195, 163, 131
    n_notes equ 8
    NOTE_LEN equ 22050        ; 0.5s per note
    TOTAL    equ 176400       ; 8 * 22050

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

    audio: times 352800 db 0

section .text
    global _start

; sawtooth from a 16.16 phase in eax -> eax in -AMP..+AMP
saw_from_phase:
    and eax, 0xFFFF
    imul eax, (2*AMP)
    shr eax, 16
    sub eax, AMP
    ret

_start:
    xor rcx, rcx             ; global sample index
    xor r12, r12            ; note index
    xor r14, r14            ; main phase (16.16)
    xor r15, r15            ; sub phase (16.16, octave down)
.note_loop:
    cmp r12, n_notes
    jge .write
    mov r13d, [notes + r12*4]  ; this note's main increment
    ; sub increment = main / 2 (one octave down)
    mov ebx, r13d
    shr ebx, 1               ; sub_inc = main_inc / 2

    xor r8, r8               ; sample within note
.samp:
    cmp r8, NOTE_LEN
    jge .next_note

    ; --- main oscillator (saw) ---
    add r14d, r13d
    mov eax, r14d
    call saw_from_phase
    mov r9d, eax             ; main sample

    ; --- sub oscillator (saw, octave down) ---
    add r15d, ebx
    mov eax, r15d
    call saw_from_phase
    ; mix = main/2 + sub/2
    sar eax, 1               ; sub/2
    sar r9d, 1               ; main/2
    add eax, r9d

    ; clamp & write
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
    inc r8
    jmp .samp
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
    mov rdx, 352800
    syscall
    mov rax, 60
    xor rdi, rdi
    syscall
