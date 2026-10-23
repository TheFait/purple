"""Synthesizes the game's sound effects into assets/audio/*.wav.

Pure stdlib, deterministic (seeded). Original synthesis, so no third-party licensing.
Run from the project root:  python tools/gen_sfx.py
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
TAU = math.tau


def n_samples(sec):
    return int(RATE * sec)


def env_ad(i, n, attack=0.01, decay_pow=3.0):
    """Fast attack, exponential-ish decay over the whole buffer."""
    t = i / n
    a = min(1.0, i / max(1, RATE * attack))
    return a * (1.0 - t) ** decay_pow


def sine(freq, i):
    return math.sin(TAU * freq * i / RATE)


def tri(freq, i):
    return 2.0 / math.pi * math.asin(math.sin(TAU * freq * i / RATE))


def saw(freq, i):
    p = (freq * i / RATE) % 1.0
    return 2.0 * p - 1.0


class Noise:
    """White noise through a one-pole lowpass (cutoff 0..1, higher = brighter)."""

    def __init__(self, seed, cutoff=0.5):
        self.rng = random.Random(seed)
        self.cutoff = cutoff
        self.y = 0.0

    def next(self):
        x = self.rng.uniform(-1, 1)
        self.y += self.cutoff * (x - self.y)
        return self.y


def write(name, samples, gain=0.8):
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = gain / peak
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples))
    print("wrote", os.path.relpath(path))


def click():
    n = n_samples(0.05)
    return [sine(1500, i) * env_ad(i, n, 0.002, 4) for i in range(n)]


def tick():
    n = n_samples(0.04)
    nz = Noise(1, 0.6)
    return [(sine(900, i) * 0.6 + nz.next() * 0.4) * env_ad(i, n, 0.001, 5) for i in range(n)]


def slide():
    n = n_samples(0.28)
    nz = Noise(2, 0.12)
    out = []
    for i in range(n):
        t = i / n
        e = math.sin(math.pi * t) ** 1.5
        out.append(nz.next() * e)
    return out


def flip():
    n = n_samples(0.16)
    nz = Noise(3, 0.7)
    return [(nz.next() * 0.7 + sine(220 - 120 * i / n, i) * 0.6) * env_ad(i, n, 0.002, 3) for i in range(n)]


def heartbeat():
    n = n_samples(0.62)
    out = [0.0] * n
    for start, amp in ((0.0, 1.0), (0.22, 0.75)):
        s0 = n_samples(start)
        ln = n_samples(0.18)
        for i in range(ln):
            if s0 + i < n:
                out[s0 + i] += sine(62 - 20 * i / ln, i) * env_ad(i, ln, 0.005, 2.5) * amp
    return out


def drumroll():
    dur = 1.1
    n = n_samples(dur)
    nz = Noise(4, 0.35)
    out = []
    for i in range(n):
        t = i / n
        rate = 14 + 26 * t  # hits per second accelerate
        phase = (t * dur * rate) % 1.0
        hit = (1.0 - phase) ** 4
        out.append(nz.next() * hit * (0.25 + 0.75 * t))
    return out


def win():
    notes = [523.25, 659.25, 783.99, 1046.5]
    n = n_samples(0.75)
    out = [0.0] * n
    for k, f in enumerate(notes):
        s0 = n_samples(0.07 * k)
        ln = n - s0
        for i in range(ln):
            e = env_ad(i, ln, 0.005, 2.2)
            out[s0 + i] += (tri(f, i) * 0.6 + sine(f * 2, i) * 0.25) * e
    return out


def streak():
    n = n_samples(0.9)
    out = []
    for i in range(n):
        t = i / n
        f = 440 * 2 ** (2.5 * t)
        out.append((sine(f, i) * 0.5 + tri(f * 1.5, i) * 0.3) * math.sin(math.pi * min(1.0, t * 1.1)) ** 0.8 * (1 - t) ** 0.6)
    return out


def lose():
    n = n_samples(1.2)
    nz = Noise(5, 0.5)
    out = []
    for i in range(n):
        t = i / n
        f = 220 * (1 - 0.8 * t)
        buzz = saw(f, i) * 0.5 + saw(f * 1.01, i) * 0.4
        boom = sine(55 * (1 - 0.4 * t), i) * 1.2 * math.exp(-4 * t)
        crash = nz.next() * math.exp(-6 * t)
        out.append((buzz * (1 - t) ** 1.5 + boom + crash * 0.8))
    return out


def shuffle():
    n = n_samples(0.55)
    nz = Noise(6, 0.45)
    out = []
    for i in range(n):
        t = i / n
        burst = 0.5 + 0.5 * math.sin(TAU * 22 * t)
        out.append(nz.next() * burst * math.sin(math.pi * t))
    return out


def turn():
    n = n_samples(0.4)
    out = [0.0] * n
    for k, f in enumerate((659.25, 880.0)):
        s0 = n_samples(0.11 * k)
        ln = n - s0
        for i in range(ln):
            out[s0 + i] += sine(f, i) * env_ad(i, ln, 0.004, 3)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    write("click", click(), 0.6)
    write("tick", tick(), 0.6)
    write("slide", slide(), 0.55)
    write("flip", flip(), 0.8)
    write("heartbeat", heartbeat(), 0.9)
    write("drumroll", drumroll(), 0.7)
    write("win", win(), 0.7)
    write("streak", streak(), 0.7)
    write("lose", lose(), 0.9)
    write("shuffle", shuffle(), 0.5)
    write("turn", turn(), 0.5)


if __name__ == "__main__":
    main()
