#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""쇼츠용 세로 영상(1080×1920)을 굽는다.

    python3 verify/gen_shorts.py [--out shorts.mp4] [--fps 30]

GIF 와 같은 생각이다 — 화면 녹화를 하지 않고 **앱과 같은 식으로 격자를 조립해서**
프레임을 만든다. 창틀·커서가 안 들어가고 정수 배율이라 픽셀이 안 뭉갠다.
스프라이트·팔레트·레이아웃은 전부 Swift 소스에서 읽으므로 앱을 고치면 영상도 따라온다.

구성 (23.5초):
    0.0–2.5  제목
    2.5–9.5  화분 하나가 Lv.1 → Lv.10
    9.5–15.0 정원이 넓어진다 — 베란다에서 비밀의 숲까지
    15.0–20.0 살아 있는 정원 — 새가 날아와 앉는다
    20.0–23.5 설치

자막은 장면 안에 박지 않고 `CAPTIONS` 한 군데에 **초 단위로** 모아둔다. 장면 함수가
제 문구를 들고 있으면 길이를 바꿀 때마다 문구가 어긋나고, 전체 대본을 한눈에 못 본다.
"""

import argparse
import importlib.util
import pathlib
import shutil
import subprocess
import sys
import wave

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODEL = ROOT / "Sources/TokenPlant/Core/PlantModel.swift"
W, H = 1080, 1920
FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"

SKY = (207, 228, 239)
CREAM = (250, 248, 242)
INK = (43, 32, 22)
GREEN = (62, 142, 93)
GREY = (138, 132, 122)


def _load(name):
    spec = importlib.util.spec_from_file_location(
        name, pathlib.Path(__file__).with_name(f"{name}.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


SP = _load("preview_species")
GIF = _load("gen_gif")
DECOR = _load("gen_decor")


def font(size, mono=False):
    return ImageFont.truetype(MONO if mono else FONT, size)


def center(d, y, text, f, fill=INK):
    w = d.textbbox((0, 0), text, font=f)[2]
    d.text(((W - w) // 2, y), text, font=f, fill=fill)


# ── 대본 ────────────────────────────────────────────────────────
#
# (장면, 문구). `\n` 으로 줄을 나눈다. 한 줄은 16자 안쪽으로 — 그보다 길면
# 세로 화면에서 글자가 작아져 엄지로 스크롤하다 읽히지 않는다.
# `*강조*` 로 감싼 토막은 초록색으로 뽑는다.
#
# **시각은 여기 안 적는다.** 나레이션을 붙이면 줄마다 읽는 길이가 다르고, 초를 손으로
# 적어두면 목소리를 다시 뽑을 때마다 열두 줄을 전부 고쳐야 한다. 음성 파일 길이에서
# `timeline()` 이 계산하고, **장면 길이도 거기서 나온다** — 말이 끝나기 전에 장면이
# 넘어가는 일이 구조적으로 안 생긴다.

SCRIPT = [
    ("제목",        "터미널에서 쓴 토큰이\n그대로 *물*이 됩니다"),
    ("성장",        "따로 켤 것도\n누를 것도 없어요"),
    ("성장",        "씨앗에서 거목까지\n*10단계*"),
    ("성장",        "메뉴바에 띄워두면\n알아서 크고 있습니다"),
    ("정원",        "화분에는\n곧바로 새 씨앗이"),
    ("정원",        "그루가 늘수록\n정원이 *넓어지고*"),
    ("정원",        "*비밀의 숲*까지\n모두 일곱 단계"),
    ("살아있는 정원", "상점에서 *장식*을 사서\n정원에 놓으면"),
    ("살아있는 정원", "바람개비가 돌고\n고양이가 꼬리를 흔들고"),
    ("살아있는 정원", "*모이통* 앞엔\n새가 내려앉습니다"),
    ("설치",        "한 줄이면 설치됩니다"),
    ("설치",        "무료 · 오픈소스\n*깃허브*에 있어요"),
]

LEAD = 0.6         # 첫 말이 나오기 전 여백
GAP = 0.45         # 줄 사이 숨
TAIL = 1.0         # 마지막 말 뒤 여백 — 설치 명령어를 읽을 시간이다
CAPTIONS = []      # timeline() 이 채운다: (시작초, 끝초, 문구)

CAP_BOTTOM = 1790          # 자막 상자의 아랫변
CAP_FADE = 0.12            # 초. 뚝 끊기면 싸구려로 보인다
CAP_TEXT = (252, 250, 245)
CAP_HI = (146, 222, 165)   # 어두운 상자 위라 본문 GREEN 은 안 읽힌다 — 밝게 올린다


def speech_lengths(voice):
    """나레이션 열두 줄의 길이(초). 음성이 없으면 글자 수로 어림잡는다."""
    if voice is None:
        # 목소리 없이도 스크립트가 돌아야 한다 — 자막만 있는 판을 굽는 경우.
        return [0.17 * len(t.replace("\n", "").replace("*", "")) + 0.7
                for _, t in SCRIPT]
    out = []
    for i in range(1, len(SCRIPT) + 1):
        with wave.open(str(voice / f"{i:02d}.wav"), "rb") as w:
            out.append(w.getnframes() / w.getframerate())
    return out


def timeline(voice):
    """대본 → (자막 구간, 장면별 초). `CAPTIONS` 를 채우고 둘 다 돌려준다."""
    durs = speech_lengths(voice)
    cues, scene_secs = [], {}
    t = LEAD
    for (scene, text), d in zip(SCRIPT, durs):
        cues.append((t, t + d, text))
        scene_secs[scene] = scene_secs.get(scene, 0.0) + d + GAP
        t += d + GAP
    scene_secs[SCRIPT[0][0]] += LEAD
    scene_secs[SCRIPT[-1][0]] += TAIL - GAP
    CAPTIONS[:] = cues
    return cues, scene_secs


def _segments(line):
    """`*강조*` 를 (글자, 색) 토막으로 쪼갠다."""
    out, rest = [], line
    while "*" in rest:
        head, _, rest = rest.partition("*")
        if head:
            out.append((head, None))
        body, _, rest = rest.partition("*")
        if body:
            out.append((body, CAP_HI))
    if rest:
        out.append((rest, None))
    return out or [(line, None)]


def draw_caption(canvas, t):
    """t초 시점의 자막을 얹는다. 없으면 그대로 둔다."""
    cue = next((c for c in CAPTIONS if c[0] <= t < c[1]), None)
    if cue is None:
        return canvas
    start, end, text = cue
    alpha = min(1.0, (t - start) / CAP_FADE, (end - t) / CAP_FADE)

    f = font(58)
    lines = text.split("\n")
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    lh, pad_x, pad_y = 78, 46, 28
    widths = [probe.textbbox((0, 0), l.replace("*", ""), font=f)[2] for l in lines]
    bw = min(W - 60, max(widths) + pad_x * 2)
    bh = lh * (len(lines) - 1) + 78 + pad_y * 2
    bx, by = (W - bw) // 2, CAP_BOTTOM - bh

    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle([bx, by, bx + bw, by + bh], 26, fill=INK + (235,))
    y = by + pad_y
    for line, wdt in zip(lines, widths):
        x = (W - wdt) // 2
        for chunk, color in _segments(line):
            d.text((x, y), chunk, font=f, fill=(color or CAP_TEXT) + (255,))
            x += probe.textbbox((0, 0), chunk, font=f)[2]
        y += lh

    if alpha < 1:
        layer.putalpha(layer.getchannel("A").point(lambda v: int(v * alpha)))
    return Image.alpha_composite(canvas.convert("RGBA"), layer).convert("RGB")


def grid_image(px, scale):
    """hex 격자 → 정수 배율 확대 이미지."""
    h, w = len(px), len(px[0])
    im = Image.new("RGB", (w, h))
    im.putdata([SP.rgb(c) if c else (0, 0, 0) for row in px for c in row])
    return im.resize((w * scale, h * scale), Image.NEAREST)


def paste_center(canvas, im, y):
    canvas.paste(im, ((W - im.width) // 2, y))


def paste_middle(canvas, im, cy):
    """세로 **중심**을 맞춘다 — 티어마다 높이가 달라서 위를 맞추면 바닥이 널뛴다."""
    canvas.paste(im, ((W - im.width) // 2, cy - im.height // 2))


def crop(px, x0, x1):
    """격자를 세로로 잘라낸다. 확대 전에 잘라야 정수 배율이 유지된다."""
    return [row[x0:x1] for row in px]


def fit_width(width, slack=2):
    """격자 폭 → (정수 배율, 자를 범위). 픽셀아트라 배율은 정수여야 한다.

    내림만 쓰면 `forest`(272) 가 ×3=816 이라 1080 안에서 쪼그라든다. 한 칸 올려서
    ×4=1088 로 키우고 넘치는 **2칸만** 잘라낸다. 많이 잘라야 하는 티어는
    가장자리 그루가 반쯤 잘리므로 그냥 내림을 쓴다.
    """
    up = -(-W // width)                      # ceil
    cols = W // up
    if up > 1 and width - cols <= slack:
        x0 = (width - cols) // 2
        return up, x0, x0 + cols
    return max(1, W // width), 0, width


def tiers():
    """`GardenTier.all` 에서 이름을 읽는다 — 앱에서 티어 이름을 고치면 영상도 따라온다."""
    import re
    s = MODEL.read_text(encoding="utf-8")
    body = s[s.index("static let all: [GardenTier]"):]
    body = body[: body.index("\n    ]")]
    out = []
    for key, name in re.findall(r'\.init\(key: "(\w+)",\s*name: "([^"]+)"', body):
        out.append((key, name))
    return out


# ── 1. 제목 ─────────────────────────────────────────────────────

def scene_title(n):
    icon = Image.open(ROOT / "Resources/AppIcon-512.png").convert("RGBA")
    icon = icon.resize((420, 420), Image.NEAREST)
    out = []
    for i in range(n):
        c = Image.new("RGB", (W, H), SKY)
        d = ImageDraw.Draw(c)
        # 아이콘이 살짝 떠올랐다 가라앉는다. 정지 화면으로 시작하면 넘겨진다.
        lift = int(14 * (1 - min(1.0, i / 18)))
        c.paste(icon, ((W - 420) // 2, 540 - lift), icon)
        center(d, 1060, "AI 토큰으로", font(84))
        center(d, 1180, "식물 키우기", font(104), GREEN)
        center(d, 1400, "TokenPlant", font(52, mono=True), GREY)
        out.append(c)
    return out


# ── 2. 화분 성장 ────────────────────────────────────────────────

def scene_growth(n):
    palette, shade = SP.base_palette(), SP.shade_map()
    pot = SP.pot_rows()
    stages = SP.stage_silhouettes()
    foliage = [SP.strip_blooms(rows) for _, rows in stages]
    sp = next(s for s in SP.species_catalog() if s["id"] == "sunflower")
    motif = sp.get("motif") or SP.SPECIES_MOTIF[sp["id"]]

    cells = []
    for i in range(len(stages)):
        art = SP.compose(i, motif, foliage)
        g = SP.decorate(art, pot, shade)
        cells.append(SP.render_cell(g, sp, palette, 28))   # 24px × 28 = 672

    per = n / len(cells)
    out = []
    for i in range(n):
        idx = min(len(cells) - 1, int(i / per))
        c = Image.new("RGB", (W, H), CREAM)
        d = ImageDraw.Draw(c)
        center(d, 190, "Claude Code 를 쓰면", font(68), GREY)
        center(d, 300, "식물이 자랍니다", font(92))

        im = cells[idx]
        c.paste(im, ((W - im.width) // 2, 560), im)

        center(d, 1420, f"Lv.{idx + 1}  {stages[idx][0]}", font(64), GREEN)
        # 게이지 — 단계가 올라갈수록 찬다
        bw, bh, bx, by = 760, 22, (W - 760) // 2, 1520   # 자막 상자 위로 비켜둔다
        d.rounded_rectangle([bx, by, bx + bw, by + bh], bh // 2, fill=(228, 224, 214))
        fill = int(bw * (idx + 1) / len(cells))
        d.rounded_rectangle([bx, by, bx + fill, by + bh], bh // 2, fill=GREEN)
        out.append(c)
    return out


# ── 3. 정원이 채워진다 ──────────────────────────────────────────

def scene_garden(n):
    """정원이 **넓어지는** 장면. 한 티어에서 그루 수만 올리면 나무가 점처럼 보여서
    화면이 비어 있다 — 티어를 넘기면 배율이 같이 커지므로 매 컷이 꽉 찬다."""
    lays, season = GIF.layouts(), GIF.seasons()["spring"]
    catalog = SP.species_catalog()
    names = dict(tiers())

    shots = []
    for key in ("balc", "bed", "yard", "green", "arbor", "forest"):
        lay = lays[key]
        slots = sum(len(xs) for _, xs in lay["rows"])
        trees = [catalog[i % len(catalog)] for i in range(slots)]
        px = GIF.compose(lay, season, trees, [], None, 0)
        scale, x0, x1 = fit_width(lay["width"])
        shots.append((grid_image(crop(px, x0, x1), scale), names[key], slots))

    per = n / len(shots)
    out = []
    for i in range(n):
        im, name, slots = shots[min(len(shots) - 1, int(i / per))]
        c = Image.new("RGB", (W, H), CREAM)
        d = ImageDraw.Draw(c)
        center(d, 230, "다 자라면", font(68), GREY)
        center(d, 340, "정원으로 옮겨집니다", font(92))
        paste_middle(c, im, 1020)
        center(d, 1400, f"{name}  ·  {slots}그루", font(76), GREEN)
        out.append(c)
    return out


# ── 4. 살아 있는 정원 ───────────────────────────────────────────

def scene_alive(n):
    lay = GIF.layouts()["yard"]
    season = GIF.seasons()["spring"]
    catalog = {s["id"]: s for s in SP.species_catalog()}
    trees = [catalog[i] for i in ("sunflower", "tomato", "lavender", "cherry",
                                  "dandelion", "lettuce") if i in catalog]
    decor = ["windmill", "cat", "feeder", "birdbath", "mushroom"]
    perch = dict(GIF.decor_placements(lay, decor))["feeder"]
    base_y = perch[1]
    start = (lay["width"] + 4, base_y - 16)
    # 136 전체를 ×7 로 넣으면 새(16px)가 112px 밖에 안 돼서 뭘 보라는 건지 모른다.
    # 장식 다섯 개가 다 들어가는 108칸만 잘라 ×10 으로 키운다 — 새가 160px 이 된다.
    # 새는 화면 밖(x=140)에서 날아오므로 잘라낸 뒤에도 오른쪽에서 들어온다.
    cx0, cx1 = 0, 108
    scale = W // (cx1 - cx0)                       # 108 → ×10 = 1080

    out = []
    for i in range(n):
        f = i // 6                                  # 30fps → 5fps 와 같은 리듬
        px = GIF.compose(lay, season, trees, decor, GIF.bird_pose(perch, start, f), f)
        c = Image.new("RGB", (W, H), CREAM)
        d = ImageDraw.Draw(c)
        center(d, 230, "정원은 가만히 있지 않아요", font(68), GREY)
        center(d, 340, "새가 날아옵니다", font(92))
        paste_middle(c, grid_image(crop(px, cx0, cx1), scale), 1000)
        out.append(c)
    return out


# ── 5. 설치 ─────────────────────────────────────────────────────

def scene_install(n):
    icon = Image.open(ROOT / "Resources/AppIcon-512.png").convert("RGBA")
    icon = icon.resize((240, 240), Image.NEAREST)
    out = []
    for _ in range(n):
        c = Image.new("RGB", (W, H), SKY)
        d = ImageDraw.Draw(c)
        c.paste(icon, ((W - 240) // 2, 420), icon)
        center(d, 740, "TokenPlant", font(88))
        center(d, 870, "macOS 14+", font(48), GREY)

        bx, by, bw, bh = 90, 1060, W - 180, 260
        d.rounded_rectangle([bx, by, bx + bw, by + bh], 24, fill=(38, 34, 30))
        d.text((bx + 48, by + 56), "brew tap seoyeon1123/tap",
               font=font(40, mono=True), fill=(170, 230, 180))
        d.text((bx + 48, by + 134), "brew install --cask tokenplant",
               font=font(40, mono=True), fill=(170, 230, 180))

        center(d, 1460, "github.com/seoyeon1123/tokenplant", font(46, mono=True), INK)
        out.append(c)
    return out


# ── 나레이션 ────────────────────────────────────────────────────

def prep_voice(src):
    """`say` 로 뽑은 01.aiff … 12.aiff 를 다듬어 build/voice/NN.wav 로 둔다.

    두 가지를 한다. **앞뒤 무음을 자르고**(`say` 는 말 앞뒤로 0.5초쯤 침묵을 붙인다 —
    그대로 쓰면 자막이 먼저 떠 있고 한참 뒤에 소리가 난다) **음량을 맞춘다**
    (줄마다 들쭉날쭉하면 볼륨을 계속 만지게 된다).
    """
    dst = ROOT / "build/voice"
    dst.mkdir(parents=True, exist_ok=True)
    trim = ("silenceremove=start_periods=1:start_silence=0.05:"
            "start_threshold=-45dB:detection=peak")
    for i in range(1, len(SCRIPT) + 1):
        raw = next((src / f"{i:02d}{e}" for e in (".aiff", ".aif", ".wav", ".m4a")
                    if (src / f"{i:02d}{e}").exists()), None)
        if raw is None:
            raise SystemExit(f"나레이션 {i:02d} 번 파일이 {src} 에 없습니다.")
        subprocess.run([
            "ffmpeg", "-y", "-loglevel", "error", "-i", str(raw),
            # 뒤쪽 무음은 뒤집어서 같은 필터를 한 번 더 먹인다
            "-af", f"{trim},areverse,{trim},areverse,loudnorm=I=-16:TP=-1.5:LRA=11",
            "-ar", "48000", "-ac", "1", str(dst / f"{i:02d}.wav"),
        ], check=True)
    return dst


def mux(video, voice, starts, out):
    """각 줄을 제 자막이 뜨는 순간에 놓고 영상에 붙인다."""
    args, filt = [], []
    for i, start in enumerate(starts):
        args += ["-i", str(voice / f"{i + 1:02d}.wav")]
        filt.append(f"[{i + 1}:a]adelay={round(start * 1000)}|{round(start * 1000)}[a{i}]")
    mix = "".join(f"[a{i}]" for i in range(len(starts)))
    # normalize=0 — 켜두면 줄이 겹치지 않는데도 열두 개로 나눠 소리가 작아진다.
    # apad — 마지막 말이 영상보다 먼저 끝난다. 이게 없으면 `-shortest` 가 소리에
    # 맞춰 **영상 끝을 잘라서** 설치 명령어를 읽을 1초가 통째로 사라진다.
    filt.append(f"{mix}amix=inputs={len(starts)}:normalize=0,apad[out]")
    subprocess.run([
        "ffmpeg", "-y", "-loglevel", "error", "-i", str(video), *args,
        "-filter_complex", ";".join(filt), "-map", "0:v", "-map", "[out]",
        "-c:v", "copy", "-c:a", "aac", "-b:a", "128k", "-shortest",
        "-movflags", "+faststart", str(out),
    ], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "Resources/shorts.mp4"))
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--voice", help="01..12 나레이션 음성이 있는 폴더 "
                                    "(verify/tp-voice.sh 가 만든다)")
    # 목소리를 CapCut 같은 바깥 편집기에서 입힐 때 쓴다. 길이는 `--voice` 로 잡고
    # 소리는 안 붙인다 — 자막 자리와 장면 길이가 그대로라 그 위에 얹기만 하면 된다.
    ap.add_argument("--silent", action="store_true", help="소리 없이 굽는다")
    # 자막까지 바깥 편집기에서 넣을 때. 장면 위의 제목 줄은 자막이 아니라 화면의
    # 일부라 그대로 둔다 — 그것까지 빼면 그냥 빈 배경에 그림만 남는다.
    ap.add_argument("--bare", action="store_true", help="자막 상자 없이 굽는다")
    args = ap.parse_args()

    GIF.PAL = DECOR.palette()
    GIF.PLANT_PAL = SP.base_palette()

    fps = args.fps
    voice = prep_voice(pathlib.Path(args.voice).expanduser()) if args.voice else None
    cues, secs = timeline(voice)
    scenes = [("제목", scene_title), ("성장", scene_growth), ("정원", scene_garden),
              ("살아있는 정원", scene_alive), ("설치", scene_install)]

    tmp = pathlib.Path("/tmp/tp-shorts")
    if tmp.exists():
        shutil.rmtree(tmp)
    tmp.mkdir(parents=True)

    # 자막은 장면을 다 만든 **뒤에** 전역 시각으로 얹는다. 장면 안에서 그리면
    # 장면 길이를 바꿀 때마다 대본을 따라 고쳐야 한다.
    n = 0
    for name, fn in scenes:
        frames = fn(round(secs[name] * fps))
        for im in frames:
            (im if args.bare else draw_caption(im, n / fps)).save(tmp / f"{n:05d}.png")
            n += 1
        print(f"  {name:12} {secs[name]:5.1f}초  {len(frames):4}프레임")

    # 대본이 영상보다 길면 뒷 자막이 통째로 안 나온다 — 조용히 사라지면 안 된다.
    over = [t for s, _, t in cues if s >= n / fps]
    if over:
        print("\n⚠ 영상 길이를 넘어가 안 나오는 자막:")
        for t in over:
            print(f"   {t.replace(chr(10), ' ')}")

    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    if args.silent:
        voice = None
        # 바깥 편집기에서 목소리를 얹으려면 **몇 초에 무슨 말인지** 가 필요하다.
        cue_file = out.with_suffix(".txt")
        cue_file.write_text(
            "\n".join(f"{s:6.2f}  {t.replace(chr(10), ' ').replace('*', '')}"
                      for s, _, t in cues) + "\n", encoding="utf-8")
        print(f"  대본 시각표: {cue_file}")
    silent = out.with_suffix(".silent.mp4") if voice else out
    subprocess.run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-framerate", str(fps), "-i", str(tmp / "%05d.png"),
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18",
        "-movflags", "+faststart", str(silent),
    ], check=True)
    shutil.rmtree(tmp)

    if voice:
        mux(silent, voice, [c[0] for c in cues], out)
        silent.unlink()
    print(f"\n영상: {out}  ({n}프레임 · {n / fps:.1f}초 · "
          f"{out.stat().st_size // 1024}KB{'  · 나레이션 포함' if voice else ''})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
