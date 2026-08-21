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

The story so far — from a single beep to a real synth:

- [x] a single beep (square wave -> WAV header -> `write`)
- [x] one octave, in tune (note -> frequency table)
- [x] a real melody, sequenced by hand
- [x] all four oscillators (square, saw, triangle, noise for drums)
- [x] polyphony — melody + bass + percussion at once (a tiny tracker)
  - [x] polyphony + ADSR — the mix, now without clicks
- [x] ADSR envelopes, so notes breathe instead of clicking
- [x] [AMBITIOUS] an FM synth — the "fm" was never just about radio
- [x] vibrato — the pitch, wavering gently, for a voice that's alive
- [x] tremolo — the volume, pulsing, like a heartbeat under the note
  - [x] strong tremolo — depth cranked up, the note pulsing rhythmically
- [x] configurable tempo (BPM) — the same tune, fast or slow
- [x] PWM — pulse-width modulation, the square wave that shivers
- [x] a delay/echo — the sound, coming back to you, fading each time

### Sculpting the timbre

- [x] a low-pass filter — carve the highs, warm and mellow
- [x] bitcrusher — crush the resolution, lo-fi and crunchy
- [x] ring modulation — two signals multiplied, metallic and strange
- [x] a resonant filter sweep — the "wah" that opens and closes
- [x] distortion / overdrive — push the signal past its limits, crunchy and hot
- [x] an auto-wah — a filter that follows the signal's own energy, funky and alive

### More oscillators, stranger voices

- [x] a supersaw — many detuned saws stacked into one huge trance lead
- [ ] hard sync — one oscillator resetting another, tearing and aggressive
- [ ] an octaver — a copy an octave below, thick and heavy like a synth bass
- [ ] additive synthesis — building a tone by stacking dozens of sines, one harmonic at a time
- [ ] phase distortion synthesis — the Casio CZ trick, bending the read-through of a wave

### Space and movement

- [x] chorus — one voice becoming many, wide and shimmering
- [x] reverb — a room built from math, so notes have somewhere to ring
- [x] a flanger — a swept short delay, the sound of a jet passing overhead
- [x] a phaser — moving notches drifting through the spectrum, swirling and psychedelic
- [ ] a rotary speaker (Leslie) — a spinning voice, the swirl of a Hammond organ
- [ ] harmonic tremolo — lows and highs pulsing against each other, liquid and vintage
- [ ] a slapback delay — one short echo, rockabilly and immediate
- [ ] shimmer reverb — reflections rising into the light, ambient and celestial
- [ ] a stutter/glitch effect — sound shattered and repeated, hyperpop in assembly
- [ ] sidechain pumping — the volume breathing in time, the heartbeat of modern electronic music

### Shaping the dynamics

- [ ] a compressor — taming the loud and lifting the quiet, the invisible hand of every mix
- [ ] a limiter — a hard ceiling, so nothing ever clips
- [ ] a noise gate — silence below a threshold, cutting the hiss and the dead air

### Playing the machine

- [ ] an arpeggiator — chords played one note at a time, automatically
- [ ] a step sequencer — a grid of on and off, the heart of every drum machine
- [ ] drum patterns — a real beatmaker, kick and snare and hat in pure asm
- [ ] euclidean rhythms — beats spread evenly by an ancient algorithm, the pulse of techno
- [ ] swing / groove — nudging the offbeats late, so the machine feels human
- [ ] scale quantization — snapping notes to a scale, so everything plays in key
- [ ] named chords — play Cmaj7 or Dm by name, not by hand-stacked frequencies
- [ ] probability / generative notes — notes that fire by chance, music that writes itself
- [ ] a drone mode — sustained, evolving pads, ambient and endless
- [ ] microtonal tunings — stepping outside the 12 notes the West agreed on
- [ ] a text score format — compose in a file, no recompiling

### The deep end — modern synthesis, hand-rolled

- [ ] wavetable synthesis — a table of shapes, morphing as it plays (the modern sound, in pure asm)
- [ ] a pitch shifter — moving the pitch without moving the time (or the reverse)
- [ ] an octave/harmony generator — building chords from a single played note
- [ ] a vocoder — one signal's voice wrapped around another, the robot that sings
- [ ] MIDI export — write out a .mid alongside the .wav, to open your work in a real DAW
- [ ] [AMBITIOUS] multi-operator FM (6 operators, DX7-style algorithms)
- [ ] [AMBITIOUS] Karplus-Strong — plucked strings from a burst of noise
- [ ] [AMBITIOUS] physical modeling — simulating a tube or a reed, breath turned to sound
- [ ] [AMBITIOUS] granular synthesis — sound broken into a thousand grains, clouds of texture
- [ ] [AMBITIOUS] concatenative synthesis — reassembling fragments of real sound, collage as instrument
- [ ] [AMBITIOUS] convolution reverb — the fingerprint of a real hall, not a mathematical guess
- [ ] [AMBITIOUS] a full tracker interface — patterns, instruments, per-column effects, the FastTracker way
- [ ] [AMBITIOUS] a terminal waveform visualizer, drawing the sound as it plays
- [ ] [UNREASONABLE] spectral processing — an FFT in pure assembly, painting sound in frequencies
- [ ] [UNREASONABLE] real-time output straight to the sound card (/dev/dsp, then ALSA)

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
