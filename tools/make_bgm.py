#!/usr/bin/env python3
"""BGM を作る（要件#36）。外部の音源や楽曲は使わず、ここで作曲・合成する（すべてオリジナル）。

使い方（ffmpeg が必要。assets/bgm/*.ogg を作り直す）:
  python3 tools/make_bgm.py

曲:
  title   タイトル。ゆったりした店内放送ふう（88 BPM）
  konbini コンビニ。明るく軽い（112 BPM）
  arcade  ゲームセンター。にぎやかなシンセ（132 BPM）
  versus  対戦。少し緊張感のある短調（138 BPM）
各曲は 16 小節でつなぎ目なくループする。
"""
import math, os, random, struct, subprocess, sys, tempfile, wave

RATE = 32000
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "bgm")

NOTE = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def freq(midi):
    return 440.0 * 2 ** ((midi - 69) / 12.0)


def chord_notes(name, octave=4):
    """'Am7' -> midi notes"""
    root = name[0] + ("#" if len(name) > 1 and name[1] == "#" else "")
    rest = name[len(root):]
    base = 12 * (octave + 1) + NOTE[root]
    third = 3 if rest.startswith("m") and not rest.startswith("maj") else 4
    notes = [base, base + third, base + 7]
    if "maj7" in rest:
        notes.append(base + 11)
    elif "7" in rest:
        notes.append(base + 10)
    if "sus4" in rest:
        notes[1] = base + 5
    return notes


class Track:
    def __init__(self, bpm, bars):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.bars = bars
        self.length = int(self.beat * 4 * bars * RATE)
        self.buf = [0.0] * self.length

    def add(self, start_beat, samples, gain):
        i0 = int(start_beat * self.beat * RATE)
        n = self.length
        for i, v in enumerate(samples):
            self.buf[(i0 + i) % n] += v * gain  # 端を越えた分は先頭に回す（ループのつなぎ目をなめらかに）


def env(n, a, d, s, r, sustain_len):
    out = []
    for i in range(n):
        t = i / RATE
        if t < a:
            g = t / a
        elif t < a + d:
            g = 1 - (1 - s) * (t - a) / d
        elif t < sustain_len:
            g = s
        else:
            g = s * max(0.0, 1 - (t - sustain_len) / r)
        out.append(g)
    return out


def tone(f, dur, wave_kind, a=0.005, d=0.08, s=0.6, r=0.08, vib=0.0, duty=0.5):
    n = int((dur + r) * RATE)
    e = env(n, a, d, s, r, dur)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / RATE
        ff = f * (1 + vib * math.sin(2 * math.pi * 5.5 * t) * min(1.0, t * 3))
        ph += ff / RATE
        x = ph % 1.0
        if wave_kind == "square":
            v = 1.0 if x < duty else -1.0
        elif wave_kind == "tri":
            v = 4 * abs(x - 0.5) - 1
        elif wave_kind == "saw":
            v = 2 * x - 1
        else:
            v = math.sin(2 * math.pi * x)
        out.append(v * e[i])
    return out


def soft_square(f, dur, **kw):
    # 矩形波を少し丸める（耳に痛くないように）
    raw = tone(f, dur, "square", **kw)
    out, prev = [], 0.0
    for v in raw:
        prev += (v - prev) * 0.35
        out.append(prev)
    return out


def kick():
    n = int(0.22 * RATE)
    out, ph = [], 0.0
    for i in range(n):
        t = i / RATE
        f = 50 + 110 * math.exp(-t * 28)
        ph += f / RATE
        out.append(math.sin(2 * math.pi * ph) * math.exp(-t * 14))
    return out


def noise(dur, decay, rng, hp=0.0):
    n = int(dur * RATE)
    out, prev = [], 0.0
    for i in range(n):
        t = i / RATE
        w = rng.uniform(-1, 1)
        v = w - prev * hp
        prev = w
        out.append(v * math.exp(-t * decay))
    return out


def compose(name, bpm, key_root, minor, progression, lead_style, seed, drums=True, bars=16):
    rng = random.Random(seed)
    tr = Track(bpm, bars)
    scale = [0, 2, 3, 5, 7, 8, 10] if minor else [0, 2, 4, 5, 7, 9, 11]
    root_midi = 60 + NOTE[key_root]

    # パッド（和音）と ベース
    for bar in range(bars):
        ch = progression[bar % len(progression)]
        notes = chord_notes(ch, 4)
        for nt in notes:
            tr.add(bar * 4, tone(freq(nt), tr.beat * 4 - 0.05, "saw", a=0.12, d=0.4, s=0.5, r=0.2), 0.035)
        bass_root = chord_notes(ch, 2)[0]
        pattern = [0, 1.5, 2, 3.5] if lead_style != "calm" else [0, 2]
        for k, b in enumerate(pattern):
            nt = bass_root + (12 if (k == 3 and lead_style == "busy") else 0)
            tr.add(bar * 4 + b, tone(freq(nt), tr.beat * 0.45, "tri", a=0.003, d=0.1, s=0.7, r=0.05), 0.24)

    # メロディ: 和音の音を軸に、音階の中で動く。4小節ごとの「問い」と「答え」
    motif_rhythms = {
        "calm": [[0, 1.5], [2, 1], [3, 1]],
        "bright": [[0, 0.5], [0.5, 0.5], [1, 1], [2, 0.5], [2.5, 0.5], [3, 1]],
        "busy": [[0, 0.5], [0.5, 0.25], [0.75, 0.25], [1, 0.5], [1.5, 0.5], [2, 0.75], [2.75, 0.25], [3, 0.5], [3.5, 0.5]],
        "tense": [[0, 0.75], [0.75, 0.25], [1, 0.5], [1.5, 0.5], [2, 1], [3, 0.5], [3.5, 0.5]],
    }[lead_style]
    phrase_notes = []
    for phrase in range(2):
        line = []
        deg = rng.choice([0, 2, 4])
        for bar in range(4):
            bar_notes = []
            for (b, l) in motif_rhythms:
                step = rng.choice([-2, -1, -1, 0, 1, 1, 2])
                deg = max(-2, min(9, deg + step))
                bar_notes.append((b, l, deg))
            line.append(bar_notes)
        phrase_notes.append(line)
    lead_kind = {"calm": "sine", "bright": "square", "busy": "square", "tense": "square"}[lead_style]
    lead_gain = {"calm": 0.16, "bright": 0.09, "busy": 0.085, "tense": 0.09}[lead_style]
    for bar in range(bars):
        section = (bar // 4) % 4
        if section == 3 and bar % 4 == 3:
            continue  # 区切りで一拍休む
        line = phrase_notes[0 if section in (0, 2) else 1]
        for (b, l, deg) in line[bar % 4]:
            octv, idx = divmod(deg, 7)
            midi = root_midi + 12 * octv + scale[idx] + (12 if lead_style in ("busy", "tense") and section == 2 else 0)
            dur = l * tr.beat * 0.9
            if lead_kind == "square":
                s = soft_square(freq(midi), dur, a=0.004, d=0.06, s=0.55, r=0.06, vib=0.006, duty=0.25 if lead_style == "busy" else 0.5)
            else:
                s = tone(freq(midi), dur, "sine", a=0.02, d=0.2, s=0.6, r=0.25, vib=0.004)
            tr.add(bar * 4 + b, s, lead_gain)
            # 軽いこだま
            tr.add(bar * 4 + b + 0.75, s, lead_gain * 0.25)

    # 打楽器
    if drums:
        hat = noise(0.04, 90, rng, hp=0.9)
        snare = noise(0.18, 22, rng, hp=0.4)
        k = kick()
        for bar in range(bars):
            for b in range(4):
                if lead_style == "calm":
                    if b in (0, 2):
                        tr.add(bar * 4 + b, k, 0.35)
                    tr.add(bar * 4 + b + 0.5, hat, 0.05)
                    continue
                tr.add(bar * 4 + b, k if b % 2 == 0 else snare, 0.5 if b % 2 == 0 else 0.22)
                tr.add(bar * 4 + b + 0.5, hat, 0.07)
                if lead_style == "busy":
                    tr.add(bar * 4 + b + 0.25, hat, 0.035)
                    tr.add(bar * 4 + b + 0.75, hat, 0.035)
            if lead_style == "tense" and bar % 2 == 1:
                tr.add(bar * 4 + 3.5, k, 0.4)

    # 音量をそろえる
    peak = max(abs(v) for v in tr.buf) or 1.0
    g = 0.85 / peak
    return [max(-1.0, min(1.0, v * g)) for v in tr.buf]


SONGS = [
    ("title", 88, "F", False, ["Fmaj7", "Em7", "Dm7", "C", "A#maj7", "Am7", "Gm7", "C7"], "calm", 11),
    ("konbini", 112, "C", False, ["C", "G", "Am", "F", "C", "Em", "F", "G"], "bright", 23),
    ("arcade", 132, "E", False, ["E", "C#m", "A", "B", "E", "G#m", "A", "B7"], "busy", 37),
    ("versus", 138, "D", True, ["Dm", "A#", "C", "Am", "Dm", "Gm", "A#", "A7"], "tense", 41),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    for (name, bpm, key, minor, prog, style, seed) in SONGS:
        data = compose(name, bpm, key, minor, prog, style, seed)
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            tmp = f.name
        with wave.open(tmp, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(b"".join(struct.pack("<h", int(v * 32767)) for v in data))
        out = os.path.join(OUT, name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "4", out], check=True)
        os.remove(tmp)
        print(f"{out}  {len(data) / RATE:.1f}s")


if __name__ == "__main__":
    sys.exit(main())
