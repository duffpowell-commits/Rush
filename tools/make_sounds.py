#!/usr/bin/env python3
"""Build Rush's real sound set from CC0 recordings (Nov 25, 2026). Sources are listed in
assets/audio/SOURCES.md; download them into one folder and run:
    python3 tools/make_sounds.py <src_dir>
Writes mono .ogg clips + two synced music layers into assets/audio/. Needs ffmpeg + numpy."""
import subprocess, sys, os
import numpy as np

SRC = sys.argv[1]
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
SR = 44100


def load(name, start=0.0, dur=None, ch=1):
    cmd = ["ffmpeg", "-v", "error", "-ss", str(start)]
    if dur:
        cmd += ["-t", str(dur)]
    cmd += ["-i", os.path.join(SRC, name), "-ac", str(ch), "-ar", str(SR), "-f", "f32le", "-"]
    x = np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout, np.float32).copy()
    return x.reshape(-1, ch) if ch > 1 else x


def fade(x, a=0.005, b=0.05):
    n, m = int(a * SR), int(b * SR)
    x = x.copy()
    if n:
        x[:n] *= np.linspace(0, 1, n)[:, None] if x.ndim > 1 else np.linspace(0, 1, n)
    if m:
        x[-m:] *= np.linspace(1, 0, m)[:, None] if x.ndim > 1 else np.linspace(1, 0, m)
    return x


def peak(x, db=-1.0):
    return x * (10 ** (db / 20) / (np.abs(x).max() + 1e-9))


def mix(*parts):
    """parts: (signal, offset_seconds, gain)"""
    n = max(int(o * SR) + len(s) for s, o, g in parts)
    out = np.zeros(n, np.float32)
    for s, o, g in parts:
        i = int(o * SR)
        out[i:i + len(s)] += s * g
    return out


def pitch(x, r):
    """resample to change pitch and speed together (r > 1 = higher, shorter)"""
    idx = np.arange(0, len(x) - 1, r)
    return np.interp(idx, np.arange(len(x)), x).astype(np.float32)


def save(name, x, q=4):
    x = np.clip(x, -1, 1).astype(np.float32)
    ch = 1 if x.ndim == 1 else x.shape[1]
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", str(ch), "-i", "-",
                    "-c:a", "libvorbis", "-q:a", str(q), os.path.join(OUT, name + ".ogg")],
                   input=x.tobytes(), check=True)
    print(name, "%.2fs" % (len(x) / SR))


# --- one-shots (all mono) -------------------------------------------------------------------
click = load("cc0/switch_01.ogg")
save("click", peak(fade(click, 0.002, 0.03), -6))

ignite = load("turn_stove_on_01.ogg")
sizzle = load("fryingpan01.wav", 54.0, 1.3)
save("fire", peak(fade(mix((ignite, 0, 1.0), (fade(sizzle, 0.08, 0.5), 0.12, 1.6))), -2))

burst = load("fryingpan01.wav", 54.3, 0.7)
clank = load("cc0/pot_01.ogg")
save("rush", peak(fade(mix((pitch(fade(burst, 0.01, 0.25), 1.25), 0, 1.6), (clank, 0, 0.6))), -1))

save("plate", peak(fade(load("cc0/dishes_02.ogg"), 0.002, 0.1), -2))

ding = load("bell_ding2.wav")
save("bell", peak(fade(ding, 0.001, 0.3), -1))
save("level", peak(fade(mix((ding, 0, 1.0), (pitch(ding, 1.26), 0.22, 0.9)), 0.001, 0.4), -1))

smoke = pitch(load("fryingpan01.wav", 0.0, 1.4), 0.8)
save("burn", peak(fade(mix((fade(smoke, 0.01, 0.6), 0, 1.5), (load("cc0/metal_02.ogg"), 0, 0.8))), -1))

save("walk", peak(fade(load("cc0/slam_03.ogg"), 0.002, 0.15), -1))         # a table walks (chair shoved back)
save("door", peak(fade(load("cc0/door_close_03.ogg"), 0.002, 0.15), -1))   # a cook walks out
crash = mix(*[(load("cc0/dishes_0%d.ogg" % i), 0.07 * (i - 1), 0.8) for i in range(1, 5)])
save("gameover", peak(fade(mix((crash, 0, 1.0), (load("cc0/gong_02.ogg"), 0.05, 0.5)), 0.002, 0.6), -1))
save("ticket", peak(fade(load("cc0/paper_01.ogg"), 0.002, 0.08), -4))      # a new ticket prints

# --- music: cafe jazz, looped, plus a "rush" layer with the kitchen under it ------------------
A, L, CF = 2.0, 115.46, 0.04   # loop found by matching the onset envelope (corr 0.66)
song = load("little_cafe_0.wav", A, L + CF + 0.1, ch=2)
n, c = int(L * SR), int(CF * SR)
loop = song[:n].copy()
w = np.linspace(0, 1, c)[:, None]
loop[:c] = song[:c] * w + song[n:n + c] * (1 - w)
loop = loop * (10 ** (-3 / 20) / np.abs(loop).max())
save("music_loop", loop, q=3)

def tile(x, n):
    out = np.zeros(n, np.float32)
    i, cf = 0, int(0.5 * SR)
    while i < n:
        seg = x[: min(len(x), n - i)].copy()
        if i:
            seg[:cf] *= np.linspace(0, 1, cf)[: len(seg[:cf])]
        out[i:i + len(seg)] += seg
        i += len(x) - cf
    return out

amb = (tile(load("fryingpan01.wav", 2.0, 50.0), n) * 0.55 + tile(load("forkonplate01.wav", 0.0, 118.0), n) * 0.5
       + tile(load("kitchenstovefan01.wav", 10.0, 60.0), n) * 0.12)
amb = amb / (np.abs(amb).max() + 1e-9) * 0.35
busy = loop + amb[:, None]
busy = busy * (10 ** (-3 / 20) / np.abs(busy).max())
save("music_busy", busy, q=3)
