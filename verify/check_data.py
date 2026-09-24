#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Swift 컴파일러 없이 잡을 수 있는 것들 — 데이터 불변식 검사.

`swift test` 가 있는데 이걸 왜 또 두는가: 이 저장소는 Swift 툴체인이 없는 환경
(클라우드 컨테이너, 리눅스 VM)에서도 손이 간다. 스프라이트 한 줄이 15칸이 되거나
정원 슬롯이 해금 조건보다 적어지는 건 **컴파일은 통과하고 화면만 깨지는** 종류라,
컴파일러가 없는 자리에서도 걸러야 한다.

    python3 verify/check_data.py

Swift 소스를 직접 파싱해서 본다 — 파이썬 원본(`../plant_sprites.py` 등)과
생성물이 어긋나는 것까지 잡으려면 생성물 쪽을 봐야 한다.
"""

import pathlib
import re
import sys

# preview_species 를 import 하는데, 오래된 __pycache__ 가 남으면 고친 값을 안 읽고
# **거짓 통과/거짓 실패**를 낸다(실제로 한 번 속았다).
sys.dont_write_bytecode = True
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources" / "TokenPlant"

FAIL = []



def _gen_decor():
    """스프라이트 **원본**. 생성물(Swift)과 대조하려면 원본을 읽어야 한다."""
    import importlib.util
    path = pathlib.Path(__file__).with_name("gen_decor.py")
    spec = importlib.util.spec_from_file_location("gen_decor", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def anim_frames():
    return sum(len(v) for v in _gen_decor().ANIM.values())


def bird_frames():
    return len(_gen_decor().BIRD)


def bad(where, msg):
    FAIL.append(f"{where}: {msg}")


def read(rel):
    return (SRC / rel).read_text(encoding="utf-8")


# ── 1. 정원 씬 레이아웃 ────────────────────────────────────────
# 슬롯이 해금 조건보다 적으면 이식한 그루가 조용히 사라진다.
# 좌표가 캔버스를 넘치면 오른쪽 끝 나무가 반만 그려진다.

def check_scene():
    model = read("Core/PlantModel.swift")
    tiers = {}
    for m in re.finditer(
        r'\.init\(key: "(\w+)",\s*name: "([^"]+)",\s*need: (\d+),\s*canvas: \((\d+), (\d+)\)', model
    ):
        key, name, need, w, h = m.group(1), m.group(2), int(m.group(3)), int(m.group(4)), int(m.group(5))
        tiers[key] = dict(name=name, need=need, w=w, h=h)
    if len(tiers) != 7:
        bad("GardenTier", f"티어가 7개가 아니다 ({len(tiers)}개)")

    scene = read("UI/GardenScene.swift")
    # `static func byKey` 는 SeasonPalette 에도 있고 그게 먼저 나온다 —
    # `all` 뒤에서 찾아야 슬라이스가 뒤집히지 않는다.
    at = scene.index("static let all: [SceneLayout]")
    block = scene[at:scene.index("static func byKey", at)]
    sprite = 16   # GardenSprites.size

    layouts = {}
    for chunk in block.split(".init(key: ")[1:]:
        key = re.match(r'"(\w+)"', chunk).group(1)
        w = int(re.search(r"width: (\d+)", chunk).group(1))
        h = int(re.search(r"height: (\d+)", chunk).group(1))
        rows = [(int(b), [int(x) for x in xs.split(",") if x.strip()])
                for b, xs in re.findall(r"baseline: (\d+), xs: \[([0-9,\s]*)\]", chunk)]
        layouts[key] = dict(w=w, h=h, rows=rows)

    if set(layouts) != set(tiers):
        bad("SceneLayout", f"티어와 레이아웃 키가 다르다 {sorted(set(tiers) ^ set(layouts))}")

    for key, L in layouts.items():
        t = tiers.get(key)
        if not t:
            continue
        where = f"{key}({t['name']})"
        if (L["w"], L["h"]) != (t["w"], t["h"]):
            bad(where, f"캔버스 불일치 레이아웃 {L['w']}x{L['h']} vs 티어 {t['w']}x{t['h']}")

        horizon = int(L["h"] * 0.42)
        if not 0 < horizon < L["h"]:
            bad(where, f"지평선 {horizon} 이 캔버스 밖")

        total = sum(len(xs) for _, xs in L["rows"])
        # 창가·베란다는 화분 자체를 보여주는 티어라 슬롯이 need 보다 적을 수 있다.
        if t["need"] >= 3 and total < t["need"]:
            bad(where, f"슬롯 {total} < 필요 {t['need']}그루 — 그루가 사라진다")

        prev = -1
        for b, xs in L["rows"]:
            if b <= sprite - 1:
                bad(where, f"기준선 {b} 이 낮아 나무 위쪽이 잘린다")
            if b > L["h"]:
                bad(where, f"기준선 {b} 이 캔버스({L['h']}) 아래")
            if b < prev:
                bad(where, "줄 순서가 뒤→앞이 아니다 (앞나무가 뒷나무에 가린다)")
            prev = b
            for x in xs:
                if x < 0 or x + sprite > L["w"]:
                    bad(where, f"x={x} 에서 나무가 오른쪽으로 넘친다 (+{sprite} > {L['w']})")

    # 장식 자리 — GardenView.decorSpots 와 같은 식을 쓴다 (18px 간격 한 줄)
    for key, L in layouts.items():
        count = max(1, (L["w"] - 6) // 18)
        for i in range(count):
            x = 3 + i * 18
            if x + 16 > L["w"]:
                bad(key, f"장식 {i + 1}번째가 x={x} 에서 오른쪽으로 넘친다")
    # 마지막 두 티어는 장식 열두 개를 다 담아야 한다 — 못 담으면 뽑아도 안 보인다.
    for key in ("arbor", "forest"):
        if key in layouts and max(1, (layouts[key]["w"] - 6) // 18) < 12:
            bad(key, "장식 자리가 12개보다 적다 — 뽑은 장식이 정원에 안 나온다")


# ── 2. 계절 팔레트 ─────────────────────────────────────────────

def check_palettes():
    scene = read("UI/GardenScene.swift")
    for hexes in re.findall(r'"(#[0-9a-fA-F]*)"', scene):
        if len(hexes) != 7:
            bad("SeasonPalette", f"{hexes} 는 6자리 hex 가 아니다")


# ── 3. 스프라이트 격자 ─────────────────────────────────────────
# 한 줄이라도 길이가 다르면 렌더에서 인덱스가 밀린다.

def grids_in(text, start_marker, end_marker=None):
    """픽셀 줄만 뽑는다.

    문자열 리터럴만 있는 줄이 픽셀 줄이다. 딕셔너리 키(`"wateringCan": [`)는
    뒤에 `:` 가 붙으므로 걸러진다 — 이걸 안 가리면 키 이름이 15칸 줄로 잡힌다.
    """
    seg = text[text.index(start_marker):]
    if end_marker and end_marker in seg:
        seg = seg[:seg.index(end_marker)]
    return [m.group(1) for m in re.finditer(r'^\s*"([^"]*)",\s*$', seg, re.M)]


def check_sprites():
    ps = read("Core/PlantSprites.swift")

    # 화분 24×24 — 실루엣 17줄 + 화분 7줄
    pot_rows = grids_in(ps, "enum PotSprites", "enum GardenSprites")
    off = [r for r in pot_rows if len(r) != 24]
    if off:
        bad("PotSprites", f"24칸이 아닌 줄 {len(off)}개: {off[:3]}")
    if len(pot_rows) != 10 * 17 + 7:
        bad("PotSprites", f"줄 수 {len(pot_rows)} (기대 177)")

    g_rows = grids_in(ps, "enum GardenSprites", "enum PlantSpriteBuilder")
    off = [r for r in g_rows if len(r) != 16]
    if off:
        bad("GardenSprites", f"16칸이 아닌 줄 {len(off)}개: {off[:3]}")
    if len(g_rows) != 3 * 16:
        bad("GardenSprites", f"줄 수 {len(g_rows)} (기대 48: 실루엣 3종 × 16줄)")

    ic = read("Core/IconSprites.swift")
    for name, start, end, expect in [
        ("ItemIcons", "enum ItemIcons", "enum DecorIcons", 8 * 16),
        # 장식 12개(0번) + 움직이는 것들의 추가 프레임. 장수는 **원본(gen_decor.py)에서**
        # 센다 — 여기 숫자를 손으로 적어두면 프레임을 추가하고 `--write` 를 빼먹어도
        # 통과한다. 그 경우 파이썬에는 있고 Swift 에는 없는 프레임이 생긴다.
        ("DecorIcons", "enum DecorIcons", "enum BirdIcon", (12 + anim_frames()) * 16),
        ("BirdIcon", "enum BirdIcon", "enum MenuBarSprites", bird_frames() * 16),
        ("MenuBarSprites", "enum MenuBarSprites", None, 10 * 11 + 5),
    ]:
        rows = grids_in(ic, start, end)
        off = [r for r in rows if len(r) != 16]
        if off:
            bad(name, f"16칸이 아닌 줄 {len(off)}개: {off[:3]}")
        if len(rows) != expect:
            bad(name, f"줄 수 {len(rows)} (기대 {expect})")

    # 실루엣에 손으로 그린 아웃라인(K)이 있으면 decorate() 가 이중 처리한다.
    # 아웃라인은 코드가 4-이웃으로 만든다 — 실루엣은 K 가 하나도 없어야 한다.
    for name, text, start, end in [("PotSprites", ps, "static let stages", "enum GardenSprites"),
                                   ("MenuBarSprites", ic, "static let plants", None)]:
        rows = grids_in(text, start, end)
        if not rows:
            bad(name, "실루엣 줄을 하나도 못 읽었다 — 검사가 헛돌고 있다")
            continue
        for r in rows:
            if "K" in r:
                bad(name, f"실루엣에 손으로 그린 아웃라인: {r}")
                break


# ── 4. 팔레트에 없는 문자 ──────────────────────────────────────

def palette_keys(text, enum_name):
    """팔레트 딕셔너리의 키 문자들.

    `enum X` 다음 첫 `]` 로 자르면 `[Character: String]` 의 대괄호에 걸린다 —
    `= [` 뒤부터 봐야 한다.
    """
    seg = text[text.index(enum_name):]
    seg = seg[seg.index("= ["):]
    seg = seg[:seg.index("]")]
    return set(re.findall(r'"(.)": "#', seg))


def check_characters():
    ps = read("Core/PlantSprites.swift")
    ic = read("Core/IconSprites.swift")

    plant = palette_keys(ps, "enum PlantPalette") | {".", "K"}
    icon = palette_keys(ic, "enum IconPalette") | {"."}

    for name, text, start, end, known in [
        ("PotSprites", ps, "enum PotSprites", "enum GardenSprites", plant),
        ("GardenSprites", ps, "enum GardenSprites", "enum PlantSpriteBuilder", plant),
        ("ItemIcons", ic, "enum ItemIcons", "enum DecorIcons", icon),
        ("DecorIcons", ic, "enum DecorIcons", "enum BirdIcon", icon),
        ("BirdIcon", ic, "enum BirdIcon", "enum MenuBarSprites", icon),
        ("MenuBarSprites", ic, "enum MenuBarSprites", None, plant),
    ]:
        seen = set("".join(grids_in(text, start, end)))
        unknown = seen - known
        if unknown:
            bad(name, f"팔레트에 없는 문자 {sorted(unknown)} — 투명 구멍이 된다")


# ── 5. 상점 품목 ↔ 아이콘 ──────────────────────────────────────

def check_shop_icons():
    shop = read("Core/PlantShop.swift")
    seg = shop[shop.index("enum ShopItem"):shop.index("var name: String")]
    items = re.findall(r"case (\w+)", seg)
    if len(items) != 11:
        bad("ShopItem", f"품목이 11개가 아니다 ({len(items)}개)")

    ic = read("Core/IconSprites.swift")
    keys = set(re.findall(r'"(\w+)": \[', ic))
    missing = [i for i in items if i not in keys]
    if missing:
        bad("IconSprites", f"아이콘 없는 품목 {missing} — 그 줄만 이모지로 튄다")

    # 장식은 `shopKeys` + `gachaKeys` 로 선언되고 정원이 그 키로 아트를 찾는다.
    # 선언에만 있고 아트가 없으면 정원에 빈칸이 놓이고, 뽑기는 그걸 "받았다"고 말한다.
    dseg = ic[ic.index("enum DecorIcons"):ic.index("enum BirdIcon")]
    dkeys = set(re.findall(r'"(\w+)": \[', dseg))
    declared = []
    for field in ("shopKeys", "gachaKeys"):
        m = re.search(rf"static let {field} = \[(.*?)\]", dseg, re.S)
        if not m:
            bad("DecorIcons", f"{field} 선언이 없다")
            continue
        declared += re.findall(r'"(\w+)"', m.group(1))
    for d in declared:
        if d not in dkeys:
            bad("DecorIcons", f"{d} 장식 아트가 없다 — 정원에 빈칸이 놓인다")
    if len(set(declared)) != len(declared):
        bad("DecorIcons", "같은 장식이 상점과 뽑기에 둘 다 있다 — 이미 산 걸 또 뽑는다")

    # 상점에서 직접 사는 장식(`isDecoration`)과 `shopKeys` 가 같아야 한다.
    decor_seg = shop[shop.index("var isDecoration"):]
    decor_seg = decor_seg[:decor_seg.index("}")]
    shop_decor = {d.strip().lstrip(".") for part in re.findall(r"case ([.\w, ]+):", decor_seg)
                  for d in part.split(",") if d.strip()}
    m = re.search(r"static let shopKeys = \[(.*?)\]", dseg, re.S)
    if m:
        keys = set(re.findall(r'"(\w+)"', m.group(1)))
        # decorBox 는 장식이 아니라 장식을 **뽑는** 소모품이라 여기 끼면 안 된다.
        if shop_decor != keys:
            bad("DecorIcons", f"상점 장식 {sorted(shop_decor)} 과 shopKeys {sorted(keys)} 가 다르다")

    # 뽑기 자리 — 캔버스에 열두 개가 들어가는가(GardenView.decorSpots 와 같은 식)
    gv = read("UI/GardenView.swift")
    if "DecorIcons.size + 2" not in gv:
        bad("decorSpots", "장식 자리가 계산식이 아니다 — 늘어난 장식이 조용히 안 그려진다")
    # 그리기·클릭·끌기가 **같은 함수**를 봐야 한다. 갈리면 엉뚱한 장식이 잡힌다
    # (정원 나무에서 이미 한 번 그렇게 어긋났다).
    if "func decorPlacements" not in gv:
        bad("decorPlacements", "장식 자리 계산이 한 곳에 없다")
    if gv.count("layout.decorPlacements(") < 2:
        bad("decorPlacements", "그리기와 끌기가 같은 자리 계산을 안 쓴다")

    # ── 움직이는 것 ────────────────────────────────────────────
    #
    # 프레임이 있는 장식은 0번(`art`)과 나머지(`frames`)가 **같은 키**를 써야 한다.
    # 프레임만 있고 0번이 없으면 `grid(_:frame:)` 이 nil 을 주고 장식이 통째로 사라진다.
    m = re.search(r"static let frames: \[String: \[\[String\]\]\] = \[(.*?)\n    \]", dseg, re.S)
    if not m:
        bad("DecorIcons", "frames 선언이 없다 — 움직이는 장식이 정지 화면이 된다")
    else:
        fkeys = re.findall(r'^        "(\w+)": \[', m.group(1), re.M)
        for k in fkeys:
            if not re.search(rf'^        "{k}": \[\n            "', dseg, re.M):
                bad("DecorIcons", f"{k} 는 프레임만 있고 0번 아트가 없다")
        if not fkeys:
            bad("DecorIcons", "frames 가 비었다")

    # 새는 **소유물이 아니다.** 목록에 끼면 도감에 영영 안 채워지는 칸이 생긴다.
    if "bird" in declared:
        bad("BirdIcon", "새가 장식 목록에 있다 — 새는 사는 게 아니라 찾아오는 것이다")

    # 정원이 실제로 프레임을 쓰는가. 파일에 프레임이 있어도 `compose` 가 0번만 그리면
    # 화면은 여전히 정지 화면이다 — 스프라이트만 늘고 아무 일도 안 일어난다.
    for needle, why in [
        ("DecorIcons.grid(key, frame: frame)", "장식이 프레임을 안 쓴다"),
        ("BirdIcon.grid(frame: bird.art)", "새가 자세를 안 쓴다"),
        ("func birdPerch", "새 자리 계산이 없다"),
        ("func hasMotion", "움직일 게 없을 때 타이머를 멈출 방법이 없다"),
        ("activeState != .inactive", "창이 뒤에 있어도 5fps 로 다시 그린다"),
        ("struct GardenCanvas", "돌리는 코드가 뷰마다 흩어져 있다 — 두 화면의 새가 다르게 논다"),
        ("BirdFlight.pose(", "새가 날아오지 않는다 — 자리가 바뀌면 순간이동한다"),
        (".onChange(of: perch", "모이통을 옮겨도 새가 따라오지 않는다"),
        ("bird.facingLeft ? BirdIcon.size - 1 - gx : gx",
         "새가 가는 쪽을 안 본다 — 왼쪽으로 갈 때 뒷걸음질로 날아온다"),
    ]:
        if needle not in gv:
            bad("GardenView", why)

    # 모이통·물받이가 새를 부르는 유일한 조건이다. 여기서 키를 바꾸면 조용히 새가 안 온다.
    for k in ("feeder", "birdbath"):
        if f'== "{k}"' not in gv:
            bad("birdPerch", f"{k} 가 새를 부르지 않는다")
    # 미니뷰도 같이 움직여야 한다. 정원 창은 3그루부터 열리는데 바람개비·고양이·새는
    # 그 전에 나온다 — 미니뷰가 정지 화면이면 처음 몇 달은 아무도 못 본다.
    cv = read("UI/CollectionView.swift")
    if "GardenCanvas(" not in cv:
        bad("CollectionView", "도감 미니뷰가 정지 화면이다 — 정원 창은 3그루부터라 그전엔 여기서만 보인다")
    # 큰 창과 미니뷰가 **같은 캔버스**를 써야 한다. 갈리면 두 화면의 새가 다르게 논다.
    if "GardenCanvas(layout:" not in gv:
        bad("GardenView", "정원 창이 공용 캔버스를 안 쓴다 — 미니뷰와 새가 다르게 논다")

    # 한도 조회가 30초 틱에 다시 묶이면 안 된다. 한 번 그렇게 묶여서 하루 2,880번을
    # usage 엔드포인트에 보냈고 429 를 받았다 — 화면에는 "한도 조회가 제한됐어요"만 남는다.
    app = read("TokenPlantApp.swift")
    if "guard shouldReadLimits else { return }" not in app:
        bad("TokenPlantApp", "한도 조회에 주기 제한이 없다 — 30초마다 네트워크와 프로세스를 때린다")
    # 한도 조회가 성장 경로와 **같은 Task** 에 있으면, codex 프로세스가 한 번 안 끝날 때
    # `isRefreshing` 이 안 풀려서 앱이 조용히 멈춘다. 실제로 하루를 잃었다.
    if "Task { await refreshLimits() }" not in app:
        bad("TokenPlantApp", "한도 조회가 성장 경로에 묶여 있다 — 한 번 막히면 화분이 멈춘다")
    if "defer { isRefreshing = false }" not in app:
        bad("TokenPlantApp", "isRefreshing 래치를 defer 로 안 푼다 — 한 번 걸리면 영원히 갱신이 막힌다")
    if "refreshWatchdog" not in app:
        bad("TokenPlantApp", "멈춘 갱신을 풀어줄 감시견이 없다")
    if "limits.rateLimited" not in app:
        bad("TokenPlantApp", "429 를 받아도 안 쉰다 — 같은 주기로 계속 때리면 제한이 안 풀린다")

    # 게이지 라벨은 막대와 **같은 것**을 말해야 한다. 누적 물과 다음 단계 문턱을
    # `/` 로 이어 붙였더니 분수로 읽혀서, 막대(단계 진행도 11%)와 숫자(68%처럼 보임)가
    # 정반대를 가리켰다. 사용자는 "물이 안 찬다"로 읽었다.
    pv = read("UI/PotView.swift")
    if "stageProgress" in pv and '"/ \\(' in pv:
        bad("PotView", "게이지 라벨이 분수로 읽힌다 — 막대는 단계 진행도인데 숫자는 누적/문턱이다")

    # 저장 여부를 **호출부가** 판단하면 구멍이 생긴다. 지갑만 보다가 `lastDate` 변경을
    # 통째로 흘려서, 오늘 사용량이 0인 날 세이브가 어제 날짜에 얼어붙었다.
    ps = read("Core/PlantStore.swift")
    if "guard data != lastWritten else { return }" not in ps:
        bad("PlantStore", "persist 가 내용 변화를 스스로 안 본다 — 호출부가 조건을 들고 있으면 또 새어나간다")
    if "save.rawWallet != walletBefore" in ps:
        bad("PlantStore", "지갑이 변할 때만 저장한다 — lastDate 같은 변경이 안 남는다")

    sv = read("UI/ShopView.swift")
    if "새가 찾아와" not in sv:
        bad("ShopView", "모이통 설명에 새 이야기가 없다 — 아무도 새를 못 본다")


# ── 5b. 가격표가 두 언어에서 같은가 ───────────────────────────
#
# `engine_port.py` 는 Swift 를 돌릴 수 없는 환경에서 유일하게 실행되는 오라클이다.
# 그 둘의 가격표가 갈리면 파이썬 테스트 224개가 전부 **없는 앱**을 검증하게 된다.


def check_price_parity():
    shop = read("Core/PlantShop.swift")
    seg = shop[shop.index("var priceDays"):shop.index("var price:")]
    swift = {m[0]: float(m[1]) for m in re.findall(r"case \.(\w+): return ([\d.]+)", seg)}

    port = Path(__file__).with_name("engine_port.py").read_text(encoding="utf8")
    pseg = port[port.index("PRICE_DAYS = dict("):]
    pseg = pseg[:pseg.index(")")]
    py = {m[0]: float(m[1]) for m in re.findall(r"(\w+)=([\d.]+)", pseg)}

    if swift != py:
        only_swift = {k: v for k, v in swift.items() if py.get(k) != v}
        only_py = {k: v for k, v in py.items() if swift.get(k) != v}
        bad("가격표", f"Swift 와 포팅이 다르다 — Swift {only_swift} / 포팅 {only_py}")
        return

    assumed = re.search(r"assumedDailyRaw = ([\d_]+)", read("Core/PlantBalance.swift"))
    rate = int(assumed.group(1).replace("_", "")) if assumed else 0
    pr = re.search(r"ASSUMED_DAILY_RAW = ([\d_]+)", port)
    if not pr or int(pr.group(1).replace("_", "")) != rate:
        bad("기준 하루치", f"Swift {rate} ≠ 포팅 {pr.group(1) if pr else '없음'}")


# ── 5c. 테스트가 화폐 값을 손으로 박았나 ──────────────────────
#
# 값은 `ShopItem.priceDays × 하루 유입` 에서 나오므로 가격이 바뀌면 숫자가 통째로 움직인다.
# 테스트에 `s.rawWallet = 200_000` 처럼 박아두면 구매가 **조용히 실패**하고,
# 몇 줄 뒤 `s.pot2!` 같은 강제 언래핑에서 크래시한다. 실제로 그렇게 터졌다.
# 구매가 뒤따르는 리터럴만 잡는다 — 저장 왕복·부족분 테스트의 리터럴은 정상이다.

LITERAL_WALLET = re.compile(r"\brawWallet\s*=\s*([\d_]+)\s*$")


def check_test_currency_literals():
    tests = ROOT / "Tests"
    if not tests.exists():
        return
    for f in sorted(tests.rglob("*.swift")):
        lines = f.read_text(encoding="utf-8").split("\n")
        for i, line in enumerate(lines):
            m = LITERAL_WALLET.search(line.split("//")[0])
            if not m:
                continue
            window = "\n".join(lines[i + 1:i + 9])
            if "buy(" not in window:
                continue          # 구매가 없으면 리터럴이어도 상관없다
            bad(f.name,
                f"{i + 1}행: 지갑에 {m.group(1)} 을 박아두고 바로 구매한다 — "
                f"가격이 바뀌면 조용히 실패한다. `ShopItem.<품목>.price` 를 써라")


# ── 6. 단계 수 일치 ────────────────────────────────────────────

def check_stage_counts():
    bal = read("Core/PlantBalance.swift")
    at = bal.index("static let stageFractions")
    body = bal[bal.index("[", bal.index("=", at)):]
    body = body[:body.index("]")]
    body = re.sub(r"//[^\n]*", "", body)          # 줄마다 단계 이름 주석이 붙어 있다
    fracs = [x.strip() for x in body.strip("[\n ").split(",") if x.strip()]
    n = len(fracs)
    if n != 10:
        bad("PlantBalance", f"임계값 단계가 {n}개 (기대 10)")

    # 비율은 0 에서 시작해 오름차순이고 1 미만이어야 한다 —
    # 마지막 단계가 1.0 이면 만렙과 이식이 같은 순간이 돼서 거목을 볼 틈이 없다.
    vals = [float(x) for x in fracs]
    if vals[0] != 0:
        bad("PlantBalance", f"stageFractions 첫 값이 {vals[0]} (기대 0)")
    if vals[-1] >= 1.0:
        bad("PlantBalance", f"stageFractions 마지막 값이 {vals[-1]} — 1 미만이어야 한다")
    for i in range(1, n):
        if vals[i] <= vals[i - 1]:
            bad("PlantBalance", f"stageFractions[{i}] 가 앞 단계보다 작다")

    ps = read("Core/PlantSprites.swift")
    levels = len(re.findall(r"level: \d+", ps))
    if levels and levels != n:
        bad("PotSprites", f"스프라이트 단계 {levels} ≠ 임계값 단계 {n}")

    ic = read("Core/IconSprites.swift")
    # `static let plants` 는 `pot` 뒤에 오므로 여기서부터 끝까지가 식물 줄이다.
    menu = len(grids_in(ic, "static let plants", None))
    if menu % 11 or menu // 11 != n:
        bad("MenuBarSprites", f"메뉴바 줄 {menu} (기대 {n}단계 × 11줄)")


# ── 7. 꽃 모티프 ────────────────────────────────────────────────

DIMS = {"big": (7, 5), "small": (5, 3), "fruit": (3, 2)}


def swift_motifs():
    """PlantSprites.swift 의 생성된 BloomMotif.art 를 다시 읽어온다."""
    s = read("Core/PlantSprites.swift")
    at = s.index("var art: BloomArt")
    body = s[at: s.index("\n}", at)]
    out = {}
    for chunk in body.split("case .")[1:]:
        name = re.match(r"(\w+)", chunk).group(1)
        art = {}
        for key in ("big", "small", "fruit"):
            m = re.search(rf"{key}: \[(.*?)\]", chunk, re.S)
            if m:
                art[key] = re.findall(r'"([^"]*)"', m.group(1))
        out[name] = art
    return out


def check_motifs():
    """스탬프 치수 · 종 대응 · 파이썬↔Swift 일치.

    파이썬 쪽(`preview_species.py`)이 원본이고 Swift 는 `gen_motifs.py` 가 만든다.
    둘이 어긋나면 화면에서 본 것과 앱에 들어간 것이 달라진다 — 가격표를 양언어로
    맞춰 둔 것과 같은 이유다.
    """
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    try:
        from preview_species import MOTIFS, ANCHORS, SPECIES_MOTIF
    except Exception as e:                       # noqa: BLE001
        bad("BloomMotif", f"파이썬 모티프를 못 읽었다: {e}")
        return

    sw = swift_motifs()

    # 치수
    for name, art in MOTIFS.items():
        for key, (w, h) in DIMS.items():
            rows = art.get(key)
            if rows is None:
                bad("BloomMotif", f"{name}.{key} 가 없다")
                continue
            if len(rows) != h or any(len(r) != w for r in rows):
                shape = f"{len(rows)}줄 × {sorted({len(r) for r in rows})}칸"
                bad("BloomMotif", f"{name}.{key} 가 {w}×{h} 가 아니다 ({shape})")

    # 양언어 일치
    if set(sw) != set(MOTIFS):
        only_py = sorted(set(MOTIFS) - set(sw))
        only_sw = sorted(set(sw) - set(MOTIFS))
        bad("BloomMotif", f"모티프 목록이 다르다 — 파이썬만 {only_py}, Swift만 {only_sw}"
                          " (verify/gen_motifs.py --write 를 다시 돌려라)")
    for name in sorted(set(sw) & set(MOTIFS)):
        for key in DIMS:
            if sw[name].get(key) != MOTIFS[name].get(key):
                bad("BloomMotif", f"{name}.{key} 가 파이썬과 Swift 에서 다르다"
                                  " (verify/gen_motifs.py --write)")

    # 종 대응 — 빠진 종이 있으면 화분이 엉뚱한 꽃을 단다
    model = read("Core/PlantModel.swift")
    ids = re.findall(r'\.init\(id: "([^"]+)"', model)
    assigned = dict(re.findall(r'\.init\(id: "([^"]+)".*?motif: \.(\w+)\)', model, re.S))
    for pid in ids:
        if pid not in assigned:
            bad("PlantSpecies", f"{pid} 에 motif 가 없다")
        elif assigned[pid] not in MOTIFS:
            bad("PlantSpecies", f"{pid} 가 없는 모티프 .{assigned[pid]} 를 가리킨다")
        elif SPECIES_MOTIF.get(pid) != assigned[pid]:
            bad("PlantSpecies", f"{pid}: Swift 는 .{assigned[pid]}, 파이썬은 "
                                f".{SPECIES_MOTIF.get(pid)}")

    # 앵커가 식물 영역(24칸 × 17줄) 안에서 스탬프를 다 담는지
    for lv, anchors in enumerate(ANCHORS, 1):
        for row, col, size in anchors:
            w, h = DIMS[size] if size in DIMS else (3, 3)
            if row - h // 2 < 0 or row + h // 2 > 16:
                bad("BloomLayout", f"Lv.{lv} 앵커({row},{col}) {size} 가 위아래로 넘친다")
            if col - w // 2 < 0 or col + w // 2 > 23:
                bad("BloomLayout", f"Lv.{lv} 앵커({row},{col}) {size} 가 좌우로 넘친다")



def check_garden_blooms():
    """정원(16x16) 꽃이 **잎 안쪽**에 찍히는지.

    가장자리에 걸치면 꽃이 허공에 뜬 것처럼 보인다. 모양 3종 × 모티프 15종을
    전부 곱해 봐야 한다 — 모티프마다 `small` 의 채워진 칸이 달라서,
    하나만 통과한다고 나머지가 안전하지 않다.
    """
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    try:
        from preview_species import MOTIFS, GARDEN_ANCHORS, garden_shapes
    except Exception as e:                       # noqa: BLE001
        bad("GardenBloom", f"파이썬 정원 데이터를 못 읽었다: {e}")
        return

    shapes = garden_shapes()

    # Swift 쪽 앵커와 일치하는지
    sw = read("Core/PlantSprites.swift")
    at = sw.find("enum GardenBloomLayout")
    if at < 0:
        bad("GardenBloom", "GardenBloomLayout 이 없다 (verify/gen_motifs.py --write)")
    else:
        body = sw[at: sw.index("\n}", at)]
        for name, pts in GARDEN_ANCHORS.items():
            m = re.search(rf"case \.{name}: return \[(.*?)\]", body)
            got = [(int(a), int(b)) for a, b in
                   re.findall(r"row: (\d+), col: (\d+)", m.group(1))] if m else []
            if got != [tuple(p) for p in pts]:
                bad("GardenBloom", f"{name} 앵커가 파이썬({pts})과 Swift({got})에서 다르다"
                                   " (verify/gen_motifs.py --write)")

    for name, anchors in GARDEN_ANCHORS.items():
        rows = shapes.get(name)
        if not rows:
            bad("GardenBloom", f"{name} 모양을 못 읽었다")
            continue
        if len(rows) != 16 or any(len(r) != 16 for r in rows):
            bad("GardenBloom", f"{name} 이 16x16 이 아니다")
            continue
        if not anchors:
            bad("GardenBloom", f"{name} 에 꽃 자리가 없다 — 이식하면 꽃이 사라진다")
        for (r, c) in anchors:
            for mname, mot in MOTIFS.items():
                art = mot["small"]
                h, w = len(art), len(art[0])
                top, left = r - h // 2, c - w // 2
                for y, line in enumerate(art):
                    for x, ch in enumerate(line):
                        if ch in "._":
                            continue
                        gy, gx = top + y, left + x
                        if not (0 <= gy < 16 and 0 <= gx < 16) or rows[gy][gx] == ".":
                            bad("GardenBloom",
                                f"{name} 앵커({r},{c}) 에 {mname} 을 찍으면 "
                                f"({gy},{gx}) 가 잎 밖이다")
                            break
                    else:
                        continue
                    break


def main():
    check_scene()
    check_palettes()
    check_sprites()
    check_characters()
    check_shop_icons()
    check_price_parity()
    check_test_currency_literals()
    check_stage_counts()
    check_motifs()
    check_garden_blooms()

    if FAIL:
        print(f"데이터 검사 실패 {len(FAIL)}건\n")
        for f in FAIL:
            print("  ✗", f)
        return 1
    print("데이터 검사 통과 — 씬 레이아웃 · 스프라이트 격자 · 팔레트 · 품목 아이콘 · 가격표 양언어 일치 · 테스트 리터럴 · 단계 수 · 꽃 모티프 · 정원 개화")
    return 0


if __name__ == "__main__":
    sys.exit(main())
