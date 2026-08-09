; asm.fm — beep.asm
; A single square wave. The "hello world" of sound.
;
; Generates a 440 Hz (A4) square wave, 1 second long,
; and writes a valid WAV file to stdout.
;
; Sound is just numbers: 44100 of them per second, each one the
; position of a speaker cone. A square wave flips between high and
; low — that's the whole 8-bit soul.
;
;   nasm -f elf64 beep.asm -o beep.o && ld beep.o -o beep
;   ./beep > out.wav && aplay out.wav

section .data
    ; --- WAV header (44 bytes) ---
    ; sample_rate = 44100 Hz, mono, 16-bit
    ; 1 second => 44100 samples => 88200 bytes of audio data
    ;   data_bytes = 44100 * 2 = 88200
    ;   riff_size  = 36 + data_bytes = 88236
header:
    db "RIFF"                 ; ChunkID
    dd 88236                  ; ChunkSize = 36 + data size
    db "WAVE"                 ; Format
    db "fmt "                 ; Subchunk1ID
    dd 16                     ; Subchunk1Size (16 for PCM)
    dw 1                      ; AudioFormat (1 = PCM)
    dw 1                      ; NumChannels (1 = mono)
    dd 44100                  ; SampleRate
    dd 88200                  ; ByteRate = SampleRate * Channels * BytesPerSample
    dw 2                      ; BlockAlign = Channels * BytesPerSample
    dw 16                     ; BitsPerSample
    db "data"                 ; Subchunk2ID
    dd 88200                  ; Subchunk2Size = data size in bytes
header_len equ $ - header

    ; audio buffer lives in .data (not .bss) so Rosetta on Apple Silicon
    ; doesn't choke on a pure-bss load segment. 88200 bytes, zero-filled.
    audio: times 88200 db 0

section .text
    global _start

_start:
    ; --- generate the square wave into `audio` ---
    ; period in samples = 44100 / 440 ~= 100  (50 high, 50 low)
    ;
    ; rsi = write pointer into audio
    ; rcx = sample index (0 .. 44099)
    ; r8  = phase position within the period (0 .. 99)
    ; amplitude: high = +8000, low = -8000  (16-bit range: -32768..32767)

    lea rsi, [audio]
    xor rcx, rcx              ; sample index = 0
    xor r8, r8               ; phase = 0

.gen_loop:
    cmp rcx, 44100
    jge .write

    cmp r8, 50                ; first half of the period?
    jl .high

.low:
    mov ax, -8000
    jmp .store

.high:
    mov ax, 8000

.store:
    mov [rsi], ax             ; write 16-bit sample
    add rsi, 2

    inc r8                    ; advance phase
    cmp r8, 100               ; period complete?
    jl .no_wrap
    xor r8, r8               ; reset phase
.no_wrap:

    inc rcx
    jmp .gen_loop

.write:
    ; --- write WAV header to stdout ---
    mov rax, 1                ; sys_write
    mov rdi, 1                ; stdout
    lea rsi, [header]
    mov rdx, header_len
    syscall

    ; --- write audio data to stdout ---
    mov rax, 1
    mov rdi, 1
    lea rsi, [audio]
    mov rdx, 88200
    syscall

    ; --- exit(0) ---
    mov rax, 60
    xor rdi, rdi
    syscall
