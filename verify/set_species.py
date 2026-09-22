# -*- coding: utf-8 -*-
"""지금 키우는 화분의 **종만** 갈아끼운다. 물과 단계는 그대로 둔다.

    python3 verify/set_species.py                 # 고를 수 있는 종 목록
    python3 verify/set_species.py cherry          # 벚나무로 교체
    python3 verify/set_species.py cherry --slot 1 # 두 번째 화분
    python3 verify/set_species.py --random        # 아무거나

지금은 한 번 심으면 이식할 때까지 4주를 같은 종으로 보게 된다. 마음에 안 드는 종이
걸리면 한 달을 참아야 하는데, 그건 수집 게임에서 제일 빨리 질리는 구조다.
제대로 고치려면 앱 안에 "씨앗 다시 고르기"가 있어야 하고, 이 스크립트는 그 전까지의 임시방편이다.

앱이 켜져 있으면 30초마다 세이브를 덮어쓰므로, 먼저 끄고 고친 뒤 다시 켠다.
"""
import json
import random
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODEL = ROOT / "Sources/TokenPlant/Core/PlantModel.swift"
SAVE = Path.home() / "Library/Application Support/TokenPlant/state.json"
APP = "/Applications/TokenPlant.app"


def catalog():
    """종 목록을 소스에서 읽는다 — 목록을 두 군데 두면 반드시 어긋난다."""
    s = MODEL.read_text(encoding="utf-8")
    body = s[s.index("static let catalog"):]
    body = body[: body.index("\n    ]")]
    out = []
    for chunk in body.split(".init(id:")[1:]:
        chunk = chunk[: chunk.index(")")]
        pid = re.match(r'\s*"([^"]+)"', chunk).group(1)

        def field(key):
            m = re.search(rf'{key}: "([^"]*)"', chunk)
            return m.group(1) if m else None

        def bare(key):
            m = re.search(rf"{key}: \.(\w+)", chunk)
            return m.group(1) if m else None

        out.append(dict(id=pid, name=field("name"),
                        rarity=bare("rarity"), motif=bare("motif")))
    return out


RARITY_KO = {"common": "흔함", "uncommon": "보통", "rare": "희귀", "legendary": "전설"}


def show(items, current=None):
    print("고를 수 있는 종:\n")
    order = ["common", "uncommon", "rare", "legendary"]
    for r in order:
        rows = [c for c in items if c["rarity"] == r]
        if not rows:
            continue
        print(f"  [{RARITY_KO.get(r, r)}]")
        for c in rows:
            mark = " ← 지금" if c["id"] == current else ""
            print(f"    {c['id']:<14} {c['name']:<7} 꽃 {c['motif']}{mark}")
        print()
    print("  예:  python3 verify/set_species.py cherry")


def app_running():
    return subprocess.run(["pgrep", "-x", "TokenPlant"],
                          capture_output=True).returncode == 0


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    slot = 0
    if "--slot" in sys.argv:
        slot = int(sys.argv[sys.argv.index("--slot") + 1])
        args = [a for a in args if a != str(slot)]

    items = catalog()
    ids = {c["id"]: c for c in items}

    if not SAVE.exists():
        sys.exit(f"세이브가 없습니다: {SAVE}\n앱을 한 번 실행해 주세요.")
    data = json.loads(SAVE.read_text(encoding="utf-8"))

    key = "pot" if slot == 0 else "pot2"
    pot = data.get(key)
    if not pot:
        sys.exit(f"{slot + 1}번 화분이 비어 있습니다.")
    current = pot.get("speciesID")

    if "--random" in flags:
        pick = random.choice([c["id"] for c in items if c["id"] != current])
    elif args:
        pick = args[0]
    else:
        show(items, current)
        return

    if pick not in ids:
        near = [i for i in ids if pick.lower() in i.lower()]
        hint = f"\n비슷한 것: {near}" if near else ""
        sys.exit(f"그런 종이 없습니다: {pick}{hint}\n목록: python3 verify/set_species.py")

    if pick == current:
        print(f"이미 {ids[pick]['name']} 입니다.")
        return

    was_running = app_running()
    if was_running:
        # 앱이 켜져 있으면 30초마다 세이브를 덮어써서 방금 고친 게 사라진다.
        subprocess.run(["pkill", "-x", "TokenPlant"], capture_output=True)
        print("앱을 잠시 껐습니다.")

    backup = SAVE.with_suffix(f".json.{datetime.now():%Y%m%d%H%M%S}.bak")
    shutil.copy2(SAVE, backup)

    data = json.loads(SAVE.read_text(encoding="utf-8"))   # 껐을 때 쓴 내용을 다시 읽는다
    data[key]["speciesID"] = pick
    SAVE.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")

    old = ids.get(current, {}).get("name", current)
    new = ids[pick]
    water = data[key].get("water", 0)
    stage = (data[key].get("stageIndex") or 0) + 1
    print(f"{old} → {new['name']} ({RARITY_KO.get(new['rarity'], new['rarity'])}, 꽃 {new['motif']})")
    print(f"진행도 유지: Lv.{stage} · {water:,} mL")
    print(f"되돌리려면: cp \"{backup}\" \"{SAVE}\"")

    if was_running and Path(APP).exists():
        subprocess.run(["open", APP])
        print("앱을 다시 켰습니다.")


if __name__ == "__main__":
    main()
