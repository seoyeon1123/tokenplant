#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""움직이는 정원을 GIF 로 굽는다 — 소개 글·README 에 붙일 것.

    python3 verify/gen_gif.py [--out garden.gif] [--scale 6] [--tier yard]

화면 녹화를 안 하는 이유: 앱 창을 찍으면 창틀·그림자·커서가 같이 들어가고
배율이 정수로 안 떨어져 픽셀이 뭉갠다. 여기서는 `GardenComposer` 와 **같은 식**으로
격자를 조립해 정수 배율로 확대하므로, 앱에서 보는 것과 픽셀 단위로 같다.

스프라이트·팔레트·레이아웃은 전부 Swift 소스에서 읽는다 — 값을 여기 베껴두면
앱을 고친 뒤 GIF 만 옛날 모습으로 남는다.
"""

import argparse
import importlib.util
import pathlib
import re
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCENE = ROOT / "Sources/TokenPlant/UI/GardenScene.swift"


def _load(name):
    spec = importlib.util.spec_from_file_location(name, pathlib.Path(__file__).with_name(f"{name}.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


DECOR = _load("gen_decor")
SP = _load("preview_species")


# ── 씬 레이아웃 — SceneLayout 에서 읽는다 ────────────────────────

def layouts():
    """`SceneLayout.all` 을 Swift 에서 그대로 읽는다."""
    s = SCENE.read_text(encoding="utf-8")
    body = s[s.index("static let all: [SceneLayout]"):]
    body = body[: body.index("\n    ]")]
    out = {}
    for chunk in body.split(".init(key:")[1:]:
        key = re.match(r'\s*"([^"]+)"', chunk).group(1)
        w = int(re.search(r"width: (\d+)", chunk).group(1))
        h = int(re.search(r"height: (\d+)", chunk).group(1))
        feats = set(re.findall(r"\.(\w+)", chunk[chunk.index("features:"): chunk.index("rows:")]))
        rows = [(int(b), [int(x) for x in xs.split(",") if x.strip()])
                for b, xs in re.findall(r"baseline: (\d+), xs: \[([^\]]*)\]", chunk)]
        out[key] = dict(width=w, height=h, features=feats, rows=rows)
    return out


def seasons():
    s = SCENE.read_text(encoding="utf-8")
    body = s[s.index("static let all: [SeasonPalette]"):]
    body = body[: body.index("\n    ]")]
    out = {}
    for chunk in body.split(".init(key:")[1:]:
        key = re.match(r'\s*"([^"]+)"', chunk).group(1)
        d = dict(re.findall(r"(\w+): \"(#[0-9a-fA-F]{6})\"", chunk))
        d["extraHaze"] = float(re.search(r"extraHaze: ([\d.]+)", chunk).group(1))
        out[key] = d
    return out


OUTLINE = "#2b2016"


def blend(hex_a, hex_b, t):
    a, b = SP.rgb(hex_a), SP.rgb(hex_b)
    return "#%02x%02x%02x" % tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


# ── 조립 — GardenComposer.compose 와 같은 순서 ───────────────────

def compose(lay, season, trees, decor, bird, frame):
    W, H = lay["width"], lay["height"]
    horizon = int(H * 0.42)
    px = [[None] * W for _ in range(H)]

    def put(x, y, hexv):
        if hexv and 0 <= x < W and 0 <= y < H:
            px[y][x] = hexv

    for y in range(H):
        for x in range(W):
            put(x, y, season["sky"] if y < horizon
                else (season["grass"] if (x + y) % 4 < 2 else season["grass2"]))

    if "glass" in lay["features"]:
        for y in range(horizon):
            for x in range(W):
                put(x, y, "#8fa8ad" if (x % 14 == 0 or y % 12 == 0) else "#cfe0e4")
        for x in range(W):
            put(x, horizon - 1, OUTLINE)

    if "fence" in lay["features"]:
        top = max(0, horizon - 10)
        for y in range(top, horizon):
            for x in range(W):
                put(x, y, season["fence"] if x % 6 < 4 else season["fence2"])
        for x in range(W):
            put(x, top, OUTLINE)

    if "sill" in lay["features"]:
        for y in range(horizon, min(horizon + 6, H)):
            for x in range(W):
                put(x, y, season["fence"] if y < horizon + 4 else season["fence2"])
        for x in range(W):
            put(x, horizon, OUTLINE)

    if "path" in lay["features"]:
        for y in range(max(0, H - 8), H):
            for x in range(W):
                put(x, y, season["path"] if (x * 3 + y) % 5 != 0 else "#ad8f63")

    if "pond" in lay["features"]:
        cx, cy, rx, ry = int(W * 0.78), H - 13, 15.0, 6.0
        for y in range(cy - 7, cy + 8):
            for x in range(cx - 16, cx + 17):
                d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
                if d <= 1:
                    put(x, y, season["water"])
                elif d <= 1.35:
                    put(x, y, OUTLINE)
        for k in range(4):
            put(cx - 6 + k * 2, cy - 2, "#dff0f8")

    # 그루 — 뒷줄부터. 뒷줄은 하늘색 쪽으로 물린다(대기 원근)
    shapes = SP.garden_shapes()
    shade = SP.shade_map()
    n = max(1, len(lay["rows"]))
    idx = 0
    for ri, (baseline, xs) in enumerate(lay["rows"]):
        haze = 0.22 * (1 - ri / (n - 1)) if n > 1 else 0
        if season["extraHaze"] > 0:
            haze = season["extraHaze"] + haze * 0.6
        for x in xs:
            if idx >= len(trees):
                break
            sp = trees[idx]
            idx += 1
            art = SP.decorate(SP.compose_garden(sp["shape"], sp["motif"], shapes), [], shade)
            for gy, row in enumerate(art):
                for gx, ch in enumerate(row):
                    hexv = SP.color_for(ch, sp, PLANT_PAL)
                    if not hexv:
                        continue
                    put(x + gx, baseline + gy - 16,
                        blend(hexv, season["sky"], haze) if haze > 0 else hexv)
    # 장식 — 그루보다 **나중에**. 앞쪽 바닥에 서니까 앞줄 나무보다 앞이다.
    # 자리 계산식은 SceneLayout.decorSpots 와 같다(16+2 간격 한 줄)
    step, base_y = DECOR.SIZE + 2, H - 2
    for i, key in enumerate(decor):
        art = frame_art(key, frame)
        for gy, row in enumerate(art):
            for gx, ch in enumerate(row):
                if ch != ".":
                    put(3 + i * step + gx, base_y + gy - DECOR.SIZE, PAL[ch])

    # 새 — 장식 **다음에** 그린다
    if bird:
        art = DECOR.BIRD[bird["art"]]
        for gy, row in enumerate(art):
            for gx, ch in enumerate(row):
                if ch == ".":
                    continue
                col = DECOR.SIZE - 1 - gx if bird["flip"] else gx
                put(bird["x"] + col, bird["y"] + gy - DECOR.SIZE, PAL[ch])

    return px


def frame_art(key, frame):
    """DecorIcons.grid(_:frame:) 포팅 — 0번은 ART, 나머지는 ANIM."""
    extra = DECOR.ANIM.get(key, [])
    if not extra:
        return DECOR.ART[key]
    i = frame % (len(extra) + 1)
    return DECOR.ART[key] if i == 0 else extra[i - 1]


# ── 새 동선 — BirdFlight 포팅 ────────────────────────────────────

LANDING, IDLE = 8, 40
PERCHED, FLYING, PECKING = 0, 1, 2


def bird_pose(to, start, elapsed):
    if elapsed < LANDING:
        t = min(max(elapsed + 1, 0), LANDING) / LANDING
        ease = 1 - (1 - t) ** 2
        return dict(x=round(start[0] + (to[0] - start[0]) * ease),
                    y=round(start[1] + (to[1] - start[1]) * ease),
                    art=FLYING, flip=to[0] < start[0])
    t = (elapsed - LANDING) % IDLE
    art = PECKING if t in (12, 13, 14, 18, 19, 20) else (FLYING if t == 32 else PERCHED)
    return dict(x=to[0], y=to[1], art=art, flip=to[0] < start[0])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT / "Resources/garden.gif"))
    ap.add_argument("--scale", type=int, default=6)
    ap.add_argument("--tier", default="yard")
    ap.add_argument("--frames", type=int, default=LANDING + IDLE)
    args = ap.parse_args()

    global PAL, PLANT_PAL
    PAL = DECOR.palette()
    PLANT_PAL = SP.base_palette()

    lay = layouts()[args.tier]
    season = seasons()["spring"]

    catalog = {s["id"]: s for s in SP.species_catalog()}
    trees = [catalog[i] for i in ("sunflower", "tomato", "lavender", "bamboo",
                                  "dandelion", "lettuce") if i in catalog]

    # 모이통을 가운데 두는 건 **구도 때문**이다. 맨 왼쪽에 두면 새가 오른쪽에서 날아와
    # 화면 끝에 앉아 바깥을 보고 끝난다 — 앱에서는 사용자가 끌어서 옮기면 되는 일이다.
    decor = ["windmill", "cat", "feeder", "birdbath", "mushroom"]
    step, base_y = DECOR.SIZE + 2, lay["height"] - 2
    perch = (3 + decor.index("feeder") * step, base_y)     # 모이통 앞
    start = (lay["width"] + 4, base_y - 16)               # 화면 밖 오른쪽

    images = []
    for f in range(args.frames):
        px = compose(lay, season, trees, decor, bird_pose(perch, start, f), f)
        img = Image.new("RGB", (lay["width"], lay["height"]))
        img.putdata([SP.rgb(c) for row in px for c in row])
        images.append(img.resize((lay["width"] * args.scale, lay["height"] * args.scale),
                                 Image.NEAREST))

    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    images[0].save(out, save_all=True, append_images=images[1:],
                   duration=200, loop=0, optimize=True)     # 200ms = 앱과 같은 5fps
    print(f"GIF: {out}  ({len(images)}프레임 · {out.stat().st_size // 1024}KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
