#!/usr/bin/env python3
"""把原先写死在 audio_director.gd 里的程序化音频，烘焙成外置 WAV 文件。

背景：所有 BGM / 环境音 / 音效原本都是 GDScript 里用 sin() 实时合成的，
音频数据和代码混在一起（658 行）。本脚本用 numpy 复刻同一套合成算法，
产出 res://assets/audio/ 下的独立文件，代码改为按 id 读文件。

好处：
  - 音频与代码解耦，美术/音频可以直接替换文件而不必改代码
  - 启动时不再需要 CPU 实时合成几十段波形
  - 后期想换成真实录音，只要按同名覆盖即可

用法：
  python3 tools/bake_audio.py            # 烘焙全部
  python3 tools/bake_audio.py --list     # 只列出将生成的文件
"""
import os
import sys
import wave
import math
import struct

import numpy as np

SR = 22050
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAME = os.path.join(ROOT, "game")
if not os.path.isfile(os.path.join(GAME, "project.godot")):
    GAME = ROOT
OUT_DIR = os.path.join(GAME, "assets", "audio")


def rng_for(seed):
    return np.random.default_rng(seed)


def env(buf, attack, release):
    n = len(buf)
    ai = max(1, int(attack * SR))
    ri = max(1, int(release * SR))
    g = np.ones(n)
    if ai < n:
        g[:ai] = np.linspace(0.0, 1.0, ai)
    if ri < n:
        g[n - ri:] = np.linspace(1.0, 0.0, ri)
    return buf * g


def lowpass(buf, cut):
    a = min(max(cut, 0.001), 0.999)
    out = np.empty_like(buf)
    prev = 0.0
    for i, v in enumerate(buf):
        prev = prev + a * (v - prev)
        out[i] = prev
    return out


def noise(n, r):
    return r.uniform(-1.0, 1.0, n)


def drone(dur, freqs, amp, r, noise_amt):
    n = int(dur * SR)
    t = np.arange(n) / SR
    v = np.zeros(n)
    for k, f in enumerate(freqs):
        lfo = 1.0 + 0.004 * np.sin(2 * np.pi * (0.05 + 0.017 * k) * t)
        v += np.sin(2 * np.pi * f * lfo * t) * amp / (1.0 + k * 0.6)
    if noise_amt > 0:
        v += lowpass(noise(n, r), 0.02) * noise_amt
    v *= 0.75 + 0.25 * np.sin(2 * np.pi * 0.037 * t)
    return v


def pulse_bed(dur, bpm, r):
    n = int(dur * SR)
    t = np.arange(n) / SR
    period = 60.0 / bpm
    ph = np.mod(t, period) / period
    thump = np.exp(-ph * 14.0) * np.sin(2 * np.pi * 48.0 * t)
    sub = np.sin(2 * np.pi * 36.7 * t) * 0.16
    return thump * 0.5 + sub


def air(dur, amp, hum, r):
    n = int(dur * SR)
    t = np.arange(n) / SR
    v = lowpass(noise(n, r), 0.012) * amp
    if hum > 0:
        v += np.sin(2 * np.pi * 50.0 * t) * hum
    return v


# ---------------------------------------------------------------- 音色定义
BGM_FREQ = {
    "bgm_title": [55, 82.5, 110],
    "bgm_menu": [55, 82.5, 110],
    "bgm_day_class": [98, 147],
    "bgm_unease": [61.7, 92.5, 123.4],
    "bgm_investigate": [73.4, 110],
    "bgm_rollcall": [58, 87, 232],
    "bgm_horror": [43.6, 65.4, 87.3],
    "bgm_chase": [49, 98],
    "bgm_truth": [65.4, 98, 130.8],
    "bgm_final": [43.6, 65.4, 98, 130.8],
    "bgm_ending_true": [130.8, 164.8, 196],
    "bgm_ending_bad": [49, 58.3, 73.4],
}
AMB_SPEC = {
    "amb_classroom_day": (0.05, 0.010),
    "amb_classroom_night": (0.035, 0.014),
    "amb_hallway": (0.04, 0.008),
    "amb_rain": (0.14, 0.0),
    "amb_dorm_night": (0.03, 0.012),
    "amb_old_building": (0.045, 0.006),
    "amb_broadcast_static": (0.16, 0.020),
    "amb_fire": (0.12, 0.0),
    "amb_library": (0.028, 0.009),
}


def synth(sid):
    r = rng_for(abs(hash(sid)) % (2 ** 31))

    if sid in BGM_FREQ:
        dur = 12.0
        v = drone(dur, BGM_FREQ[sid], 0.22, r, 0.02)
        if sid in ("bgm_chase", "bgm_final", "bgm_rollcall"):
            v += pulse_bed(dur, 104 if sid == "bgm_chase" else 62, r) * 0.5
        if sid == "bgm_ending_true":
            v = drone(dur, BGM_FREQ[sid], 0.16, r, 0.005) * 0.9
        return v * 0.6

    if sid in AMB_SPEC:
        amp, hum = AMB_SPEC[sid]
        dur = 8.0
        v = air(dur, amp, hum, r)
        if sid == "amb_rain":
            n = int(dur * SR)
            v = lowpass(noise(n, r), 0.35) * 0.16
        if sid == "amb_fire":
            n = int(dur * SR)
            base = lowpass(noise(n, r), 0.05) * 0.13
            crack = np.zeros(n)
            for _ in range(90):
                p = r.integers(0, n - 300)
                ln = int(r.integers(60, 280))
                crack[p:p + ln] += np.exp(-np.arange(ln) / 40.0) * r.uniform(0.1, 0.5)
            v = base + crack * 0.5
        if sid == "amb_broadcast_static":
            n = int(dur * SR)
            v = noise(n, r) * 0.13 + np.sin(2 * np.pi * 50 * np.arange(n) / SR) * 0.02
        return v

    # —— 音效
    def short(dur):
        return int(dur * SR)

    if sid == "sfx_click":
        n = short(0.05)
        return env(noise(n, r) * 0.28, 0.001, 0.04)
    if sid == "sfx_page":
        n = short(0.22)
        return env(lowpass(noise(n, r), 0.5) * 0.22, 0.005, 0.18)
    if sid in ("sfx_knock_soft", "sfx_knock_hard"):
        amp = 0.30 if sid == "sfx_knock_soft" else 0.55
        n = short(0.16)
        t = np.arange(n) / SR
        v = np.sin(2 * np.pi * 96 * t) * np.exp(-t * 26) * amp
        v += lowpass(noise(n, r), 0.2) * amp * 0.5 * np.exp(-t * 30)
        return v
    if sid == "sfx_knock_pattern":
        seq = [0.0, 0.17, 0.34, 0.62, 0.79]
        n = short(1.05)
        out = np.zeros(n)
        for s in seq:
            p = int(s * SR)
            ln = short(0.16)
            t = np.arange(ln) / SR
            hit = np.sin(2 * np.pi * 96 * t) * np.exp(-t * 26) * 0.42
            out[p:p + ln] += hit[:max(0, min(ln, n - p))]
        return out
    if sid in ("sfx_door", "sfx_door_slam"):
        n = short(0.5 if sid == "sfx_door" else 0.32)
        t = np.arange(n) / SR
        if sid == "sfx_door":
            v = lowpass(noise(n, r), 0.03) * 0.20
            v *= np.exp(-t * 3.0)
            v += np.sin(2 * np.pi * 70 * t) * 0.08 * np.exp(-t * 5)
        else:
            v = np.sin(2 * np.pi * 58 * t) * np.exp(-t * 12) * 0.6
            v += lowpass(noise(n, r), 0.25) * 0.35 * np.exp(-t * 18)
        return v
    if sid in ("sfx_broadcast_click", "sfx_broadcast_static"):
        n = short(0.09 if "click" in sid else 0.7)
        v = noise(n, r) * (0.30 if "click" in sid else 0.16)
        return env(v, 0.002, 0.05)
    if sid == "sfx_heartbeat":
        n = short(0.9)
        t = np.arange(n) / SR
        v = np.zeros(n)
        for off in (0.0, 0.30):
            ph = np.clip(t - off, 0, None)
            v += np.sin(2 * np.pi * 46 * ph) * np.exp(-ph * 15.0) * 0.55
        return v
    if sid == "sfx_scream":
        n = short(1.1)
        t = np.arange(n) / SR
        f = 420 + 260 * np.sin(2 * np.pi * 3.1 * t)
        v = np.sin(2 * np.pi * f * t) * 0.30
        v += noise(n, r) * 0.18
        return env(v, 0.02, 0.5)
    if sid == "sfx_whisper":
        n = short(1.4)
        v = lowpass(noise(n, r), 0.08) * 0.20
        t = np.arange(n) / SR
        v *= 0.6 + 0.4 * np.sin(2 * np.pi * 5.5 * t)
        return env(v, 0.15, 0.5)
    if sid == "sfx_glass":
        n = short(0.6)
        t = np.arange(n) / SR
        v = np.zeros(n)
        for f in (1800, 2400, 3100, 4200):
            v += np.sin(2 * np.pi * f * t) * np.exp(-t * 12) * 0.10
        v += noise(n, r) * 0.20 * np.exp(-t * 16)
        return v
    if sid in ("sfx_step", "sfx_steps_run"):
        if sid == "sfx_step":
            n = short(0.2)
            t = np.arange(n) / SR
            return lowpass(noise(n, r), 0.12) * 0.20 * np.exp(-t * 16)
        n = short(1.2)
        out = np.zeros(n)
        for i in range(6):
            p = int(i * 0.19 * SR)
            ln = short(0.16)
            t = np.arange(ln) / SR
            hit = lowpass(noise(ln, r), 0.12) * 0.22 * np.exp(-t * 18)
            out[p:p + ln] += hit[:max(0, min(ln, n - p))]
        return out
    if sid == "sfx_chair":
        n = short(0.42)
        t = np.arange(n) / SR
        v = lowpass(noise(n, r), 0.30) * 0.18
        v *= np.exp(-t * 4.0)
        return v
    if sid == "sfx_sting":
        n = short(1.0)
        t = np.arange(n) / SR
        v = np.sin(2 * np.pi * 1400 * t) * 0.16 * np.exp(-t * 5)
        v += np.sin(2 * np.pi * 220 * t) * 0.22 * np.exp(-t * 3)
        v += noise(n, r) * 0.10 * np.exp(-t * 8)
        return v
    if sid == "sfx_low_boom":
        n = short(1.6)
        t = np.arange(n) / SR
        v = np.sin(2 * np.pi * 34 * t) * 0.55 * np.exp(-t * 2.2)
        v += np.sin(2 * np.pi * 51 * t) * 0.22 * np.exp(-t * 3.0)
        return v
    if sid == "sfx_water":
        n = short(1.0)
        return lowpass(noise(n, r), 0.42) * 0.16
    if sid == "sfx_flesh":
        n = short(0.42)
        t = np.arange(n) / SR
        v = lowpass(noise(n, r), 0.10) * 0.30 * np.exp(-t * 7)
        v += np.sin(2 * np.pi * 62 * t) * 0.14 * np.exp(-t * 9)
        return v
    if sid == "sfx_bell":
        n = short(2.2)
        t = np.arange(n) / SR
        v = np.zeros(n)
        for f, a in ((784, 0.20), (1176, 0.12), (1568, 0.07)):
            v += np.sin(2 * np.pi * f * t) * a * np.exp(-t * 1.6)
        return v
    if sid == "sfx_write":
        n = short(0.5)
        t = np.arange(n) / SR
        v = lowpass(noise(n, r), 0.55) * 0.13
        v *= 0.5 + 0.5 * np.sin(2 * np.pi * 11 * t)
        return v
    if sid == "sfx_lighter":
        n = short(0.35)
        t = np.arange(n) / SR
        v = noise(n, r) * 0.24 * np.exp(-t * 22)
        return v
    if sid == "sfx_fire_burst":
        n = short(1.3)
        t = np.arange(n) / SR
        v = lowpass(noise(n, r), 0.20) * 0.30
        v *= np.exp(-t * 1.6)
        v += np.sin(2 * np.pi * 44 * t) * 0.14 * np.exp(-t * 2.4)
        return v
    if sid == "sfx_rewind":
        n = short(1.0)
        t = np.arange(n) / SR
        f = 1600 - 1200 * (t / (n / SR))
        v = np.sin(2 * np.pi * f * t) * 0.14
        v += noise(n, r) * 0.10
        return env(v, 0.01, 0.2)
    if sid == "sfx_breath":
        n = short(1.5)
        t = np.arange(n) / SR
        v = lowpass(noise(n, r), 0.06) * 0.18
        v *= 0.4 + 0.6 * np.abs(np.sin(2 * np.pi * 0.7 * t))
        return env(v, 0.2, 0.4)
    return None


def write_wav(path, buf):
    buf = np.clip(buf, -1.0, 1.0)
    data = (buf * 32000.0).astype("<i2").tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


ALL_IDS = (list(BGM_FREQ) + list(AMB_SPEC) + [
    "sfx_click", "sfx_page", "sfx_knock_soft", "sfx_knock_hard",
    "sfx_knock_pattern", "sfx_door", "sfx_door_slam", "sfx_broadcast_click",
    "sfx_broadcast_static", "sfx_heartbeat", "sfx_scream", "sfx_whisper",
    "sfx_glass", "sfx_step", "sfx_steps_run", "sfx_chair", "sfx_sting",
    "sfx_low_boom", "sfx_water", "sfx_flesh", "sfx_bell", "sfx_write",
    "sfx_lighter", "sfx_fire_burst", "sfx_rewind", "sfx_breath",
])


def main():
    if "--list" in sys.argv:
        for i in ALL_IDS:
            print(i)
        return 0
    os.makedirs(OUT_DIR, exist_ok=True)
    total = 0
    ok = 0
    for sid in ALL_IDS:
        total += 1
        buf = synth(sid)
        if buf is None:
            print(f"  [skip] {sid}")
            continue
        p = os.path.join(OUT_DIR, sid + ".wav")
        write_wav(p, buf)
        ok += 1
        print(f"  {sid:24s} {len(buf) / SR:5.1f}s  "
              f"{os.path.getsize(p) / 1024:7.1f} KB")
    size = sum(os.path.getsize(os.path.join(OUT_DIR, f))
               for f in os.listdir(OUT_DIR) if f.endswith(".wav"))
    print(f"\n烘焙 {ok}/{total} 个音频，合计 {size / 1024 / 1024:.1f} MB")
    print(f"输出目录：{OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
