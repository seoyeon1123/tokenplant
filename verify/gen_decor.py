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


# ── 움직이는 것들 ────────────────────────────────────────────────
#
# 모이통·물받이·고양이·바람개비는 **살아있는 걸 약속하는 이름**이다.
# 안 도는 바람개비, 안 움직이는 고양이, 새가 안 오는 모이통은 약속을 안 지킨다.
#
# 프레임 0 은 항상 `ART` 와 같다 — 상점 아이콘·도감 실루엣이 그걸 쓰기 때문에
# 따로 두면 두 곳이 어긋난다. 여기엔 **1번부터** 적는다.

# 45° 는 코드로 돌려봤다가 버렸다 — 11px 최근접 회전은 날개가 뭉개진다.
# 픽셀아트는 보고 고쳐야 한다는 규칙이 여기서도 맞았다. 손으로 그린다.

FRAMES = {
    # 바퀴만 45° — 기둥(rows 11~15)은 그대로다. 4날개는 90°마다 같은 그림이라
    # 0°/45° 두 장이면 한 바퀴가 돈다. 5fps 로 번갈면 도는 것으로 읽힌다.
    "windmill": [
        ".....KWWWK......",
        ".....KWWWK......",
        ".....KWWWK......",
        ".KKKKKKKKKKKKK..",
        ".KWWWKKKKKWWWK..",
        ".KWWWKKKKKWWWK..",
        ".KWWWKKKKKWWWK..",
        ".KKKKKKKKKKKKK..",
        ".....KWWWK......",
        ".....KWWWK......",
        ".....KWWWK......",
        "......KwwK......",
        "......KwwK......",
        ".....KxxxxK.....",
        ".....KKKKKK.....",
        "................",
    ],

    # 고양이 — 꼬리만 움직인다. 몸을 건드리면 16px 에서 덩어리가 흔들려 지저분하다.
    "cat": [
        "................",
        "................",
        "...KK.....KK....",
        "..KyyK...KyyK...",
        "..KyyyKKKyyyK...",
        "..KyyyyyyyyyK...",
        "..KyKyyyyyKyK...",
        "..KyyyyKyyyyK...",
        "...KyyyyyyyK....",
        "....KyyyyyK..K..",
        "....KyyyyyK.KyK.",
        "....KyyyyyK.KyK.",
        "....KyyyyyKKyK..",
        "....KyyyyyyyK...",
        ".....KKKKKKK....",
        "................",
    ],

    # 눈 감기 — 세 번째 프레임. 꼬리는 1번 자리에 둔다.
    "cat2": [
        "................",
        "................",
        "...KK.....KK....",
        "..KyyK...KyyK...",
        "..KyyyKKKyyyK...",
        "..KyyyyyyyyyK...",
        "..KKKyyyyyKKK...",
        "..KyyyyKyyyyK...",
        "...KyyyyyyyK....",
        "....KyyyyyK..K..",
        "....KyyyyyK.KyK.",
        "....KyyyyyK.KyK.",
        "....KyyyyyKKyK..",
        "....KyyyyyyyK...",
        ".....KKKKKKK....",
        "................",
    ],
    # 물받이 — 돌은 그대로 두고 **수면만** 흔든다. 세 줄(4~6)에서 반짝이(V)가 흘러간다.
    # 물결을 크게 그리면 물이 넘치는 것처럼 보인다. 빛 몇 점이면 충분하다.
    "birdbath": [
        "................",
        "................",
        "................",
        "...KKKKKKKKKK...",
        "..KEBBVBBBBBEK..",
        "..KEBBBVBBBVEK..",
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

    "birdbath2": [
        "................",
        "................",
        "................",
        "...KKKKKKKKKK...",
        "..KEBBBBVBBBEK..",
        "..KEVBBBBBBVEK..",
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
}
# 어떤 장식이 몇 장짜리인가. 0번은 ART 에 이미 있으므로 여기엔 1번부터 둔다.
# 바람개비는 2장(0°/45°), 고양이는 3장(꼬리·꼬리+눈감음)이다.
ANIM = {
    "windmill": [FRAMES["windmill"]],
    "cat": [FRAMES["cat"], FRAMES["cat2"]],
    "birdbath": [FRAMES["birdbath"], FRAMES["birdbath2"]],
}

# 새 — 장식이 아니라 **모이통·물받이가 있으면 찾아오는 손님**이다.
# 그래서 뽑기 목록에도 상점에도 없다. 프레임 0 은 앉은 자세, 1 은 날갯짓.
BIRD = [
    # 0 앉음 — 모이통 앞에 선 기본 자세.
    [
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "......KKKK......",
        ".....KqqqqK.KK..",
        ".....KqKqqKKYK..",
        "....KqqqqqqKK...",
        "..KKqqxxxqqK....",
        ".KqqqqxxxqqK....",
        "..KKqqqqqqK.....",
        "......K..K......",
        "................",
    ],
    # 1 날갯짓 — 날아오는 중에도, 앉아서 폴짝 뛸 때도 이 장을 쓴다.
    # 옆모습에서 날개를 세우면 토끼 귀로 읽혀서, 두 칸 떠오른 자세로 대신한다.
    [
        "................",
        "................",
        "................",
        "................",
        "................",
        "......KKKK......",
        ".....KqqqqK.KK..",
        ".....KqKqqKKYK..",
        "....KqqqqqqKK...",
        "..KKqxxxxqqK....",
        ".KqqqxxxxqqK....",
        "..KKqqqqqqK.....",
        "................",
        "................",
        "................",
        "................",
    ],
    # 2 쪼기 — 머리를 숙이고 부리가 바닥을 향한다. 꼬리가 들린다.
    [
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "..KK............",
        ".KqqK...........",
        ".KqqqKKKK.......",
        "..KqqqqqqqK.....",
        "..KqqxxxqqqK....",
        "...KqqqqqqqK....",
        "....KKqqqqK.....",
        ".....KqqK.......",
        "......KYK.......",
    ],
]


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
    # 프레임도 같은 규칙을 받는다 — 한 장이라도 격자가 어긋나면 애니메이션에서 튄다.
    packs = [(f"{k}·{i+1}", f) for k, fs in ANIM.items() for i, f in enumerate(fs)]
    packs += [(f"bird·{i}", f) for i, f in enumerate(BIRD)]
    for key, rows in packs:
        if len(rows) != SIZE:
            bad.append(f"{key}: {len(rows)}줄 (16이어야 한다)")
        for i, r in enumerate(rows):
            if len(r) != SIZE:
                bad.append(f"{key}[{i}]: {len(r)}칸 — {r!r}")
            for ch in r:
                if ch != "." and ch not in pal:
                    bad.append(f"{key}[{i}]: '{ch}' 는 IconPalette 에 없다")
    for k in ANIM:
        if k not in ART:
            bad.append(f"프레임만 있고 0번이 없다: {k}")

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
    # 프레임도 같이 본다 — 0번과 나란히 놔야 "번갈면 어떻게 보일지" 가 판단된다.
    keys = SHOP_DECOR + GACHA_DECOR
    extra = [(f"{k}·{i+1}", f) for k, fs in ANIM.items() for i, f in enumerate(fs)]
    extra += [("새·앉음", BIRD[0]), ("새·날갯짓", BIRD[1]), ("새·쪼기", BIRD[2])]
    cols, gap, label = 6, 6, 12
    rows = (len(keys) + len(extra) + cols - 1) // cols
    cw = SIZE * scale + gap
    ch = SIZE * scale + gap + label
    img = Image.new("RGB", (cols * cw + gap, rows * ch + gap), "#cfe0e4")
    d = ImageDraw.Draw(img)
    cells = [(k, ART[k]) for k in keys] + extra
    for i, (key, art) in enumerate(cells):
        ox = gap + (i % cols) * cw
        oy = gap + (i // cols) * ch
        # 뽑기 전용은 바닥색을 달리해 한눈에 갈라 보이게. 프레임은 또 다른 색.
        d.rectangle([ox, oy, ox + SIZE * scale - 1, oy + SIZE * scale - 1],
                    fill="#e0c88f" if "·" in key else
                         ("#9fc48f" if key in GACHA_DECOR else "#b8d4a8"))
        for y, r in enumerate(art):
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
    lines.append("")
    lines.append("    /// 움직이는 장식의 **1번 프레임부터**. 0번은 `art` 에 이미 있다.")
    lines.append("    ///")
    lines.append("    /// 바람개비는 0°/45° 두 장이면 한 바퀴가 돈다 — 날개가 넷이라 90°마다 같은 그림이다.")
    lines.append("    /// 고양이는 꼬리만 움직인다. 16px 에서 몸을 건드리면 덩어리가 흔들려 지저분해진다.")
    lines.append("    static let frames: [String: [[String]]] = [")
    for k, fs in ANIM.items():
        lines.append(f'        "{k}": [')
        for f in fs:
            lines.append("            [")
            for r in f:
                lines.append(f'                "{r}",')
            lines.append("            ],")
        lines.append("        ],")
    lines.append("    ]")
    lines.append("")
    lines.append("    /// 0번 포함 전체 장수. 움직이지 않는 장식은 1이다.")
    lines.append("    static func frameCount(_ key: String) -> Int {")
    lines.append("        (frames[key]?.count ?? 0) + 1")
    lines.append("    }")
    lines.append("")
    lines.append("    /// `frame` 은 아무 수나 와도 된다 — 장수로 나눠 돌린다.")
    lines.append("    static func grid(_ key: String, frame: Int) -> [[Character]]? {")
    lines.append("        guard let zero = art[key] else { return nil }")
    lines.append("        let extra = frames[key] ?? []")
    lines.append("        guard !extra.isEmpty else { return zero.map { Array($0) } }")
    lines.append("        let i = ((frame % (extra.count + 1)) + extra.count + 1) % (extra.count + 1)")
    lines.append("        let rows = i == 0 ? zero : extra[i - 1]")
    lines.append("        return rows.map { Array($0) }")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    lines.append("/// 새. **장식이 아니다** — 상점에도 뽑기에도 없고, 모이통이나 물받이를 놓아두면 찾아온다.")
    lines.append("///")
    lines.append("/// 그래서 `DecorIcons` 와 따로 둔다. 소유물 목록에 섞이면 도감에 빈 칸이 생긴다.")
    lines.append("/// 세 장이다 — 앉음 · 날갯짓 · 쪼기. 옆모습에서 날개를 세우면 토끼 귀로 읽혀서,")
    lines.append("/// 날갯짓은 두 칸 떠오른 자세로 대신한다. 그 장을 폴짝 뛰는 데도 같이 쓴다.")
    lines.append("///")
    lines.append("/// **생성물이다.** 원본은 `verify/gen_decor.py`.")
    lines.append("enum BirdIcon {")
    lines.append("    static let size = 16")
    lines.append("")
    lines.append("    static let art: [[String]] = [")
    for f in BIRD:
        lines.append("        [")
        for r in f:
            lines.append(f'            "{r}",')
        lines.append("        ],")
    lines.append("    ]")
    lines.append("")
    lines.append("    /// 자세 번호. 순서대로 돌리는 게 아니라 **골라 쓴다** —")
    lines.append("    /// 날아오는 중엔 `flying`, 내려앉으면 `perched`, 가끔 `pecking`.")
    lines.append("    static let perched = 0")
    lines.append("    static let flying = 1")
    lines.append("    static let pecking = 2")
    lines.append("")
    lines.append("    static var frameCount: Int { art.count }")
    lines.append("")
    lines.append("    static func grid(frame: Int) -> [[Character]] {")
    lines.append("        let i = ((frame % art.count) + art.count) % art.count")
    lines.append("        return art[i].map { Array($0) }")
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
