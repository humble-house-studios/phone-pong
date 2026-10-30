"""Synthesizes every sound in Phone Pong (no samples, no downloads).

Run from the project root:  python3 tools/make_audio.py
Writes WAV files into audio/ and prints the music loop length in frames,
which main.gd uses as MUSIC_FRAMES.
"""
import os
import struct
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")


def note(n):
    """MIDI note number -> frequency."""
    return 440.0 * 2 ** ((n - 69) / 12)


def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def square(freq, dur, duty=0.5):
    ph = (np.cumsum(np.full(int(SR * dur), freq) if np.isscalar(freq) else freq) / SR) % 1.0
    return np.where(ph < duty, 1.0, -1.0)


def sweep_square(f0, f1, dur, duty=0.5):
    n = int(SR * dur)
    freqs = np.geomspace(f0, f1, n)
    ph = (np.cumsum(freqs) / SR) % 1.0
    return np.where(ph < duty, 1.0, -1.0)


def triangle(freq, dur):
    ph = (t_axis(dur) * freq) % 1.0
    return 4 * np.abs(ph - 0.5) - 1


def noise(dur, seed=0):
    return np.random.default_rng(seed).uniform(-1, 1, int(SR * dur))


def env(n, attack=0.004, release=0.03, decay_to=1.0):
    """Attack / linear decay / release envelope, no clicks."""
    e = np.linspace(1.0, decay_to, n)
    a = min(int(SR * attack), n)
    r = min(int(SR * release), n)
    if a:
        e[:a] *= np.linspace(0, 1, a)
    if r:
        e[-r:] *= np.linspace(1, 0, r)
    return e


def write_wav(name, data, loop_frames=None):
    data = np.clip(data, -1, 1)
    pcm = (data * 32000).astype("<i2").tobytes()
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm)
    if loop_frames:
        # Append a 'smpl' chunk so Godot detects the loop on import.
        smpl = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, loop_frames - 1, 0, 0)
        with open(path, "r+b") as f:
            f.seek(0, 2)
            f.write(b"smpl" + struct.pack("<I", len(smpl)) + smpl)
            size = f.tell()
            f.seek(4)
            f.write(struct.pack("<I", size - 8))
    return len(data)


def blip(freq, dur, duty=0.5, vol=0.5):
    s = square(freq, dur, duty)
    return s * env(len(s), release=dur * 0.6, decay_to=0.3) * vol


def arpeggio(notes, step, duty=0.25, vol=0.45, tail=0.0):
    parts = []
    for i, n in enumerate(notes):
        d = step + (tail if i == len(notes) - 1 else 0)
        s = square(note(n), d, duty)
        parts.append(s * env(len(s), release=min(0.05, d * 0.5), decay_to=0.5))
    return np.concatenate(parts) * vol


def make_sfx():
    write_wav("hit_player", blip(note(76), 0.07, 0.5, 0.55))
    write_wav("hit_cpu", blip(note(69), 0.07, 0.5, 0.45))
    write_wav("wall", blip(note(64), 0.035, 0.25, 0.3))
    write_wav("score_player", arpeggio([72, 76, 79, 84], 0.07, tail=0.15))
    write_wav("score_cpu", arpeggio([67, 63, 60], 0.09, duty=0.5, tail=0.15))
    write_wav("win", arpeggio([72, 76, 79, 84, 79, 84, 88], 0.09, tail=0.35, vol=0.5))
    s = sweep_square(note(62), note(43), 0.9, duty=0.5)
    write_wav("lose", s * env(len(s), release=0.3, decay_to=0.4) * 0.4)


def make_music():
    bpm = 140
    beat = 60 / bpm
    sixteenth = beat / 4
    bars = 8
    total = int(round(SR * beat * 4 * bars))
    mix = np.zeros(total)

    def place(sig, start_sec, gain=1.0):
        i = int(round(start_sec * SR))
        j = min(i + len(sig), total)
        mix[i:j] += sig[: j - i] * gain

    # A minor, with a lift to E major at the end so the loop pulls back to the top.
    chords = [
        (57, [69, 72, 76]),  # Am
        (53, [65, 69, 72]),  # F
        (48, [67, 72, 76]),  # C
        (55, [67, 71, 74]),  # G
        (57, [69, 72, 76]),  # Am
        (53, [65, 69, 72]),  # F
        (50, [65, 69, 74]),  # Dm
        (52, [68, 71, 76]),  # E
    ]

    for bar, (root, tones) in enumerate(chords):
        bar_t = bar * beat * 4
        # Bass: driving eighth notes, octave jump on the off-beats.
        for k in range(8):
            n = root - 12 + (12 if k % 2 else 0)
            d = beat / 2 * 0.9
            s = triangle(note(n), d)
            place(s * env(len(s), release=0.02, decay_to=0.7), bar_t + k * beat / 2, 0.38)
        # Arpeggio: 16th notes up and down the chord.
        pattern = [0, 1, 2, 1] * 4
        for k, idx in enumerate(pattern):
            n = tones[idx] + (12 if k >= 8 and bar % 2 else 0)
            s = square(note(n), sixteenth * 0.85, 0.25)
            place(s * env(len(s), release=0.02, decay_to=0.4), bar_t + k * sixteenth, 0.10)
        # Drums: kick on 1 and 3, snare on 2 and 4, hats on every eighth.
        for b in range(4):
            t0 = bar_t + b * beat
            if b % 2 == 0:
                kt = t_axis(0.16)
                kick = np.sin(2 * np.pi * np.cumsum(np.geomspace(150, 45, len(kt))) / SR)
                place(kick * env(len(kt), attack=0.001, release=0.1, decay_to=0.2), t0, 0.6)
            else:
                sn = noise(0.12, seed=bar * 4 + b)
                place(sn * env(len(sn), attack=0.001, release=0.1, decay_to=0.05), t0, 0.22)
            for h in range(2):
                hat = noise(0.03, seed=100 + bar * 8 + b * 2 + h)
                hat = np.diff(hat, prepend=0)  # brighter
                place(hat * env(len(hat), attack=0.001, release=0.02, decay_to=0.1),
                      t0 + h * beat / 2, 0.10 if h else 0.06)

    # Soft fade at both edges of the loop to avoid a click at the seam.
    edge = int(SR * 0.004)
    mix[:edge] *= np.linspace(0, 1, edge)
    mix[-edge:] *= np.linspace(1, 0, edge)
    mix /= max(1.0, np.max(np.abs(mix)) / 0.9)
    return write_wav("music", mix, loop_frames=total)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    make_sfx()
    frames = make_music()
    print(f"MUSIC_FRAMES = {frames}")
