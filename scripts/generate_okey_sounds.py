# -*- coding: utf-8 -*-
"""Okey masasi icin GERCEKCI ornek ses efektleri.

Yaklasim: basit sinus "bip"leri yerine fiziksel modelleme.
  * Tas sesleri  -> modal sentez (kisa gurultu darbesi + rezonans modlari)
  * Kahkaha      -> formant (vokal trakti) sentezi, Rosenberg glotal darbe
  * Alkis        -> tek tek el cirpma darbelerinin istatistiksel toplami
  * Zil / piyano -> inharmonik kismi tonlar + tokmak/cekic gurultusu
  * Oda          -> Schroeder reverb (comb + allpass) ile mekan hissi

Cikti: 44.1 kHz, 16-bit mono WAV -> assets/sounds/
Calistirmak icin (bagimliliksiz, sadece standart kutuphane):
    python scripts/generate_okey_sounds.py
"""
import array, math, os, random, wave

SR = 44100
OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "assets",
    "sounds",
)

LN1000 = math.log(1000.0)


# --------------------------------------------------------------- yardimcilar
def zeros(dur):
    return [0.0] * int(SR * dur)


def add(dst, t0, src, gain=1.0):
    i0 = int(SR * t0)
    n = len(dst)
    for i, v in enumerate(src):
        j = i0 + i
        if 0 <= j < n:
            dst[j] += v * gain


def biquad_coeffs(kind, f0, q, gain_db=0.0):
    w0 = 2.0 * math.pi * f0 / SR
    cw, sw = math.cos(w0), math.sin(w0)
    alpha = sw / (2.0 * q)
    if kind == "lp":
        b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
        a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    elif kind == "hp":
        b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
        a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    elif kind == "bp":
        b0, b1, b2 = alpha, 0.0, -alpha
        a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    else:  # peak
        amp = 10.0 ** (gain_db / 40.0)
        b0, b1, b2 = 1 + alpha * amp, -2 * cw, 1 - alpha * amp
        a0, a1, a2 = 1 + alpha / amp, -2 * cw, 1 - alpha / amp
    return (b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)


def biquad(x, kind, f0, q, gain_db=0.0):
    b0, b1, b2, a1, a2 = biquad_coeffs(kind, f0, q, gain_db)
    y = [0.0] * len(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x):
        o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, v
        y2, y1 = y1, o
        y[i] = o
    return y


def resonate(x, freq, t60, gain=1.0, out=None):
    """Iki kutuplu rezonator — bir modun 'cinlamasi'."""
    r = math.exp(-LN1000 / max(1e-4, t60 * SR))
    w = 2.0 * math.pi * freq / SR
    c1 = 2.0 * r * math.cos(w)
    c2 = -r * r
    # DURTU YANITI TEPESI = gain olacak sekilde normalizasyon.
    # y[n] = a*r^n*sin((n+1)w)/sin(w) oldugundan a = sin(w) secilir.
    # (1-r^2)*sin(w) kullanmak — sinuzoidal girise gore normalizasyon —
    # modlari ~40 dB bastirip sesi cinlamasi olmayan kuru bir "tik"e
    # cevirir.
    a = math.sin(w) * gain
    n = len(x)
    if out is None:
        out = [0.0] * n
    y1 = y2 = 0.0
    for i in range(n):
        o = a * x[i] + c1 * y1 + c2 * y2
        y2, y1 = y1, o
        out[i] += o
    return out


def excitation(dur_ms, sharpness=5.0, seed=1, n=None, rise=0.18):
    """Cok kisa gurultu darbesi — 'vurus' anini temsil eder.

    Dirac degil, KISA BIR KUVVET DARBESI: gercek bir carpismada temas
    sifir surede olmaz. `rise` (ms) kadarlik yumusak yukselis, butun
    modlarin tek bir ornekte ayni fazda toplanmasini engeller — bu
    yapilmazsa ses, cinlamasi duyulmayan devasa bir sivri uce doner.
    """
    rnd = random.Random(seed)
    ne = max(4, int(SR * dur_ms / 1000.0))
    nr = max(2, int(SR * rise / 1000.0))
    n = n or ne
    exc = [0.0] * n
    for i in range(min(ne, n)):
        env = math.exp(-sharpness * i / ne)
        if i < nr:
            env *= 0.5 * (1.0 - math.cos(math.pi * i / nr))
        exc[i] = rnd.uniform(-1.0, 1.0) * env
    return exc


def modal_hit(modes, dur, exc_ms=1.6, sharpness=5.0, seed=1):
    """Modal sentez: darbe -> paralel rezonator bankasi.

    modes: (frekans, t60, kazanc) uclusu listesi.
    """
    n = int(SR * dur)
    exc = excitation(exc_ms, sharpness, seed, n)
    out = [0.0] * n
    for f, t60, g in modes:
        resonate(exc, f, t60, g, out)
    return out


def noise(dur, seed=2):
    rnd = random.Random(seed)
    return [rnd.uniform(-1.0, 1.0) for _ in range(int(SR * dur))]


def envelope(x, attack=0.002, decay=None, curve=4.0, hold=0.0):
    n = len(x)
    na = max(1, int(SR * attack))
    nh = int(SR * hold)
    nd = n - na - nh
    out = [0.0] * n
    for i in range(n):
        if i < na:
            e = i / na
        elif i < na + nh:
            e = 1.0
        else:
            e = math.exp(-curve * (i - na - nh) / max(1, nd))
        out[i] = x[i] * e
    return out


def comb(x, delay, fb):
    buf = [0.0] * delay
    y = [0.0] * len(x)
    idx = 0
    for i, v in enumerate(x):
        o = buf[idx]
        buf[idx] = v + o * fb
        idx += 1
        if idx == delay:
            idx = 0
        y[i] = o
    return y


def allpass(x, delay, g=0.5):
    buf = [0.0] * delay
    y = [0.0] * len(x)
    idx = 0
    for i, v in enumerate(x):
        b = buf[idx]
        o = -g * v + b
        buf[idx] = v + g * b
        idx += 1
        if idx == delay:
            idx = 0
        y[i] = o
    return y


def reverb(x, mix=0.12, rt=0.4):
    """Kucuk oda — Schroeder. Kuru sese mekan/derinlik katar."""
    combs = (1116, 1188, 1277, 1356)
    wet = [0.0] * len(x)
    for d in combs:
        fb = 10.0 ** (-3.0 * d / (SR * rt))
        c = comb(x, d, fb)
        for i in range(len(x)):
            wet[i] += c[i] * 0.25
    for d, g in ((556, 0.5), (441, 0.5)):
        wet = allpass(wet, d, g)
    return [x[i] * (1.0 - mix * 0.35) + wet[i] * mix for i in range(len(x))]


def dc_block(x, f=35.0):
    return biquad(x, "hp", f, 0.707)


def fade_out(x, ms=10.0):
    nf = min(len(x), int(SR * ms / 1000.0))
    for k in range(nf):
        x[len(x) - nf + k] *= 1.0 - k / nf
    return x


def short_rms(x, win_ms=50.0):
    """En gurultulu 50 ms penceresinin RMS'i.

    Kisa vurus sesleri icin dosya geneli RMS yaniltici: ses 40 ms surer,
    gerisi sessizliktir. Algilanan gurlugu bu metrik cok daha iyi temsil
    eder; butun efektler buna gore esitlenir.
    """
    w = int(SR * win_ms / 1000.0)
    if len(x) <= w:
        return math.sqrt(sum(v * v for v in x) / max(1, len(x)))
    s = sum(v * v for v in x[:w])
    best = s
    for i in range(w, len(x)):
        s += x[i] * x[i] - x[i - w] * x[i - w]
        if s > best:
            best = s
    return math.sqrt(best / w)


def compress(x, thresh=0.15, ratio=5.0, attack_ms=1.2, release_ms=55.0,
             look_ms=2.5):
    """Zarf takipli kompresor.

    Sentezlenen darbelerin tepe/ortalama orani ~27 dB cikiyor; gercek bir
    mikrofon kaydinda bu 15–18 dB'dir. Kompresor ilk sivri ucu bastirip
    tasin CINLAMASINI one cikarir — hem daha gercekci hem de telefon
    hoparloründe duyulur olur.
    """
    at = math.exp(-1.0 / (SR * attack_ms / 1000.0))
    rl = math.exp(-1.0 / (SR * release_ms / 1000.0))
    n = len(x)
    la = int(SR * look_ms / 1000.0)
    env = 0.0
    gain = [1.0] * n
    for i in range(n):
        a = abs(x[i])
        env = a + (at if a > env else rl) * (env - a)
        gain[i] = (thresh + (env - thresh) / ratio) / env if env > thresh else 1.0
    # ILERI BAKIS: kazanc, sinyalin `la` ornek ILERISINDEN okunur. Zarf
    # takipcisi 1 ms'lik bir sivri ucu yakalayamaz; ileri bakis olmadan
    # kompresor tam da bastirmasi gereken transient'i kaciriyordu.
    return [x[i] * gain[min(n - 1, i + la)] for i in range(n)]


def write(name, data, loud=0.12, ceiling=0.93, comp=None):
    """Gurluk hedefine gore olcekler, tepe degeri tavani asarsa geri ceker.

    KIRPMA YOK: tepe sinirini asan ses SAF KAZANC ile kucultulur. Vurus
    seslerinin tepe/ortalama orani ~20 dB'dir; doygunluga sokmak "gercekci"
    olmalarini saglayan transient'i tam da yok ederdi.
    """
    data = dc_block(data)
    fade_out(data)
    if comp:
        # Kompresor esigi mutlak bir deger oldugu icin once tepe
        # normalizasyonu yapilir; boylece esik her seste ayni anlama gelir.
        pre = 0.98 / max(1e-9, max(abs(v) for v in data))
        data = compress([v * pre for v in data], comp[0], comp[1])
    gain = loud / max(1e-9, short_rms(data))
    top = max(abs(v) for v in data) * gain
    if top > ceiling:
        gain *= ceiling / top
    pcm = array.array(
        "h", (int(max(-1.0, min(1.0, v * gain)) * 32767) for v in data)
    )
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(
        "%-18s %5.2f s  %6.1f KB"
        % (name, len(data) / SR, os.path.getsize(path) / 1024.0)
    )


# --------------------------------------------------------------- tas sesleri
def tile_click(seed=1, bright=1.0, body=1.0, dur=0.22, damp=1.0):
    """Okey tasi (melamin/bakalit) sert bir yuzeye carpiyor.

    Gercek bir tasin tinisi: 2–7 kHz arasi birkac inharmonik mod, 20–60 ms
    sonumleme, ustune cok kisa bir 'tik' transienti.
    """
    modes = [
        (620 * body, 0.115 * damp, 0.60),
        (1180 * body, 0.095 * damp, 0.80),
        (2340 * bright, 0.070 * damp, 1.00),
        (3610 * bright, 0.048 * damp, 0.65),
        (5180 * bright, 0.028 * damp, 0.40),
        (7400 * bright, 0.016 * damp, 0.22),
    ]
    y = modal_hit(modes, dur, exc_ms=1.4, sharpness=6.0, seed=seed)
    # temas gurultusu — plastigin "cirt"i
    click = envelope(noise(0.006, seed + 40), attack=0.0002, curve=9.0)
    click = biquad(click, "hp", 2600.0, 0.8)
    add(y, 0.0, click, 0.20)
    return y


# ------------------------------------------------------------------- 1. draw
# Desteden tas cekme: taslarin birbirinden ayrilirken cikardigi hafif
# surtunme + tasi kaldirirken olusan yumusak tik.
d = zeros(0.30)
scrape = envelope(noise(0.075, 5), attack=0.012, curve=3.0)
scrape = biquad(scrape, "bp", 2100.0, 1.1)
scrape = biquad(scrape, "hp", 900.0, 0.7)
add(d, 0.0, scrape, 0.30)
add(d, 0.045, tile_click(seed=3, bright=1.05, body=0.95, dur=0.2), 0.75)
d = reverb(d, mix=0.08, rt=0.30)
write("draw.wav", d, loud=0.105, comp=(0.10, 8.0))

# ---------------------------------------------------------------- 2. discard
# Tasi iskartaya birakma: masaya carpan tok bir "tak", biraz daha govdeli
# ve odanin yankisi belirgin.
d = zeros(0.36)
add(d, 0.0, tile_click(seed=7, bright=0.92, body=1.15, dur=0.30, damp=1.25), 1.0)
thud = modal_hit([(210, 0.06, 1.0), (330, 0.045, 0.5)], 0.16, exc_ms=2.5, seed=8)
add(d, 0.0, thud, 0.30)  # masanin ahsap tepkisi
d = reverb(d, mix=0.14, rt=0.38)
write("discard.wav", d, loud=0.105, comp=(0.10, 8.0))

# ------------------------------------------------------------------- 3. meld
# Per acma: uc tas art arda masaya diziliyor. Insan eli hicbir zaman
# metronom gibi degildir — araliklar ve tonlar hafifce degisiyor.
d = zeros(0.62)
for k, (t, sd, br, bd) in enumerate(
    ((0.000, 11, 1.02, 0.98), (0.088, 12, 0.97, 1.06), (0.171, 13, 1.06, 1.00))
):
    add(d, t, tile_click(seed=sd, bright=br, body=bd, dur=0.26), 0.95 - 0.06 * k)
# son tas yerine otururken hafif bir "kayma"
slide = envelope(noise(0.05, 21), attack=0.008, curve=4.0)
add(d, 0.20, biquad(slide, "bp", 3000.0, 1.4), 0.16)
d = reverb(d, mix=0.13, rt=0.36)
write("meld.wav", d, loud=0.103, comp=(0.10, 8.0))

# ---------------------------------------------------------------- 4. process
# Masadaki pere tas isleme: tas, duran taslarin YANINA denk gelir — iki
# yuzeyin birbirine surtunup oturdugu kisa cift temas.
d = zeros(0.32)
add(d, 0.0, tile_click(seed=17, bright=1.12, body=0.88, dur=0.22, damp=0.8), 0.85)
add(d, 0.032, tile_click(seed=18, bright=1.05, body=0.92, dur=0.24, damp=0.9), 0.60)
d = reverb(d, mix=0.10, rt=0.32)
write("process.wav", d, loud=0.119, comp=(0.10, 8.0))


# --------------------------------------------------------------- 5. your_turn
def bell(f0, dur, partials, mallet=0.25, seed=31, detune=0.0016):
    """Vurmali metal/cam zil: inharmonik kismi tonlar + tokmak gurultusu.

    Her kismi ton hafifce cift (detune) uretilir; gercek zillerdeki 'vurus'
    (beating) etkisi buradan gelir.
    """
    n = int(SR * dur)
    exc = excitation(1.0, 8.0, seed, n)
    out = [0.0] * n
    for ratio, amp, decay in partials:
        f = f0 * ratio
        resonate(exc, f, dur * decay, amp, out)
        resonate(exc, f * (1.0 + detune), dur * decay, amp * 0.7, out)
    if mallet:
        m = envelope(noise(0.008, seed + 5), attack=0.0004, curve=8.0)
        m = biquad(m, "bp", f0 * 2.2, 0.9)
        add(out, 0.0, m, mallet)
    return out


# Sira sende: yumusak, davetkar bir cam zil — iki notali kucuk bir motif.
d = zeros(1.05)
PART = ((1.00, 1.00, 0.95), (2.02, 0.42, 0.62), (3.05, 0.24, 0.42),
        (4.21, 0.13, 0.30), (5.44, 0.07, 0.22))
add(d, 0.00, bell(784.0, 0.85, PART, mallet=0.20, seed=33), 0.85)
add(d, 0.135, bell(1046.5, 0.88, PART, mallet=0.16, seed=34), 0.75)
d = reverb(d, mix=0.20, rt=0.65)
write("your_turn.wav", d, loud=0.149, comp=(0.20, 4.0))

# ----------------------------------------------------------- 6. time_warning
# Sure bitiyor: duvar saatinin tik-tak'i, hizlanarak. Bip yerine saat sesi,
# "zaman doluyor"u anlatmanin en dogal yolu.
d = zeros(0.95)


def tick(seed, high=1.0, level=1.0):
    modes = [
        (1450 * high, 0.032, 0.70),
        (2950 * high, 0.022, 1.00),
        (4900 * high, 0.012, 0.50),
        (8200 * high, 0.006, 0.25),
    ]
    y = modal_hit(modes, 0.10, exc_ms=0.7, sharpness=9.0, seed=seed)
    return [v * level for v in y]


for t, sd, hi, lv in (
    (0.00, 51, 1.00, 0.80),
    (0.24, 52, 0.86, 0.86),   # "tak" — biraz daha pes
    (0.44, 53, 1.00, 0.92),
    (0.60, 54, 0.86, 1.00),
    (0.72, 55, 1.00, 1.00),   # hizlaniyor: zaman doluyor
):
    add(d, t, tick(sd, hi, lv))
d = reverb(d, mix=0.11, rt=0.35)
write("time_warning.wav", d, loud=0.135, comp=(0.08, 10.0))


# ---------------------------------------------------------------- 7. win
def applause(dur, claps=95, seed=61):
    """Alkis: tek tek el cirpmalarin toplami.

    Her cirpma kisa bir gurultu darbesidir; zamanlari rastgele, yogunlugu
    once artip sonra azalir — kalabalik bir alkisin istatistigi budur.
    """
    rnd = random.Random(seed)
    n = int(SR * dur)
    out = [0.0] * n
    for k in range(claps):
        # yogunluk zarfi: hizli yukselis, yavas dusus
        u = rnd.random()
        t = (u ** 0.55) * dur * 0.80
        amp = rnd.uniform(0.35, 1.0) * (1.0 - t / (dur * 1.15))
        ln = rnd.randint(int(SR * 0.004), int(SR * 0.010))
        cl = [rnd.uniform(-1.0, 1.0) for _ in range(ln)]
        cl = [cl[i] * math.exp(-6.0 * i / ln) for i in range(ln)]
        cl = biquad(cl, "bp", rnd.uniform(1100.0, 3200.0), rnd.uniform(0.7, 1.5))
        add(out, t, cl, amp)
    # kalabaligin genel ugultusu
    bed = envelope(noise(dur * 0.9, seed + 3), attack=0.05, curve=2.2)
    bed = biquad(biquad(bed, "hp", 700.0, 0.7), "lp", 5200.0, 0.7)
    add(out, 0.0, bed, 0.22)
    return out


# Kazandin: kisa bir alkis + ustune parlak, yukselen zil motifi.
d = zeros(1.75)
add(d, 0.02, applause(1.55), 0.85)
for k, (f, t) in enumerate(((659.3, 0.00), (830.6, 0.10), (987.8, 0.20),
                            (1318.5, 0.31))):
    add(d, t, bell(f, 1.0, PART, mallet=0.18, seed=70 + k), 0.55 - 0.05 * k)
d = reverb(d, mix=0.22, rt=0.75)
write("win.wav", d, loud=0.150, comp=(0.25, 3.5))


# ---------------------------------------------------------------- 8. lose
def piano_note(f0, dur, seed=81, brightness=1.0):
    """Cekicli telli calgi: inharmonik harmonikler + cekic gurultusu.

    Yuksek harmonikler daha hizli sonumlenir; piyanonun 'canli' tinisi
    buradan gelir. B: tel sertligi (inharmonisite) katsayisi.
    """
    n = int(SR * dur)
    exc = excitation(1.2, 7.0, seed, n)
    out = [0.0] * n
    B = 0.00035
    for k in range(1, 13):
        f = f0 * k * math.sqrt(1.0 + B * k * k)
        if f > SR * 0.45:
            break
        amp = (1.0 / (k ** 1.35)) * (brightness if k > 3 else 1.0)
        resonate(exc, f, dur * (0.95 / (k ** 0.45)), amp, out)
    hammer = envelope(noise(0.012, seed + 9), attack=0.0006, curve=7.0)
    hammer = biquad(hammer, "bp", f0 * 4.0, 0.8)
    add(out, 0.0, hammer, 0.10)
    return out


# Kaybettin: inen kucuk ucluk — agir, sonuk, "of" dedirten bir kapanis.
d = zeros(1.45)
for k, (f, t, a) in enumerate(
    ((329.6, 0.00, 1.00), (277.2, 0.17, 0.92), (220.0, 0.34, 0.88))
):
    add(d, t, piano_note(f, 1.05, seed=81 + k, brightness=0.55), a)
# alt oktavda kalin bir kapanis
add(d, 0.34, piano_note(110.0, 1.05, seed=90, brightness=0.35), 0.55)
d = reverb(d, mix=0.18, rt=0.60)
write("lose.wav", d, loud=0.150, comp=(0.20, 4.0))


# ---------------------------------------------------------------- 9. laugh
def voice(dur, f0_start, f0_end, formants, seed=101, jitter=0.012,
          breath=0.0):
    """Formant (vokal trakti) sentezi.

    Rosenberg glotal darbe dizisi -> paralel formant rezonatorleri.
    Konusan/gulen bir insan sesinin klasik modeli; /a/ formantlariyla
    'ha' hecesi cikar.
    """
    rnd = random.Random(seed)
    n = int(SR * dur)
    src = [0.0] * n
    i = 0
    while i < n:
        f0 = f0_start + (f0_end - f0_start) * (i / n)
        f0 *= 1.0 + rnd.uniform(-jitter, jitter)   # dogal pitch titremesi
        period = max(8, int(SR / f0))
        t1 = int(period * 0.40)   # acilma
        t2 = int(period * 0.16)   # kapanma
        for k in range(period):
            if i + k >= n:
                break
            if k < t1:
                g = 0.5 * (1.0 - math.cos(math.pi * k / t1))
            elif k < t1 + t2:
                g = math.cos(math.pi * (k - t1) / (2.0 * t2))
            else:
                g = 0.0
            src[i + k] += g
        i += period
    mean = sum(src) / n
    src = [v - mean for v in src]
    if breath:
        nz = noise(dur, seed + 7)
        src = [src[i] + nz[i] * breath for i in range(n)]
    out = [0.0] * n
    for f, bw, amp in formants:
        r = math.exp(-math.pi * bw / SR)
        t60 = LN1000 / (-math.log(max(1e-9, r)) * SR)
        resonate(src, f, t60, amp, out)
    return out


# Rakip islek tas atti: alayci bir kahkaha. /a/ formantlari (F1 730,
# F2 1090, F3 2440, F4 3400) ile "ha ha ha ha".
VOWEL_A = ((730.0, 70.0, 1.00), (1090.0, 100.0, 0.55),
           (2440.0, 130.0, 0.26), (3400.0, 190.0, 0.12))
d = zeros(1.05)
syll = ((0.000, 0.135, 245.0, 205.0, 1.00),
        (0.185, 0.130, 228.0, 192.0, 0.92),
        (0.360, 0.125, 212.0, 178.0, 0.80),
        (0.520, 0.140, 196.0, 158.0, 0.64),
        (0.700, 0.150, 182.0, 140.0, 0.44))
for k, (t, ln, fa, fb, amp) in enumerate(syll):
    # "h" nefesi — heceyi gercekci baslatir
    h = envelope(noise(0.026, 110 + k), attack=0.004, curve=3.0)
    hf = [0.0] * len(h)
    for f, bw, a in VOWEL_A:
        r = math.exp(-math.pi * bw * 2.5 / SR)
        resonate(h, f, LN1000 / (-math.log(r) * SR), a, hf)
    add(d, t, hf, 0.22 * amp)
    v = voice(ln, fa, fb, VOWEL_A, seed=101 + k, breath=0.03)
    v = envelope(v, attack=0.010, curve=3.2)
    add(d, t + 0.020, v, amp)
d = biquad(d, "hp", 130.0, 0.7)
d = biquad(d, "lp", 6500.0, 0.7)   # agiz/mikrofon bant sinirlamasi
d = reverb(d, mix=0.13, rt=0.40)
write("laugh.wav", d, loud=0.128, comp=(0.35, 2.5))

# ---------------------------------------------------------------- 10. error
# Gecersiz hamle: yaris programi zili gibi kaba, alcak bir vizilti.
# Iki dissonant testere dalgasi + 33 Hz genlik modulasyonu + hafif kirpma.
d = zeros(0.42)
n = int(SR * 0.30)
buz = [0.0] * n
for i in range(n):
    t = i / SR
    s = 0.0
    for f, a in ((112.0, 1.0), (139.0, 0.85), (224.0, 0.35)):
        ph = (f * t) % 1.0
        s += a * (2.0 * ph - 1.0)          # testere
    am = 0.55 + 0.45 * (1.0 if math.sin(2 * math.pi * 33.0 * t) > 0 else -1.0)
    buz[i] = math.tanh(1.9 * s * 0.45) * am
buz = envelope(buz, attack=0.004, hold=0.20, curve=7.0)
buz = biquad(biquad(buz, "hp", 90.0, 0.7), "lp", 2100.0, 0.9)
add(d, 0.0, buz)
d = reverb(d, mix=0.08, rt=0.28)
write("error.wav", d, loud=0.132)

print("\nToplam: %.1f KB" % (
    sum(os.path.getsize(os.path.join(OUT, f))
        for f in os.listdir(OUT) if f.endswith(".wav")) / 1024.0))
