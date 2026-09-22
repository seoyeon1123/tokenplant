# -*- coding: utf-8 -*-
"""파이썬 모티프 데이터 → Swift 코드 생성.

    python3 verify/gen_motifs.py            # 생성된 Swift 를 화면에 출력
    python3 verify/gen_motifs.py --write    # PlantSprites.swift 에 써넣는다

픽셀아트는 `preview_species.py` 에서 **보면서** 다듬고, 확정된 것만 여기로 흘려보낸다.
손으로 옮기면 24칸 격자 한 줄이 23칸이 되는 식으로 반드시 어긋난다 —
가격표를 양언어로 맞춰 둔 것과 같은 이유다.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from preview_species import (MOTIFS, ANCHORS, BUD, SPECIES_MOTIF,  # noqa: E402
                             GARDEN_ANCHORS)

ROOT = Path(__file__).resolve().parent.parent
SPRITES = ROOT / "Sources/TokenPlant/Core/PlantSprites.swift"

BEGIN = "// MARK: 생성됨 — verify/gen_motifs.py (손으로 고치지 말 것)"
END = "// MARK: 생성 끝"


def swift_rows(rows, indent):
    """마지막 줄엔 쉼표를 안 붙인다. Swift 가 허용하긴 하지만 생성물이 지저분해진다."""
    pad = " " * indent
    return (",\n" + pad).join(f'"{r}"' for r in rows)


def emit():
    out = [BEGIN, ""]
    out.append("""/// 꽃이 붙는 자리의 크기. 스탬프를 고른다.
enum BloomSize: Sendable {
    case bud, small, big, fruit
}

/// 꽃이 붙는 자리 — 원본 실루엣의 꽃 덩이 무게중심에서 뽑았다.
struct BloomAnchor: Sendable {
    let row: Int
    let col: Int
    let size: BloomSize
}

/// 한 모티프의 스탬프 세 장. `big` 7×5, `small` 5×3, `fruit` 3×2.
struct BloomArt: Sendable {
    let big: [String]
    let small: [String]
    let fruit: [String]
}

/// 꽃·열매 모티프.
///
/// 종마다 실루엣 10장을 손으로 그리면 150장이 된다. 그래서 **잎은 공용**으로 두고
/// 꽃만 갈아끼운다 — 사람이 보는 건 결국 꽃이고, 잎 덩이는 종이 달라도 비슷하다.
/// 꽃이 없는 종(상추·몬스테라·대나무)은 잎 특징을 모티프 자리에 넣어 구분한다.
enum BloomMotif: String, Codable, Sendable, CaseIterable {""")
    out.append("    case " + ", ".join(MOTIFS.keys()))
    out.append("")
    out.append("""    /// `.` = 밑의 잎을 그대로 둔다   `_` = 구멍을 뚫는다   나머지 = 칠한다
    var art: BloomArt {
        switch self {""")
    for name, m in MOTIFS.items():
        out.append(f"        case .{name}:")
        out.append("            return BloomArt(")
        out.append("                big: [" + swift_rows(m["big"], 22) + "],")
        out.append("                small: [" + swift_rows(m["small"], 24) + "],")
        out.append("                fruit: [" + swift_rows(m["fruit"], 24) + "])")
    out.append("        }")
    out.append("    }")
    out.append("}")
    out.append("")

    # 꽃봉오리는 공용
    out.append("""/// 꽃봉오리는 종을 안 가린다 — 실제로도 봉오리는 다 비슷하게 생겼다.
/// 꽃잎색만 한 픽셀 비쳐서 "뭐가 필지" 짐작만 되게 한다.
enum BloomBud {
    static let art: [String] = [""" + swift_rows(BUD, 8) + "]\n}")
    out.append("")

    # 앵커
    names = ["씨앗", "발아", "떡잎", "어린잎", "자란 줄기",
             "꽃봉오리", "첫 꽃", "만개", "열매", "거목"]
    out.append("""/// 단계별 꽃 자리. Lv.1~5 는 비어 있다 — 실제로도 그 시기엔 꽃이 없다.
enum BloomLayout {
    static let anchors: [[BloomAnchor]] = [""")
    for i, (row, nm) in enumerate(zip(ANCHORS, names)):
        if not row:
            out.append(f"        [],                                  // Lv.{i+1} {nm}")
        else:
            items = ", ".join(
                f".init(row: {r}, col: {c}, size: .{s})" for r, c, s in row)
            out.append(f"        // Lv.{i+1} {nm}")
            out.append(f"        [{items}],")
    out.append("    ]")
    out.append("}")
    out.append("")

    # 정원(16x16) 개화 자리
    out.append("""/// 정원에 심긴 그루의 꽃 자리(16x16).
///
/// 이식하고 나면 꽃이 사라지는 게 제일 이상했다 — 다 키워서 정원에 옮겼더니
/// 초록 덩이만 늘어서, 30그루를 모아도 보상이 "나무밭"이었다.
/// 화분과 같은 모티프를 작게(5x3) 얹어 이식한 뒤에도 그 종의 꽃이 계속 핀다.
///
/// 앵커는 잎 덩이 **안쪽**이어야 한다. 가장자리에 걸치면 꽃이 허공에 뜬 것처럼 보인다.
enum GardenBloomLayout {
    static func anchors(_ shape: PlantShape) -> [(row: Int, col: Int)] {
        switch shape {""")
    for name in ("round", "tall", "low"):
        pts = ", ".join(f"(row: {r}, col: {c})" for r, c in GARDEN_ANCHORS[name])
        out.append(f"        case .{name}: return [{pts}]")
    out.append("        }")
    out.append("    }")
    out.append("}")
    out.append("")
    out.append(END)
    return "\n".join(out)


def main():
    code = emit()

    # 종 → 모티프 대응이 빠진 게 없는지 먼저 본다.
    model = (ROOT / "Sources/TokenPlant/Core/PlantModel.swift").read_text(encoding="utf-8")
    ids = re.findall(r'\.init\(id: "([^"]+)"', model)
    missing = [i for i in ids if i not in SPECIES_MOTIF]
    unknown = [v for v in SPECIES_MOTIF.values() if v not in MOTIFS]
    if missing:
        sys.exit(f"모티프가 안 정해진 종: {missing}")
    if unknown:
        sys.exit(f"없는 모티프를 가리킴: {unknown}")

    if "--write" not in sys.argv:
        print(code)
        return

    s = SPRITES.read_text(encoding="utf-8")
    if BEGIN in s:
        head = s[: s.index(BEGIN)]
        tail = s[s.index(END) + len(END):]
        s = head + code + tail
    else:
        s = s.rstrip() + "\n\n" + code + "\n"
    SPRITES.write_text(s, encoding="utf-8")
    print(f"PlantSprites.swift 갱신 · 모티프 {len(MOTIFS)}종 · 종 {len(ids)}개 전부 대응됨")


if __name__ == "__main__":
    main()
