# -*- coding: utf-8 -*-
"""장식 스프라이트 원본. 여기가 출처이고 Swift 는 생성물이다.

    python3 verify/gen_decor.py            # 콘택트 시트만 (Resources/preview-decor.png)
    python3 verify/gen_decor.py --write    # IconSprites.swift 의 DecorIcons 를 갈아끼운다

왜 파이썬이 원본인가: 픽셀 아트는 **보고 고쳐야** 한다. 실제로 이 방식으로
열매가 빨간 십자가로 나온 것, 몬스테라 1px 구멍이 외곽선에 먹힌 것,
대나무 마디가 갈색 십자가였던 것을 잡았다. 숫자만 보면 셋 다 통과한다.
"""
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parent.parent
ICONS = ROOT / "Sources/TokenPlant/Core/IconSprites.swift"
SIZE = 16

# IconPalette 와 같은 문자만 쓸 수 있다. check_data 가 강제한다.
#   K 외곽선 · W 흰 · M/m 회색 · B/b 물 · S/s 모래 · V 연한하늘
#   L/G/g 초록 · Y/y 노랑 · O 흙갈 · R 빨강 · F 분홍 · P/q 주황
#   D 진갈 · N 검회 · w/x 나무 · E/e 석재 · T/t 짙은나무

ART = {
    # ── 상점에서 직접 사는 셋 (기존) ───────────────────────────
    "bench": [
        "................",
        "................",
        "................",
        "................",
        "..KKKKKKKKKKKK..",
        "..KwwwwwwwwwwK..",
        "..KxxxxxxxxxxK..",
        "..KKKKKKKKKKKK..",
        "..KwwwwwwwwwwK..",
        "..KxxxxxxxxxxK..",
        "..KKKKKKKKKKKK..",
        "...K.K....K.K...",
        "...K.K....K.K...",
        "...KKK....KKK...",
        "................",
        "................",
    ],
    "feeder": [
        "................",
        ".......K........",
        ".......K........",
        "....KKKKKKK.....",
        "...KwwwwwwwK....",
        "...KxxxxxxxK....",
        "...KKKKKKKKK....",
        "....KwwwwwK.....",
        "....KOOOOOK.....",
        "....KKKKKKK.....",
        ".......K........",
        ".......K........",
        ".......K........",
        "......KKK.......",
        "................",
        "................",
    ],
    "lantern": [
        "................",
        ".....KKKKK......",
        "....KEEEEEK.....",
        "....KKKKKKK.....",
        "...KEEEEEEEK....",
        "...KEYYYYYEK....",
        "...KEYWWWYEK....",
        "...KEYYYYYEK....",
        "...KEEEEEEEK....",
        "....KKKKKKK.....",
        ".....KEEEK......",
        ".....KEEEK......",
        "....KEEEEEK.....",
        "....KKKKKKK.....",
        "................",
        "................",
    ],

    # ── 뽑기로만 나오는 아홉 ───────────────────────────────────
    # 실루엣이 서로 다르게 나오도록 골랐다: 낮고 넓은 것, 높고 좁은 것,
    # 둥근 것, 각진 것. 같은 덩어리 모양이 섞이면 16px 에서 구분이 안 된다.
    "birdbath": [                     # 낮고 넓은 접시 — 물이 보인다
        "................",
        "................",
        "................",
        "...KKKKKKKKKK...",
        "..KEBBBBBBBBEK..",
        "..KEBVBBBBVBEK..",
        "..KEEBBBBBBEEK..",
        "...KEEEEEEEEK...",
        ".....KEEEEK.....",
        "......KEEK......",
        "......KEEK......",
        ".....KEEEEK.....",
        "....KEEEEEEK....",
        "....KKKKKKKK....",
        "................",
        "................",
    ],
    "gnome": [                        # 높고 좁은 것 — 뾰족한 모자
        "................",
        ".......K........",
        "......KRK.......",
        "......KRK.......",
        ".....KRRRK......",
        ".....KRRRK......",
        "....KRRRRRK.....",
        "....KKKKKKK.....",
        "....KqqWqqK.....",
        "....KqWWWqK.....",
        "....KKKWKKK.....",
        "...KBBBBBBBK....",
        "...KBBBBBBBK....",
        "...KKKKKKKKK....",
        "................",
        "................",
    ],
    "windmill": [                     # 제일 높은 것 — 날개가 사선으로 두껍다
        ".......K........",
        "...KK..K..KK....",
        "..KWWK.K.KWWK...",
        "..KWWWKKKWWWK...",
        "...KWWWKWWWK....",
        "....KKKKKKK.....",
        "...KWWWKWWWK....",
        "..KWWWKKKWWWK...",
        "..KWWK.K.KWWK...",
        "...KK..K..KK....",
        ".......K........",
        "......KwwK......",
        "......KwwK......",
        ".....KxxxxK.....",
        ".....KKKKKK.....",
        "................",
    ],
    "mailbox": [                      # 기둥 위 둥근 통
        "................",
        "................",
        "....KKKKKKK.....",
        "...KRRRRRRRK....",
        "...KRWWWWWRK....",
        "...KRRRRRRRK....",
        "...KRRRRRRRK....",
        "...KKKKKKKKK....",
        "......KwK.......",
        "......KwK.......",
        "......KwK.......",
        "......KxK.......",
        ".....KxxxK......",
        ".....KKKKK......",
        "................",
        "................",
    ],
    "steppingstones": [               # 유일하게 **수직 덩어리가 없는** 것 — 바닥에 깔린다
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "......KKKK......",
        ".....KEEEEK.....",
        ".....KEeeEK.....",
        "......KKKK......",
        ".KKKK......KKKK.",
        "KEEEEK....KEEEEK",
        "KEeeEK....KEeeEK",
        ".KKKK......KKKK.",
        "................",
        "................",
    ],
    "fence": [                        # 가로로 길고 낮은 것
        "................",
        "................",
        "................",
        "................",
        "..K..K..K..K..K.",
        "..KwwKwwKwwKwwK.",
        "..KKKKKKKKKKKKK.",
        "..KwwKwwKwwKwwK.",
        "..KwwKwwKwwKwwK.",
        "..KKKKKKKKKKKKK.",
        "..KxxKxxKxxKxxK.",
        "..KxxKxxKxxKxxK.",
        "..K..K..K..K..K.",
        "..K..K..K..K..K.",
        "................",
        "................",
    ],
    "mushroom": [                      # 둥근 것 — 점이 있어 한눈에 구분된다
        "................",
        "................",
        "................",
        ".....KKKKK......",
        "...KKRRRRRKK....",
        "..KRRWRRRWRRK...",
        "..KRRRRWRRRRK...",
        "..KRWRRRRRWRK...",
        "..KKRRRRRRRKK...",
        "....KKWWWKK.....",
        "......KWK.......",
        "......KWK.......",
        ".....KWWWK......",
        ".....KKKKK......",
        "................",
        "................",
    ],
    "arch": [                         # 유일하게 **속이 빈** 실루엣. 덩굴이 올라간다
        "....KKKKKKKK....",
        "...KLLwwwwLLK...",
        "..KLwwKKKKwwLK..",
        "..KwwK....KwwK..",
        "..KLwK....KwLK..",
        "..KwwK....KwwK..",
        "..KLwK....KwLK..",
        "..KwwK....KwwK..",
        "..KLwK....KwLK..",
        "..KwwK....KwwK..",
        "..KwwK....KwwK..",
        "..KxxK....KxxK..",
        "..KKKK....KKKK..",
        "................",
        "................",
        "................",
    ],
    "cat": [                          # 살아 있는 것 하나 — 귀가 실루엣을 만든다
        "................",
        "................",
        "...KK.....KK....",
        "..KyyK...KyyK...",
        "..KyyyKKKyyyK...",
        "..KyyyyyyyyyK...",
        "..KyKyyyyyKyK...",
        "..KyyyyKyyyyK...",
        "...KyyyyyyyK....",
        "....KyyyyyK.....",
        "....KyyyyyK...K.",
        "....KyyyyyK..KyK",
        "....KyyyyyKKKyK.",
        "....KyyyyyyyyK..",
        ".....KKKKKKK....",
        "................",
    ],
}

# 상점에서 직접 사는 것 / 뽑기 전용
SHOP_DECOR = ["bench", "feeder", "lantern"]
GACHA_DECOR = ["birdbath", "gnome", "windmill", "mailbox", "steppingstones",
               "fence", "mushroom", "arch", "cat"]

NAMES = {
    "bench": "벤치", "feeder": "새 모이통", "lantern": "석등",
    "birdbath": "새 물받이", "gnome": "정원 요정", "windmill": "바람개비",
    "mailbox": "우편함", "steppingstones": "디딤돌", "fence": "울타리",
    "mushroom": "버섯", "arch": "덩굴 아치", "cat": "고양이",
}


def palette():
    """IconPalette 를 Swift 에서 그대로 읽는다 — 색을 두 곳에 두면 어긋난다."""
    text = ICONS.read_text(encoding="utf-8")
    seg = text[text.index("enum IconPalette"):text.index("static func color")]
    out = {}
    for ch, hexv in re.findall(r'"(.)":\s*"(#[0-9a-fA-F]{6})"', seg):
        out[ch] = hexv
    assert len(out) > 10, "IconPalette 를 못 읽었다"
    return out


def check():
    """렌더 전에 격자부터 본다 — 한 줄이라도 길이가 다르면 인덱스가 밀린다."""
    pal = palette()
    bad = []
    for key, rows in ART.items():
        if len(rows) != SIZE:
            bad.append(f"{key}: {len(rows)}줄 (16이어야 한다)")
        for i, r in enumerate(rows):
            if len(r) != SIZE:
                bad.append(f"{key}[{i}]: {len(r)}칸 — {r!r}")
            for ch in r:
                if ch != "." and ch not in pal:
                    bad.append(f"{key}[{i}]: '{ch}' 는 IconPalette 에 없다")
    missing = set(SHOP_DECOR + GACHA_DECOR) - set(ART)
    if missing:
        bad.append(f"아트 없는 장식: {sorted(missing)}")
    extra = set(ART) - set(SHOP_DECOR + GACHA_DECOR)
    if extra:
        bad.append(f"목록에 없는 아트: {sorted(extra)}")
    return bad


def sheet(path, scale=7):
    """콘택트 시트. **눈으로 보려고** 만든다."""
    from PIL import Image, ImageDraw
    pal = palette()
    keys = SHOP_DECOR + GACHA_DECOR
    cols, gap, label = 6, 6, 12
    rows = (len(keys) + cols - 1) // cols
    cw = SIZE * scale + gap
    ch = SIZE * scale + gap + label
    img = Image.new("RGB", (cols * cw + gap, rows * ch + gap), "#cfe0e4")
    d = ImageDraw.Draw(img)
    for i, key in enumerate(keys):
        ox = gap + (i % cols) * cw
        oy = gap + (i // cols) * ch
        # 뽑기 전용은 바닥색을 달리해 한눈에 갈라 보이게
        d.rectangle([ox, oy, ox + SIZE * scale - 1, oy + SIZE * scale - 1],
                    fill="#9fc48f" if key in GACHA_DECOR else "#b8d4a8")
        for y, r in enumerate(ART[key]):
            for x, c in enumerate(r):
                if c == ".":
                    continue
                d.rectangle([ox + x * scale, oy + y * scale,
                             ox + (x + 1) * scale - 1, oy + (y + 1) * scale - 1],
                            fill=pal[c])
        d.text((ox, oy + SIZE * scale + 1), f"{key}", fill="#2b2016")
    img.save(path)
    return path


def swift_block():
    lines = ["""/// 정원 장식. 연못은 수목원 배경에 이미 절차적으로 들어간다.
///
/// 열두 개다. 셋(벤치·모이통·석등)은 상점에서 직접 사고, 아홉은 **장식 뽑기**로만 나온다.
/// 직접 살 수 있게 다 열어두면 비싼 순서대로 사는 목록이 되고, 그건 재미가 아니라 숙제다.
///
/// 실루엣을 일부러 흩었다 — 낮고 넓은 것(물받이·울타리), 높고 좁은 것(요정·바람개비),
/// 둥근 것(버섯·해시계), 각진 것(돌 등불). 16px 에서 덩어리 모양이 겹치면 구분이 안 된다.
///
/// **생성물이다.** 원본은 `verify/gen_decor.py` 고, 거기서 콘택트 시트를 뽑아 보고 고친다.
/// 직접 고치면 다음 `--write` 에 날아간다.
enum DecorIcons {
    static let size = 16

    /// 상점에서 직접 사는 장식.
    static let shopKeys = [""" + ", ".join(f'"{k}"' for k in SHOP_DECOR) + """]

    /// 뽑기로만 나오는 장식.
    static let gachaKeys = [""" + ", ".join(f'"{k}"' for k in GACHA_DECOR) + """]

    static var allKeys: [String] { shopKeys + gachaKeys }

    static let names: [String: String] = ["""]
    for k in SHOP_DECOR + GACHA_DECOR:
        lines.append(f'        "{k}": "{NAMES[k]}",')
    lines.append("    ]")
    lines.append("")
    lines.append("    static func name(_ key: String) -> String { names[key] ?? key }")
    lines.append("")
    lines.append("    static let art: [String: [String]] = [")
    for k in SHOP_DECOR + GACHA_DECOR:
        lines.append(f'        "{k}": [')
        for r in ART[k]:
            lines.append(f'            "{r}",')
        lines.append("        ],")
    lines.append("    ]")
    lines.append("")
    lines.append("    static func grid(_ key: String) -> [[Character]]? {")
    lines.append("        guard let rows = art[key] else { return nil }")
    lines.append("        return rows.map { Array($0) }")
    lines.append("    }")
    lines.append("}")
    return "\n".join(lines)


def write():
    text = ICONS.read_text(encoding="utf-8")
    start = text.index("/// 정원 장식.")
    end = text.index("enum MenuBarSprites")
    new = text[:start] + swift_block() + "\n\n" + text[end:]
    ICONS.write_text(new, encoding="utf-8")
    return len(SHOP_DECOR + GACHA_DECOR)


if __name__ == "__main__":
    bad = check()
    if bad:
        print("격자 문제:")
        for b in bad:
            print("  ✗", b)
        sys.exit(1)
    out = sheet(ROOT / "Resources/preview-decor.png")
    print(f"콘택트 시트: {out}")
    if "--write" in sys.argv:
        n = write()
        print(f"DecorIcons 갈아끼움 — 장식 {n}개 (상점 {len(SHOP_DECOR)} · 뽑기 {len(GACHA_DECOR)})")
