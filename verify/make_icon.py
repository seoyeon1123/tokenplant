# -*- coding: utf-8 -*-
"""앱 아이콘(.icns)을 스프라이트에서 직접 만든다.

손으로 그린 PNG 를 따로 두면 스프라이트를 고쳐도 아이콘이 안 따라와서 금방 어긋난다.
`PlantSprites.swift` 를 그대로 읽어 마지막 단계(거목)를 렌더한다 — 출처가 하나다.

    python3 verify/make_icon.py

`Resources/AppIcon.icns` 와 미리보기 `Resources/AppIcon-512.png` 이 나온다.
macOS 의 iconutil 이 필요 없다(ICNS 는 PNG 를 담는 단순한 컨테이너다).
"""
import re
import struct
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources/TokenPlant/Core/PlantSprites.swift"
OUT_DIR = ROOT / "Resources"


# ── PlantSprites.swift 파싱 ──────────────────────────────────────

def swift_text():
    return SRC.read_text(encoding="utf-8")


def parse_palette(text, name):
    """`static let <name>: [Character: String] = [ "K": "#2b2016", ... ]`"""
    at = text.index(f"static let {name}")
    body = text[text.index("[", text.index("=", at)):]
    body = body[: body.index("]")]
    return {k: v for k, v in re.findall(r'"(.)"\s*:\s*"(#[0-9a-fA-F]{6})"', body)}


def parse_shade(text):
    at = text.index("static let shade")
    body = text[text.index("[", text.index("=", at)):]
    body = body[: body.index("]")]
    return {k: v for k, v in re.findall(r'"(.)"\s*:\s*"(.)"', body)}


def parse_rows(block):
    return re.findall(r'"([.A-Za-z]{24})"', block)


def parse_pot(text):
    at = text.index("static let pot:")
    # `= [` 뒤부터 잘라야 한다 — 타입 표기 `[String]` 의 `]` 를 끝으로 오인한다.
    start = text.index("[", text.index("=", at))
    return parse_rows(text[start: text.index("]", start)])


def parse_last_stage(text):
    """마지막 `.init(level: N, ...)` 의 실루엣."""
    blocks = text.split(".init(level:")
    last = blocks[-1]
    rows = parse_rows(last[: last.index("]),")])
    if len(rows) != 17:
        sys.exit(f"실루엣이 17줄이 아니다: {len(rows)}줄")
    return rows


# ── PlantSpriteBuilder.decorate 포팅 ────────────────────────────

def decorate(silhouette, tail, shade, outline="K"):
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
                out[y][x] = outline

    return out + [list(r) for r in tail]


# ── 렌더 ─────────────────────────────────────────────────────────

def rgb(hex_str):
    v = int(hex_str.lstrip("#"), 16)
    return ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


def render(grid, palette, size):
    """둥근 사각 바탕 위에 스프라이트를 정수배로 올린다.

    정수배가 깨지면 픽셀아트가 흐려진다 — 그래서 셀 크기를 먼저 정수로 정하고
    거기서 나온 크기를 캔버스 가운데에 놓는다.
    """
    cells = len(grid)              # 24
    # macOS 아이콘은 가장자리에 여백이 있어야 독에서 다른 아이콘과 크기가 맞는다.
    inner = int(size * 0.76)
    cell = max(1, inner // cells)
    art = cell * cells

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # 바탕 — 위에서 아래로 옅은 크림 → 살짝 더 짙은 크림. 식물이 초록이라 보색을 피한다.
    bg = Image.new("RGBA", (size, size))
    top, bottom = (247, 243, 233, 255), (226, 234, 219, 255)
    d = ImageDraw.Draw(bg)
    for y in range(size):
        t = y / max(1, size - 1)
        d.line([(0, y), (size, y)],
               fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    canvas.paste(bg, (0, 0), rounded_mask(size, int(size * 0.2237)))

    # 스프라이트 — 최근접 확대(정수배라 선명하다).
    sprite = Image.new("RGBA", (cells, cells), (0, 0, 0, 0))
    px = sprite.load()
    for y, row in enumerate(grid):
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            hexv = palette.get(ch)
            if hexv:
                px[x, y] = rgb(hexv) + (255,)
    sprite = sprite.resize((art, art), Image.NEAREST)

    off = (size - art) // 2
    canvas.paste(sprite, (off, off), sprite)
    return canvas


# ── ICNS 쓰기 ────────────────────────────────────────────────────

# (OSType, 픽셀 크기). iconutil 없이 직접 쓴다 — 이 컨테이너는 헤더 + 청크가 전부다.
ICNS_TYPES = [
    (b"icp4", 16), (b"icp5", 32), (b"ic11", 32), (b"ic12", 64),
    (b"ic07", 128), (b"ic13", 256), (b"ic08", 256),
    (b"ic14", 512), (b"ic09", 512), (b"ic10", 1024),
]


def write_icns(path, render_at):
    import io
    chunks = b""
    for ostype, px in ICNS_TYPES:
        buf = io.BytesIO()
        render_at(px).save(buf, format="PNG")
        data = buf.getvalue()
        chunks += ostype + struct.pack(">I", len(data) + 8) + data
    path.write_bytes(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)


def main():
    text = swift_text()
    palette = parse_palette(text, "base")
    shade = parse_shade(text)
    grid = decorate(parse_last_stage(text), parse_pot(text), shade)

    if len(grid) != 24 or any(len(r) != 24 for r in grid):
        sys.exit(f"격자가 24×24 가 아니다: {len(grid)}줄")

    OUT_DIR.mkdir(exist_ok=True)
    cache = {}

    def at(px):
        if px not in cache:
            cache[px] = render(grid, palette, px)
        return cache[px]

    write_icns(OUT_DIR / "AppIcon.icns", at)
    at(512).save(OUT_DIR / "AppIcon-512.png")
    size = (OUT_DIR / "AppIcon.icns").stat().st_size
    print(f"AppIcon.icns ({size:,} bytes) · AppIcon-512.png — 거목 24×24 에서 렌더")


if __name__ == "__main__":
    main()
