"""Placeholder sounds, synthesized (original, no licences to track). Replace any file in
assets/audio/ with a real one of the same name and nothing else changes.
Run: python3 tools/gen_audio.py"""
import math, struct, wave, random

RATE = 22050
random.seed(7)


def write(name, samples):
    with wave.open(f"assets/audio/{name}.wav", "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 30000)) for s in samples))


def tone(freqs, dur, vol=0.5, decay=8.0):
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        f = freqs[min(len(freqs) - 1, int(t / dur * len(freqs)))]
        out.append(vol * math.sin(2 * math.pi * f * t) * math.exp(-decay * t / dur))
    return out


write("click", tone([900], 0.05, 0.35, 5))
write("good", tone([660, 990], 0.14, 0.45, 4))
write("bad", tone([220, 150], 0.25, 0.5, 3))
write("level", tone([523, 659, 784, 1046], 0.5, 0.45, 2))
write("gameover", tone([392, 330, 262, 196], 0.9, 0.5, 2))

# 8-second music loop: soft pad chords
chords = [[220, 277, 330], [196, 247, 294], [175, 220, 262], [196, 247, 294]]
music = []
for c in chords:
    n = int(RATE * 2)
    for i in range(n):
        t = i / RATE
        env = min(1, t * 4) * min(1, (2 - t) * 4)
        music.append(0.12 * env * sum(math.sin(2 * math.pi * f * t) for f in c))
write("music_loop", music)
print("ok")
