# 离线合成全部音效与背景音乐，输出 16-bit 单声道 WAV。
#
# 为什么用离线合成而不是运行时 AudioStreamGenerator：
# 1) 生成器每帧往缓冲区填样本，一旦主线程卡顿（后期两百只怪）就会断续爆音；
# 2) 离线文件可以先生成再用数值分析验证峰值/频段/首尾突变，生成器做不到；
# 3) Godot 导入后走 C++ 音频混音，CPU 开销接近零。
#
# 所有音效统一流程：合成 -> 单极点低通衰减高频 -> 首尾淡入淡出 -> 峰值归一化。
# 低通和淡入淡出是「不刺耳」的关键：方波/锯齿的整数倍谐波在 8kHz 以上会像针扎，
# 而波形首尾的采样突变会产生 click 噪声。
import array
import math
import os
import random
import sys

SR = 44100
# 脚本就放在 audio/ 里，输出目录即自身所在目录。
# 用法：python audio/make_audio.py
OUT = os.path.dirname(os.path.abspath(__file__))


# ----------------------------------------------------------------- 基础工具

def write_wav(name, samples, sr=SR):
    path = os.path.join(OUT, name)
    buf = array.array("h")
    for s in samples:
        v = int(round(max(-1.0, min(1.0, s)) * 32767.0))
        buf.append(v)
    if sys.byteorder == "big":
        buf.byteswap()
    data = buf.tobytes()
    header = b"RIFF" + (36 + len(data)).to_bytes(4, "little") + b"WAVEfmt "
    header += (16).to_bytes(4, "little")
    header += (1).to_bytes(2, "little")          # PCM
    header += (1).to_bytes(2, "little")          # 单声道
    header += sr.to_bytes(4, "little")
    header += (sr * 2).to_bytes(4, "little")     # byte rate
    header += (2).to_bytes(2, "little")          # block align
    header += (16).to_bytes(2, "little")         # bits
    header += b"data" + len(data).to_bytes(4, "little")
    with open(path, "wb") as f:
        f.write(header)
        f.write(data)
    print("  %-18s %6.0f ms  %6.1f KB" % (name, len(samples) / sr * 1000.0, len(data) / 1024.0))


def lowpass(samples, cutoff, sr=SR, loop=False):
    """单极点 IIR。截止越低越闷，也越不容易扎耳。

    loop=True 时先用尾部两秒驱动滤波器到稳态再处理正文。否则滤波器从 0 状态
    起步，开头会被启动瞬态压低一截，循环播放时每次回到起点都能听到一声轻微的
    "咔"——波形在接缝处有台阶，而不是连续过渡。
    """
    a = 1.0 - math.exp(-2.0 * math.pi * cutoff / sr)
    y = 0.0
    if loop:
        warm = min(len(samples), int(2.0 * sr))
        for i in range(len(samples) - warm, len(samples)):
            y += a * (samples[i] - y)
    out = []
    for s in samples:
        y += a * (s - y)
        out.append(y)
    return out


def fade(samples, fade_in=0.002, fade_out=0.006, sr=SR):
    n = len(samples)
    fi = min(int(fade_in * sr), n)
    fo = min(int(fade_out * sr), n)
    for i in range(fi):
        samples[i] *= float(i) / float(max(fi, 1))
    for i in range(fo):
        samples[n - 1 - i] *= float(i) / float(max(fo, 1))
    return samples


def normalize(samples, target_dbfs):
    peak = 0.0
    for s in samples:
        peak = max(peak, abs(s))
    if peak < 1e-9:
        return samples
    gain = (10.0 ** (target_dbfs / 20.0)) / peak
    return [s * gain for s in samples]


def mix(*tracks):
    n = 0
    for t in tracks:
        n = max(n, len(t))
    out = [0.0] * n
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out


def pad(samples, seconds, sr=SR):
    return [0.0] * int(seconds * sr) + list(samples)


def tone(dur, freq_fn, amp_fn, harmonics=(), sr=SR):
    """用累计相位合成，滑音时不会因为 2πft 直接取值而产生相位跳变。"""
    n = int(dur * sr)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / sr
        phase += 2.0 * math.pi * freq_fn(t) / sr
        v = math.sin(phase)
        for mult, gain in harmonics:
            v += gain * math.sin(phase * mult)
        out.append(v * amp_fn(t))
    return out


def noise(dur, amp_fn, rng, sr=SR):
    n = int(dur * sr)
    return [rng.uniform(-1.0, 1.0) * amp_fn(i / sr) for i in range(n)]


def echo(samples, delay_s, wet=0.3, sr=SR):
    """只做两次反射：反射次数多了音尾会拖成糊状，失去「一声音效」的利落感。"""
    d = int(delay_s * sr)
    n = len(samples)
    out = list(samples)
    out.extend([0.0] * (d * 2))
    for rep in (1, 2):
        g = wet if rep == 1 else wet * wet * 1.6
        off = d * rep
        for i in range(n):
            out[off + i] += samples[i] * g
    return out


def env(t, attack, tau):
    if t < attack:
        return t / attack
    return math.exp(-(t - attack) / tau)


# ----------------------------------------------------------------- 音效

def make_shoot(rng):
    # 手枪：极短的气流声 + 一点点下滑音高。射速高，必须做得轻、短、闷。
    body = tone(0.055, lambda t: 300.0 + 220.0 * math.exp(-t / 0.010),
                lambda t: env(t, 0.0015, 0.013), harmonics=[(2, 0.16)])
    puff = lowpass(noise(0.014, lambda t: math.exp(-t / 0.003) * 0.55, rng), 4200)
    s = mix(body, puff)
    s = lowpass(s, 4800)
    return normalize(fade(s, 0.0012, 0.008), -15.0)


def make_hit(rng):
    # 命中：闷响 + 短噪声。不做高频「叮」，因为一秒可能响十几次。
    thump = tone(0.06, lambda t: 150.0 + 70.0 * math.exp(-t / 0.012),
                 lambda t: env(t, 0.0012, 0.011), harmonics=[(2, 0.28)])
    crack = lowpass(noise(0.06, lambda t: env(t, 0.0008, 0.007) * 0.7, rng), 2400)
    s = lowpass(mix(thump, crack), 3600)
    return normalize(fade(s, 0.0010, 0.008), -13.0)


def make_kill(rng):
    # 击杀：低频「噗」。频率压到 150 以下，密集击杀时叠起来是一层低频雾，
    # 而不是一层尖刺。击杀声的响度要比命中更低，否则会盖住命中反馈。
    body = tone(0.09, lambda t: 55.0 + 95.0 * math.exp(-t / 0.018),
                lambda t: env(t, 0.002, 0.026), harmonics=[(2, 0.16), (3, 0.05)])
    sub = tone(0.09, lambda t: 48.0, lambda t: env(t, 0.004, 0.030))
    s = lowpass(mix(body, [v * 0.55 for v in sub]), 1100)
    return normalize(fade(s, 0.002, 0.012), -12.0)


def make_hurt(rng):
    # 受伤：锯齿下滑。锯齿有全部整数倍谐波，单靠一级低通仍会扎耳，串两级。
    dur = 0.22
    n = int(dur * SR)
    body = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = 75.0 + 150.0 * math.exp(-t / 0.06)
        phase += 2.0 * math.pi * f / SR
        saw = 2.0 * ((phase / (2.0 * math.pi)) % 1.0) - 1.0
        body.append(saw * env(t, 0.004, 0.075) * 0.55)
    grit = lowpass(noise(dur, lambda t: env(t, 0.002, 0.040) * 0.5, rng), 1300)
    s = lowpass(lowpass(mix(body, grit), 1700), 2100)
    return normalize(fade(s, 0.003, 0.025), -8.0)


def make_pickup(rng):
    # 拾取经验：两个音的上行小提示，比击杀略高但不尖。
    a = tone(0.045, lambda t: 990.0, lambda t: env(t, 0.002, 0.015), harmonics=[(2, 0.14)])
    b = tone(0.055, lambda t: 1480.0, lambda t: env(t, 0.002, 0.017), harmonics=[(2, 0.10)])
    s = lowpass(mix(a, pad(b, 0.028)), 6000)
    return normalize(fade(s, 0.002, 0.012), -14.0)


def make_levelup(rng):
    # 升级：四音上行琶音 + 两次反射。这是全局最"明亮"的音，但也不能超过 -9dB。
    notes = [523.25, 659.25, 783.99, 1046.50]
    pieces = []
    for i, f in enumerate(notes):
        t = tone(0.20, lambda x, f=f: f * (1.0 + 0.008 * math.exp(-x / 0.012)),
                 lambda x: env(x, 0.008, 0.055), harmonics=[(2, 0.20), (3, 0.07)])
        pieces.append(pad(t, i * 0.072))
    s = lowpass(echo(mix(*pieces), 0.105, 0.26), 5200)
    return normalize(fade(s, 0.004, 0.06), -10.0)


def make_gameover(rng):
    # 死亡：三音下行，慢衰减。要"沉"，所以用纯正弦叠少量二次谐波。
    notes = [(392.00, 0.0), (311.13, 0.18), (233.08, 0.36)]
    pieces = []
    for f, start in notes:
        t = tone(0.36, lambda x, f=f: f, lambda x: env(x, 0.010, 0.095),
                 harmonics=[(2, 0.18), (3, 0.05)])
        pieces.append(pad(t, start))
    s = lowpass(echo(mix(*pieces), 0.145, 0.22), 2600)
    return normalize(fade(s, 0.004, 0.09), -9.5)


def make_start(rng):
    # 开始游戏：三音快速上行。
    notes = [392.00, 523.25, 659.25]
    pieces = []
    for i, f in enumerate(notes):
        t = tone(0.18, lambda x, f=f: f, lambda x: env(x, 0.005, 0.048),
                 harmonics=[(2, 0.16)])
        pieces.append(pad(t, i * 0.058))
    s = lowpass(mix(*pieces), 5000)
    return normalize(fade(s, 0.003, 0.05), -11.0)


def make_click(rng):
    # 界面点击：20ms 极短音。长了会在快速连点时糊成一片。
    t = tone(0.032, lambda x: 1750.0, lambda x: env(x, 0.001, 0.0055), harmonics=[(2, 0.2)])
    s = lowpass(t, 8000)
    return normalize(fade(s, 0.0008, 0.004), -17.0)


# ----------------------------------------------------------------- 背景音乐

def make_bgm(rng):
    # 32 秒无缝循环 ambient：低频持续音 + 稀疏琶音。
    #
    # 无缝的前提是「所有周期信号在 32 秒内都是整数个周期」：
    #   110Hz × 32 = 3520 ✓   165Hz × 32 = 5280 ✓   220Hz × 32 = 7040 ✓
    #   LFO 0.0625Hz × 32 = 2 ✓
    # 于是循环点相位完全连续，不需要交叉淡化（交叉淡化会让循环处出现音量凹陷）。
    # 琶音在 30 秒前全部衰减干净，循环接缝处只剩持续音。
    dur = 32.0
    n = int(dur * SR)
    out = [0.0] * n

    for i in range(n):
        t = i / SR
        lfo = 0.62 + 0.38 * math.sin(2.0 * math.pi * 0.0625 * t - math.pi * 0.5)
        v = 0.34 * math.sin(2.0 * math.pi * 110.0 * t)
        v += 0.20 * math.sin(2.0 * math.pi * 165.0 * t)
        v += 0.09 * math.sin(2.0 * math.pi * 220.0 * t)
        out[i] += v * lfo

    # A 小调五声音阶，避免出现半音导致的不协和
    scale = [220.00, 261.63, 329.63, 392.00, 440.00, 523.25]
    t = 0.0
    while t <= 28.0:
        f = scale[rng.randrange(len(scale))]
        start = int(t * SR)
        length = min(int(2.2 * SR), n - start)
        phase = 0.0
        for i in range(length):
            x = i / SR
            phase += 2.0 * math.pi * f / SR
            amp = min(1.0, x / 0.05) * math.exp(-x / 0.55) * 0.10
            out[start + i] += (math.sin(phase) + 0.16 * math.sin(phase * 2.0)) * amp
        t += 2.0

    out = lowpass(lowpass(out, 2200, loop=True), 2600, loop=True)
    return normalize(out, -18.0)


# ----------------------------------------------------------------- 入口

def main():
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(20261106)
    print("生成音效：")
    write_wav("sfx_shoot.wav", make_shoot(rng))
    write_wav("sfx_hit.wav", make_hit(rng))
    write_wav("sfx_kill.wav", make_kill(rng))
    write_wav("sfx_hurt.wav", make_hurt(rng))
    write_wav("sfx_pickup.wav", make_pickup(rng))
    write_wav("sfx_levelup.wav", make_levelup(rng))
    write_wav("sfx_gameover.wav", make_gameover(rng))
    write_wav("sfx_start.wav", make_start(rng))
    write_wav("sfx_click.wav", make_click(rng))
    print("生成音乐：")
    write_wav("bgm_loop.wav", make_bgm(rng))
    print("完成 ->", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
