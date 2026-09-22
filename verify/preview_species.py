# -*- coding: utf-8 -*-
"""종 × 단계 대조표를 PNG 으로 렌더한다 — 조합 스프라이트를 눈으로 보고 다듬는 도구.

    python3 verify/preview_species.py            # 전체 대조표
    python3 verify/preview_species.py rose tulip # 몇 종만 크게

왜 파이썬인가: Swift 는 이 컨테이너에서 컴파일이 안 되고, 픽셀아트는 **보지 않고 고치면
반드시 망한다.** 그래서 합성 규칙을 여기서 먼저 굳히고, 확정된 데이터만 Swift 로 옮긴다.
`PlantSprites.swift` / `PlantModel.swift` 를 직접 읽으므로 출처는 하나다.
"""
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SPRITES = ROOT / "Sources/TokenPlant/Core/PlantSprites.swift"
MODEL = ROOT / "Sources/TokenPlant/Core/PlantModel.swift"
OUT = ROOT / "Resources/preview-species.png"

SIZE = 24
PLANT_ROWS = 17
BLOOM_CHARS = set("FYRrWfp")


# ── 기존 Swift 데이터 읽기 ───────────────────────────────────────

def base_palette():
    s = SPRITES.read_text(encoding="utf-8")
    at = s.index("static let base")
    body = s[s.index("[", s.index("=", at)):]
    body = body[: body.index("]")]
    return dict(re.findall(r'"(.)"\s*:\s*"(#[0-9a-fA-F]{6})"', body))


def shade_map():
    s = SPRITES.read_text(encoding="utf-8")
    at = s.index("static let shade")
    body = s[s.index("[", s.index("=", at)):]
    body = body[: body.index("]")]
    return dict(re.findall(r'"(.)"\s*:\s*"(.)"', body))


def pot_rows():
    s = SPRITES.read_text(encoding="utf-8")
    at = s.index("static let pot:")
    start = s.index("[", s.index("=", at))
    return re.findall(r'"([.A-Za-z]{24})"', s[start: s.index("]", start)])


def stage_silhouettes():
    """기존 10단계 실루엣 — 꽃이 아직 박혀 있는 원본."""
    s = SPRITES.read_text(encoding="utf-8")
    out = []
    for b in s.split(".init(level:")[1:]:
        name = re.search(r'name: "([^"]+)"', b).group(1)
        rows = re.findall(r'"([.A-Za-z]{24})"', b[: b.index("]),")])
        out.append((name, rows))
    return out


def species_catalog():
    s = MODEL.read_text(encoding="utf-8")
    at = s.index("static let catalog")
    body = s[at: s.index("\n    ]", at)]
    out = []
    # 필드 순서·추가에 안 깨지게 항목 단위로 자른 뒤 키별로 읽는다.
    # 전엔 한 줄 정규식이라 `motif:` 를 덧붙이자마자 0종이 파싱됐다.
    for chunk in body.split(".init(id:")[1:]:
        chunk = chunk[: chunk.index(")")]
        def field(key, default=None):
            m = re.search(rf'{key}: "([^"]*)"', chunk)
            return m.group(1) if m else default
        def bare(key):
            m = re.search(rf"{key}: \.(\w+)", chunk)
            return m.group(1) if m else None
        pid = re.match(r'\s*"([^"]+)"', chunk).group(1)
        out.append(dict(id=pid, name=field("name"), rarity=bare("rarity"),
                        shape=bare("shape"), leaf=field("leaf"),
                        leafLight=field("leafLight"), leafShade=field("leafShade"),
                        petal=field("petal"), motif=bare("motif")))
    if not out:
        sys.exit("종 카탈로그를 하나도 못 읽었다 — PlantModel.swift 형식이 바뀌었나?")
    return out


# ── 꽃을 떼어내 잎만 남긴다 ──────────────────────────────────────

def strip_blooms(rows):
    """꽃 픽셀을 잎(`G`)으로 덮어 **잎만 있는 바탕**을 만든다.

    투명하게 비우면 안 된다 — 꽃이 잎 덩이 **위에** 얹혀 있어서, 비우면 모티프가
    원본보다 작을 때 구멍이 남는다. 잎으로 채워 두면 어떤 크기의 모티프를 얹어도 자연스럽다.
    """
    out = []
    for r in rows:
        out.append("".join("G" if c in BLOOM_CHARS else c for c in r))
    return out


# 꽃이 붙는 자리 — 원본 실루엣의 꽃 덩이 무게중심을 그대로 고정했다.
# (row, col, 크기). 크기가 스탬프를 고른다.
ANCHORS = [
    [],                                                        # Lv.1 씨앗
    [],                                                        # Lv.2 발아
    [],                                                        # Lv.3 떡잎
    [],                                                        # Lv.4 어린잎
    [],                                                        # Lv.5 자란 줄기
    [(2, 11, "bud")],                                          # Lv.6 꽃봉오리
    [(3, 11, "big")],                                          # Lv.7 첫 꽃
    [(3, 11, "big"), (2, 3, "small"), (2, 19, "small")],       # Lv.8 만개
    [(2, 11, "big"), (2, 3, "small"), (2, 19, "small"),        # Lv.9 열매
     (6, 3, "fruit"), (6, 19, "fruit"), (9, 11, "fruit")],
    # 거목은 사이클의 끝이고 제일 오래 보는 그림이다. 여기가 전부 같으면
    # 앞 단계를 아무리 갈라도 "결국 같은 나무"로 남는다. 왕관에 종 모티프를 박는다.
    [(3, 7, "small"), (3, 16, "small"), (6, 11, "small")],      # Lv.10 거목
]

# 꽃봉오리는 종을 안 가린다 — 실제로도 봉오리는 다 비슷하게 생겼다. 꽃잎색만 살짝 비친다.
BUD = [
    ".F.",
    "GFG",
    ".G.",
]

# 열매는 종마다 다르다. 공용으로 두면 `.R./RRR/.R.` 이 빨간 **십자**로 렌더돼서
# 열매가 아니라 기호처럼 보인다(실제로 그렇게 나왔다).

# 모티프 — `big` 7x5, `small` 5x3, `fruit` 3x2. 앵커를 중심에 맞춘다.
#   `.` = 밑의 잎을 그대로 둔다   `_` = 구멍을 뚫는다   나머지 = 칠한다
#
# 열매를 3x3 으로 두면 안 된다: `.R./RRR/.R.` 은 **십자**로, 꽉 찬 3x3 은 **네모**로 보인다.
# 3x2 로 두고 아웃라인이 둘리게 하면 둥근 알처럼 읽힌다.
MOTIFS = {
    # 나팔꽃 - 위가 벌어지고 아래로 좁아지는 깔때기, 목구멍이 하얗다
    "trumpet": dict(big=[".FFFFF.",
                         "FFFFFFF",
                         "FFFWFFF",
                         "..FWF..",
                         "...Y..."],
                    small=[".FFF.",
                           "FFWFF",
                           ".FYF."],
                    fruit=["WOO",
                           "OOO"]),
    # 민들레 - 방사형 꽃잎 + 노란 가운데. 열매는 하얀 갓털
    "daisy": dict(big=["..F.F..",
                       ".FFFFF.",
                       "FFFYFFF",
                       ".FFFFF.",
                       "..F.F.."],
                  small=[".F.F.",
                         "FFYFF",
                         ".F.F."],
                  fruit=["WWW",
                         "WWW"]),
    # 해바라기 - 갈색 씨판이 크고 꽃잎이 테두리처럼 둘린다
    "sun": dict(big=[".FFFFF.",
                     "FFTTTFF",
                     "FTTTTTF",
                     "FFTTTFF",
                     ".FFFFF."],
                small=[".FFF.",
                       "FTTTF",
                       ".FFF."],
                fruit=["WTT",
                       "TTT"]),
    # 장미 - 겹꽃. 가운데가 안 보이고 층이 진다. 열매는 빨간 로즈힙
    "rosette": dict(big=[".FFFFF.",
                         "FFfFfFF",
                         "FfFFFfF",
                         "FFfFfFF",
                         ".FFFFF."],
                    small=[".FFF.",
                           "FfFfF",
                           ".FFF."],
                    fruit=["WRR",
                           "RRR"]),
    # 튤립 - 닫힌 컵. 위가 평평하고 끝이 갈라진다
    "cup": dict(big=["FF.F.FF",
                     "FFFFFFF",
                     "FFFFFFF",
                     ".FFFFF.",
                     "..FFF.."],
                small=["F.F.F",
                       "FFFFF",
                       ".FFF."],
                fruit=["Wyy",
                       "yyy"]),
    # 종꽃 - 매달린 종. 세계수가 쓴다
    "bell": dict(big=["...F...",
                      "..FFF..",
                      ".FFFFF.",
                      ".FFFFF.",
                      "..FWF.."],
                 small=["..F..",
                        ".FFF.",
                        ".FWF."],
                 fruit=["WOO",
                        "OOO"]),
    # 라벤더 - 좁고 긴 이삭. 마르면 탁한 노랑
    "spike": dict(big=["..FFF..",
                       "..FFF..",
                       ".FFFFF.",
                       "..FFF..",
                       "...F..."],
                  small=[".FFF.",
                         ".FFF.",
                         "..F.."],
                  fruit=["Wyy",
                         "yyy"]),
    # 벚꽃 - 작은 꽃이 송이로 몰려 핀다. 열매는 체리
    "cluster": dict(big=[".FF.FF.",
                         "FFFFFFF",
                         ".FWFWF.",
                         "FFFFFFF",
                         ".FF.FF."],
                    small=["FF.FF",
                           ".FWF.",
                           "FF.FF"],
                    fruit=["WRR",
                           "RRR"]),
    # 단풍 - 다섯 갈래. 열매는 갈색 시과
    "star": dict(big=["...F...",
                      ".FFFFF.",
                      "FFFFFFF",
                      ".FF.FF.",
                      ".F...F."],
                 small=[".F.F.",
                        "FFFFF",
                        "..F.."],
                 fruit=["WOO",
                        "OOO"]),
    # 방울토마토 - 꽃보다 열매가 주인공이다
    "berry": dict(big=["...G...",
                       "..RRR..",
                       ".RRRRR.",
                       ".RRRRR.",
                       "..RRR.."],
                  small=["..G..",
                         ".RRR.",
                         ".RRR."],
                  fruit=["WRR",
                         "RRR"]),
    # 선인장꽃 - 흰 가시 사이에서 핀다
    "needle": dict(big=["..WFW..",
                        ".FFFFF.",
                        "WFFYFFW",
                        ".FFFFF.",
                        "..WFW.."],
                   small=[".WFW.",
                          "FFYFF",
                          ".WFW."],
                   fruit=["WFF",
                          "FFF"]),
    # 무지개꽃 - 전설. 흰 빛이 섞여 반짝인다
    "aurora": dict(big=[".WFWFW.",
                        "FWFFFWF",
                        "WFFYFFW",
                        "FWFFFWF",
                        ".WFWFW."],
                   small=[".WFW.",
                          "WFYFW",
                          ".WFW."],
                   fruit=["WWW",
                          "WWW"]),
    # 상추 - 꽃이 없다. 밝은 잎이 주름처럼 엇갈리게 짜인다
    "ruffle": dict(big=[".LLLLL.",
                        "LGLGLGL",
                        "LLGLGLL",
                        "LGLGLGL",
                        ".LLLLL."],
                   small=[".LLL.",
                          "LGLGL",
                          ".LLL."],
                   fruit=["Wyy",
                          "yyy"]),
    # 몬스테라 - 꽃이 없다. **구멍**이 이 종의 전부라 밝은 잎맥을 세워 구멍을 또렷하게 한다
    "split": dict(big=[".GdLdG.",
                       "GddLddG",
                       "dddLddd",
                       "GddLddG",
                       ".GdLdG."],
                  small=[".dLd.",
                         "ddLdd",
                         ".dLd."],
                  fruit=["WOO",
                         "OOO"]),
    # 대나무 - 꽃이 없다. 곧은 줄기에 마디가 지고 잎이 좌우로 뻗는다
    "node": dict(big=[".L...L.",
                      "..LLL..",
                      ".LLLLL.",
                      "..LLL..",
                      ".L...L."],
                 small=["LL.LL",
                        ".LLL.",
                        "..L.."],
                 fruit=["yyy",
                        "yyy"]),
}

# 종 → 모티프. "꽃이 없는" 종끼리 안 겹치게 잎 특징으로 갈랐다.
SPECIES_MOTIF = {
    "dandelion": "daisy",
    "tomato": "berry",
    "lettuce": "ruffle",
    "sunflower": "sun",
    "morningglory": "trumpet",
    "rose": "rosette",
    "tulip": "cup",
    "lavender": "spike",
    "monstera": "split",
    "bamboo": "node",
    "maple": "star",
    "cherry": "cluster",
    "cactus": "needle",
    "worldtree": "bell",
    "rainbow": "aurora",
}


# ── 합성 ─────────────────────────────────────────────────────────

def stamp(grid, art, row, col):
    """`art` 를 (row, col) 중심에 찍는다. 격자 밖은 잘라낸다."""
    h, w = len(art), len(art[0])
    top, left = row - h // 2, col - w // 2
    for y in range(h):
        for x in range(w):
            ch = art[y][x]
            if ch == ".":
                continue                       # 밑의 잎을 그대로
            gy, gx = top + y, left + x
            if 0 <= gy < len(grid) and 0 <= gx < len(grid[0]):
                grid[gy][gx] = "." if ch == "_" else ch


def compose(stage_idx, motif_name, foliage_stages):
    """잎 바탕 + 꽃 스탬프 → 식물 17줄."""
    grid = [list(r) for r in foliage_stages[stage_idx]]
    motif = MOTIFS[motif_name]
    for row, col, size in ANCHORS[stage_idx]:
        art = BUD if size == "bud" else motif[size]
        stamp(grid, art, row, col)
    return ["".join(r) for r in grid]


def decorate(silhouette, tail, shade):
    """PlantSpriteBuilder.decorate 포팅 — 아웃라인·음영은 손으로 안 그린다."""
    rows = [list(r) for r in silhouette]
    h, w = len(rows), len(rows[0])

    def solid(x, y):
        return 0 <= y < h and 0 <= x < w and rows[y][x] != "."

    shaded = [r[:] for r in rows]
    for y in range(h):
        for x in range(w):
            c = rows[y][x]
            if c in shade and not solid(x, y + 1):
                shaded[y][x] = shade[c]

    out = [r[:] for r in shaded]
    for y in range(h):
        for x in range(w):
            if rows[y][x] != ".":
                continue
            if any(solid(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out[y][x] = "K"
    return out + [list(r) for r in tail]


def color_for(ch, sp, palette):
    """PlantSpriteBuilder.color 포팅 — 종 팔레트가 잎·꽃잎을 덮어쓴다."""
    if ch == ".":
        return None
    base = palette.get(ch)
    if ch == "G":
        base = sp["leaf"]
    elif ch == "L":
        base = sp["leafLight"]
    elif ch == "d":
        base = sp["leafShade"]
    elif ch == "F":
        base = sp["petal"] or palette.get("F")
    elif ch == "f":
        # 겹꽃 그림자 — 꽃잎색을 어둡게. 종마다 따로 안 정의해도 되게 여기서 만든다.
        p = sp["petal"] or palette.get("F")
        r, g, b = int(p[1:3], 16), int(p[3:5], 16), int(p[5:7], 16)
        base = "#%02x%02x%02x" % (int(r * 0.72), int(g * 0.72), int(b * 0.72))
    return base


def rgb(h):
    v = int(h.lstrip("#"), 16)
    return ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)


def render_cell(grid, sp, palette, scale, size=SIZE):
    img = Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for y, row in enumerate(grid):
        for x, ch in enumerate(row):
            hexv = color_for(ch, sp, palette)
            if not hexv:
                continue
            d.rectangle([x * scale, y * scale, (x + 1) * scale - 1, (y + 1) * scale - 1],
                        fill=rgb(hexv))
    return img



# ── 정원 스프라이트(16x16) ──────────────────────────────────────
#
# 이식된 그루는 지금까지 **꽃이 하나도 없었다.** 초록 덩이 세 모양뿐이라
# 정원이 차면 나무밭이 된다 — 30그루를 모아도 보상이 "초록 벽"이면 모을 이유가 없다.
# 화분과 같은 모티프를 작게(5x3) 얹어, 이식한 뒤에도 그 종의 꽃이 계속 핀다.
#
# 앵커는 잎 덩이 **안쪽**이어야 한다. 가장자리에 걸치면 꽃이 허공에 뜬 것처럼 보인다.
GARDEN_ANCHORS = {
    "round": [(2, 5), (3, 10), (5, 7)],
    "tall":  [(4, 7), (6, 8)],
    "low":   [(4, 5), (5, 10)],
}


def garden_shapes():
    """GardenSprites.shapes 를 Swift 에서 읽는다."""
    s = SPRITES.read_text(encoding="utf-8")
    at = s.index("enum GardenSprites")
    body = s[at: s.index("\n    static func grid", at)]
    out = {}
    for chunk in body.split(".round:")[0:1] + body.split(".")[0:0]:
        pass
    for name in ("round", "tall", "low"):
        i = body.index(f".{name}: [")
        seg = body[i: body.index("],", i)]
        out[name] = re.findall(r'"([.A-Za-z]{16})"', seg)
    return out


def compose_garden(shape_name, motif_name, shapes):
    grid = [list(r) for r in shapes[shape_name]]
    art = MOTIFS[motif_name]["small"]
    for row, col in GARDEN_ANCHORS[shape_name]:
        stamp(grid, art, row, col)
    return ["".join(r) for r in grid]


def render_garden(catalog, palette, shade, scale):
    """종 × 모양 대조표. 실제 정원처럼 여러 그루를 늘어놓고도 본다."""
    shapes = garden_shapes()
    cell = 16 * scale
    pad, label_w, header_h = 4, 92, 18
    cols = 4                       # 꽃 없음 + 3모양
    W = label_w + cols * (cell + pad) + pad
    H = header_h + len(catalog) * (cell + pad) + pad
    sheet = Image.new("RGBA", (W, H), (250, 248, 242, 255))
    d = ImageDraw.Draw(sheet)
    for i, t in enumerate(["before", "round", "tall", "low"]):
        d.text((label_w + i * (cell + pad) + 2, 4), t, fill=(90, 84, 74))

    for r, sp in enumerate(catalog):
        y = header_h + r * (cell + pad)
        motif = sp.get("motif") or SPECIES_MOTIF[sp["id"]]
        d.text((4, y + cell // 2 - 4), sp["name"], fill=(40, 36, 30))
        d.text((4, y + cell // 2 + 6), motif, fill=(130, 124, 112))
        # 0열: 꽃 없이 (지금 모습)
        plain = decorate(shapes[sp["shape"]], [], shade)
        sheet.alpha_composite(render_cell(plain, sp, palette, scale, 16),
                              (label_w, y))
        for c, name in enumerate(["round", "tall", "low"], start=1):
            art = compose_garden(name, motif, shapes)
            grid = decorate(art, [], shade)
            sheet.alpha_composite(render_cell(grid, sp, palette, scale, 16),
                                  (label_w + c * (cell + pad), y))
    out = ROOT / "Resources/preview-garden.png"
    sheet.save(out)
    print(f"{out}  ({W}x{H})  종 {len(catalog)}")


def main():
    only = [a for a in sys.argv[1:] if not a.startswith("--")]
    garden = "--garden" in sys.argv
    palette, shade = base_palette(), shade_map()
    pot = pot_rows()
    stages = stage_silhouettes()
    foliage = [strip_blooms(rows) for _, rows in stages]
    catalog = species_catalog()
    if only:
        catalog = [s for s in catalog if s["id"] in only]
        if not catalog:
            sys.exit(f"그런 종이 없습니다: {only}")

    if garden:
        render_garden(catalog, palette, shade, 6 if len(catalog) > 4 else 12)
        return

    scale = 5 if len(catalog) > 4 else 10
    cell = SIZE * scale
    pad, label_w, header_h = 4, 92, 18
    cols, rows_n = len(stages), len(catalog)
    W = label_w + cols * (cell + pad) + pad
    H = header_h + rows_n * (cell + pad) + pad

    sheet = Image.new("RGBA", (W, H), (250, 248, 242, 255))
    d = ImageDraw.Draw(sheet)
    for i, (name, _) in enumerate(stages):
        d.text((label_w + i * (cell + pad) + 2, 4), f"Lv.{i+1}", fill=(90, 84, 74))

    for r, sp in enumerate(catalog):
        y = header_h + r * (cell + pad)
        d.text((4, y + cell // 2 - 4), f"{sp['name']}", fill=(40, 36, 30))
        d.text((4, y + cell // 2 + 6), f"{sp.get('motif') or SPECIES_MOTIF[sp['id']]}",
               fill=(130, 124, 112))
        for c in range(cols):
            art = compose(c, sp.get("motif") or SPECIES_MOTIF[sp["id"]], foliage)
            grid = decorate(art, pot, shade)
            sheet.alpha_composite(render_cell(grid, sp, palette, scale),
                                  (label_w + c * (cell + pad), y))

    OUT.parent.mkdir(exist_ok=True)
    sheet.save(OUT)
    print(f"{OUT}  ({W}×{H})  종 {rows_n} × 단계 {cols}")


if __name__ == "__main__":
    main()
