# asm.fm

> No sound card driver. No audio library. Just the CPU and 44100 numbers a second.

No `libc`. No external calls. Sound is a list of numbers — generate the right ones, write them to a `.wav`, and the speaker moves. That's the whole trick.

## Ground rules

- x86_64, Linux, NASM
- no libc, no external calls — `syscall` or nothing
- every sample computed by hand
- if it screeches, it builds character

## Build

```sh
make            # binaries land in bin/
```

### on macOS

The target is Linux, so run it in a container. Any OCI runtime works — Docker, Podman, Colima, OrbStack — they all read the same `Dockerfile`:

```sh
docker build -t asmfm .
docker run --rm -it -v "$PWD":/asmfm asmfm
make            # inside the container
```

What I actually use: [OrbStack](https://orbstack.dev) + VS Code's Dev Containers extension. "Reopen in Container" and the terminal drops straight into Linux with `make` ready.

Note: sample buffers live in `.data`, not `.bss` — Rosetta's x86 translation chokes on pure-bss load segments (`rosetta error: bss_size overflow`).

## Usage

```sh
./bin/beep                  # a single square wave. the "hello world" of sound
./bin/beep > out.wav        # ...or dump it to a file and play it anywhere
aplay out.wav               # (or open it in anything — it's a real WAV)
```

Everything writes a valid RIFF/WAVE stream: 16-bit PCM, mono, 44.1 kHz. Pipe it, play it, keep it.

## How it works

A speaker is a cone that moves in and out. Describe its position 44100 times a second and you've described a sound.

- **Oscillators** — square, sawtooth, triangle, and noise, generated one sample at a time. The square wave is the whole 8-bit soul: high for half a period, low for the other half.
- **Pitch** — a note is just a frequency. A table maps `A4 -> 440 Hz`, and the rest of the notes fall out from there.
- **Sequencing** — a tune is a list of `{ note, duration }`. The player walks it and fills the buffer.
- **Output** — a hand-written 44-byte WAV header, then the raw samples. `write(1, ...)` and you're done.

## Roadmap

- [x] a single beep (square wave -> WAV header -> `write`)
- [x] one octave, in tune (note -> frequency table)
- [x] a real melody, sequenced by hand
- [x] all four oscillators (square, saw, triangle, noise for drums)
- [x] polyphony — melody + bass + percussion at once (a tiny tracker)
  - [x] polyphony + ADSR — the mix, now without clicks
- [ ] ADSR envelopes, so notes breathe instead of clicking
- [ ] **[AMBITIOUS]** real-time output straight to the sound card (`/dev/dsp`, then ALSA)
- [ ] **[UNREASONABLE]** an FM synth. the "fm" was never just about radio

## Experiments

Little side-by-side tests, for hearing what a single feature actually does:

- `melody_hard` vs `melody_smooth` — the same solo melody with hard note edges vs a strong ADSR envelope. Play them back to back: one clicks, the other breathes.
- `polyphony_adsr` — polyphony and envelopes combined: the three-voice mix with per-note ADSR, so nothing clicks.

## Why?

Because I'd made the CPU count, sort, hash, and draw — but never sing.

## Useful resources

- the WAV/RIFF spec (it's mercifully short)
- the equal-temperament formula (twelve notes, one ratio)
- Intel® 64 and IA-32 manuals, still ~5000 pages, still bedtime reading
- a rubber duck with perfect pitch
