#!/usr/bin/env python3
"""타입에 없는 멤버를 부르는 곳을 찾는다.

컴파일러가 없으니 "리팩터로 지운 심볼을 어딘가 아직 부르고 있다"를 잡을 방법이
필요하다. 완전한 타입 검사는 못 한다 — 대신 우리가 직접 정의한 타입들
(PlantBalance / PlantEngine / PlantSave / ShopItem / ...)에 대해서만
`Type.member` 와 열거형 `.case` 표기를 모아 선언과 대조한다.

거짓 양성을 만들지 않기 위해 **우리 타입만** 본다. Foundation·SwiftUI 멤버는
이름이 겹칠 때만 걸리는데, 그건 어차피 사람이 봐야 하는 자리다.
"""
import re
import sys
import pathlib
from collections import defaultdict

from tree_sitter import Language, Parser
import tree_sitter_swift

LANG = Language(tree_sitter_swift.language())
PARSER = Parser(LANG)

# 이 타입들에 대해서만 멤버를 검사한다.
WATCHED = {
    "PlantBalance", "PlantEngine", "PlantSave", "PotState", "ShopItem",
    "PlantSpecies", "PlantOdds", "PotSprites", "MenuBarSprites", "ItemIcons",
    "GardenTier", "PlantRarity", "PlantStateKind", "PlantEvent", "DayKey",
    "TokenDelta", "LimitsReader", "LimitsSnapshot", "LimitWindowInfo",
    "WindowKind", "UsageReader", "PlantStore", "RepotSoil", "GardenEntry",
    "PurchaseResult", "UseResult", "TokenFormat", "GardenScene",
    "LoginItem", "Water", "Nutrient", "AppModel",
    "BloomMotif", "BloomLayout", "BloomBud", "BloomArt", "BloomAnchor", "BloomSize",
    "GardenSprites", "GardenComposer", "PlantSpriteBuilder", "PlantPalette",
}

DECL = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:public\s+|internal\s+|private(?:\(set\))?\s+|fileprivate\s+|"
    r"static\s+|class\s+|final\s+|lazy\s+|override\s+|@discardableResult\s+|"
    r"nonisolated\s+|mutating\s+|convenience\s+)*"
    r"(?:func|var|let|case|init|subscript)\b"
)
NAME = re.compile(r"(?:func|var|let|case|init|subscript)\s+([A-Za-z_]\w*)")


def type_blocks(path: str):
    """파일에서 (타입이름, 시작줄, 끝줄) 을 뽑는다. extension 도 같은 이름으로 친다."""
    src = pathlib.Path(path).read_bytes()
    tree = PARSER.parse(src)
    out = []

    def walk(node):
        if node.type in ("class_declaration", "protocol_declaration"):
            # class_declaration 이 struct/enum/class/actor/extension 을 모두 덮는다.
            name = None
            for c in node.children:
                if c.type in ("type_identifier", "simple_identifier", "user_type"):
                    name = src[c.start_byte:c.end_byte].decode()
                    break
            if name:
                out.append((name.split("<")[0].split(".")[0],
                            node.start_point[0], node.end_point[0]))
        for c in node.children:
            walk(c)

    walk(tree.root_node)
    return out, src.decode("utf8", "replace").split("\n")


CASE_DECL = re.compile(r"^\s*case\s+(.+)$")


def collect_cases(root):
    """enum 의 **case 이름만** 따로 모은다.

    빠진 case 검사에 `declared`(var·func 까지 포함)를 쓰면 `name`, `price` 같은
    계산 프로퍼티가 전부 "빠진 case" 로 잡힌다 — 실제로 그렇게 터졌다.
    """
    cases = defaultdict(set)
    for f in sorted(pathlib.Path(root).rglob("*.swift")):
        blocks, lines = type_blocks(str(f))
        for name, lo, hi in blocks:
            if name not in ENUMS:
                continue
            for i in range(lo, min(hi + 1, len(lines))):
                code = lines[i].split("//")[0]
                m = CASE_DECL.match(code)
                if not m or ":" in m.group(1).split("(")[0]:
                    continue          # `case .x:` 는 switch 라벨이지 선언이 아니다
                # 딸린 값을 먼저 지운다 — `case newSeed(rarity:, isShiny:)` 에서
                # 쉼표로 나누면 `rarity`·`isShiny` 가 case 이름으로 잡힌다.
                body = re.sub(r"\([^)]*\)", "", m.group(1))
                for part in body.split(","):
                    ident = re.match(r"\s*([a-z]\w*)", part)
                    if ident:
                        cases[name].add(ident.group(1))
    return cases


def collect_declared(root):
    declared = defaultdict(set)
    for f in sorted(pathlib.Path(root).rglob("*.swift")):
        blocks, lines = type_blocks(str(f))
        # 중첩 타입도 멤버다 — `LimitsReader.ClaudeLimits` 처럼 불린다.
        for name, lo, hi in blocks:
            for outer, olo, ohi in blocks:
                if outer in WATCHED and olo < lo and hi <= ohi:
                    declared[outer].add(name)
        for name, lo, hi in blocks:
            if name not in WATCHED:
                continue
            for i in range(lo, min(hi + 1, len(lines))):
                line = lines[i]
                if not DECL.match(line):
                    continue
                for m in NAME.finditer(line):
                    declared[name].add(m.group(1))
                # `case a, b, c` / `var (a, b)` 같은 나열
                if re.match(r"\s*case\s", line):
                    for m in re.finditer(r"[,\s]([a-z]\w*)\s*(?:[,=(]|$)", line):
                        declared[name].add(m.group(1))
    return declared


USE = re.compile(r"\b(" + "|".join(sorted(WATCHED)) + r")\.([A-Za-z_]\w*)")
# 타입 자체를 값으로 쓰거나 컴파일러가 합성해 주는 멤버 — 선언이 없는 게 정상이다.
SKIP = {"self", "Type", "init", "some", "shared",
        "allCases", "rawValue", "hashValue", "description"}

# 빠진 case 검사는 **순수 enum** 에만 건다.
# struct/함수 모음에 걸면 "선언 전부가 case" 라는 전제가 깨져 거짓 양성이 쏟아진다.
ENUMS = {"ShopItem", "PlantEvent", "PlantStateKind", "PlantRarity", "WindowKind",
         "PurchaseResult", "UseResult", "PopoverTab", "BloomMotif", "BloomSize"}

# static 함수 안에서 쓰면 안 되는 인스턴스 이름들.
# 이 코드베이스에서 이 이름들은 **항상** 뷰나 모델의 인스턴스 프로퍼티다.
INSTANCE_NAMES = ("store", "model", "self.store", "self.model")


SWITCH = re.compile(r"^\s*switch\b")
BARE_CASE = re.compile(r"\.(\w+)")


def switch_case_errors(root, declared, cases):
    """우리 enum 위의 `switch` 에서 **없는 case** 를 쓰는 곳을 찾는다.

    `case .repotSoil:` 처럼 타입 이름이 안 붙은 자리는 `Type.member` 정규식에 안 걸린다.
    실제로 그 구멍으로 삭제된 case 하나가 컴파일러까지 살아 나갔다.

    스위치의 대상 타입은 안 적혀 있으므로 **case 목록으로 역추적**한다:
    한 블록의 라벨 중 하나라도 어떤 enum 의 case 와 맞으면 그 enum 위의 스위치로 보고,
    나머지 라벨 중 그 enum 에 없는 이름을 잡는다. 하나도 안 맞으면 손대지 않는다.
    """
    out = []
    for f in sorted(pathlib.Path(root).rglob("*.swift")):
        lines = f.read_text(encoding="utf8").split("\n")
        block = None           # [(줄번호, 이름)]
        start = 0
        has_default = False
        depth = 0
        pending = ""           # 여러 줄에 걸친 case 라벨을 모은다
        for n, line in enumerate(lines, 1):
            code = line.split("//")[0]
            if SWITCH.match(code):
                block, start, has_default, depth, pending = [], n, False, 0, ""
            if block is None:
                continue
            depth += code.count("{") - code.count("}")
            if re.match(r"\s*default\s*:", code):
                has_default = True

            # `case .a, .b,` 처럼 줄이 넘어가는 라벨이 흔하다 — `:` 를 볼 때까지 이어붙인다.
            if pending or re.match(r"\s*case\s+\.", code):
                pending += " " + code.strip()
                if ":" in pending:
                    label = pending[:pending.index(":")]
                    # `case .ok where item == .decorBox && list.isEmpty:` —
                    # `where` 뒤는 **라벨이 아니라 조건식**이다. 안 자르면 거기 있는
                    # 모든 `.무엇`을 이 enum 의 case 로 읽어서 없는 case 라고 우긴다.
                    # (실제로 그렇게 오탐 두 건이 나왔다.)
                    m = re.search(r"\bwhere\b", label)
                    if m:
                        label = label[:m.start()]
                    for name in BARE_CASE.findall(label):
                        block.append((n, name))
                    pending = ""
                elif not pending.rstrip().endswith(","):
                    pending = ""      # 계속되는 라벨이 아니었다

            # 스위치가 닫혔다 — 이제 판정한다.
            if depth <= 0 and block:
                names = {name for _, name in block}
                best, hits = None, 0
                for typ, members in cases.items():
                    k = len(names & members)
                    if k > hits:
                        best, hits = typ, k
                # 라벨의 절반 이상이 한 enum 과 맞아야 그 enum 위의 스위치로 인정한다.
                if best and hits >= max(1, len(names) // 2):
                    for ln, name in block:
                        if name not in cases[best]:
                            out.append((str(f.relative_to(root)), ln, best,
                                        f"{best} 에 .{name} 가 없다", lines[ln - 1].strip()))
                    # 빠진 case — 컴파일러의 "switch must be exhaustive" 를 미리 잡는다.
                    # 이 프로젝트에서 실제로 터진 오류다(PlantEvent 에 case 를 추가했을 때).
                    if not has_default:
                        gap = cases[best] - names
                        if gap:
                            out.append((str(f.relative_to(root)), start, best,
                                        f"{best} 스위치에 빠진 case: {', '.join(sorted(gap))}",
                                        lines[start - 1].strip()))
                block = None
    return out


STATIC_FUNC = re.compile(r"^(\s*)(?:@\w+\s+)*(?:public |private |internal |fileprivate )?static func\s+(\w+)")


def static_scope_errors(root):
    """`static func` 안에서 인스턴스(`store`/`model`)를 참조하는 곳을 찾는다.

    실제로 이렇게 터졌다: 순수 함수인 `GardenComposer.compose` 안에 `store.species` 를
    썼는데, `Type.member` 만 보는 검사로는 소문자 식별자가 안 걸려서 그냥 통과했다.
    static 함수의 본문은 들여쓰기로 끝을 잡는다 — 중괄호 세기보다 오탐이 적다.
    """
    bad = []
    for f in sorted(pathlib.Path(root).rglob("*.swift")):
        lines = f.read_text(encoding="utf8").split("\n")
        i = 0
        while i < len(lines):
            m = STATIC_FUNC.match(lines[i])
            if not m:
                i += 1
                continue
            indent, fname = len(m.group(1)), m.group(2)
            # 파라미터로 받았다면 정당한 사용이다.
            sig = " ".join(lines[i:i + 8])
            params_ok = any(f"{n}:" in sig for n in INSTANCE_NAMES)
            j = i + 1
            while j < len(lines):
                line = lines[j]
                stripped = line.strip()
                if stripped and (len(line) - len(line.lstrip())) <= indent and not stripped.startswith(("}", ")", "//")):
                    break
                if stripped.startswith("}") and (len(line) - len(line.lstrip())) == indent:
                    break
                code = line.split("//")[0]
                if not params_ok:
                    for n in ("store", "model"):
                        if re.search(rf"\b{n}\.", code):
                            bad.append((str(f.relative_to(root)), j + 1, fname, n, stripped))
                j += 1
            i = j
    return bad


# `var x: [K: V]` / `let x: [K: V] = ...` 지역 선언. 값 타입이 옵셔널인지도 같이 본다.
DICT_DECL = re.compile(r"\b(?:var|let)\s+(\w+)\s*:\s*\[\s*[\w.]+\s*:\s*([^\]]+)\]")


def optional_on_nonoptional_errors(root):
    """사전을 순회하며 얻은 값에 `?.` 나 `??` 를 쓰는 곳을 찾는다.

    실제로 첫 `swift build` 에서 이걸로 터졌다:

        var windows: [String: DayWindow] = [:]
        for day in wanted { windows[day] = utcWindow(forLocalDay: day) }   // 옵셔널 대입
        for (k, w) in windows where w?.contains(ts) == true { ... }        // 컴파일 에러

    `windows[day] = nil` 은 값을 넣는 게 아니라 **키를 지우는 것**이라, 만들 때 옵셔널을
    대입해도 사전에 담기는 값은 non-optional 이다. 그래서 순회로 꺼낸 값에 옵셔널 체이닝을
    걸 수 없다 — 그런데 tree-sitter 는 이 줄을 아무 문제 없이 파싱한다.
    이 검사기가 잡지 않으면 Mac 에서 빌드를 돌릴 때까지 모른다.
    """
    bad = []
    for f in sorted(pathlib.Path(root).rglob("*.swift")):
        lines = f.read_text(encoding="utf8").split("\n")
        # 파일 전체에서 "값 타입이 옵셔널이 아닌 사전" 이름을 모은다.
        plain_dicts = set()
        for line in lines:
            for name, vtype in DICT_DECL.findall(line.split("//")[0]):
                if not vtype.strip().endswith("?"):
                    plain_dicts.add(name)
        if not plain_dicts:
            continue
        for n, line in enumerate(lines, 1):
            code = line.split("//")[0]
            # for (k, v) in <사전> ... 에서 v 를 잡는다.
            m = re.search(r"for\s+(?:case\s+)?\(\s*\w+\s*,\s*(\w+)\s*\)\s+in\s+(\w+)\b", code)
            if not m:
                continue
            var, dict_name = m.group(1), m.group(2)
            if dict_name not in plain_dicts:
                continue
            if re.search(rf"\b{var}\s*\?", code) or re.search(rf"\b{var}\s*!", code):
                bad.append((str(f.relative_to(root)), n, var, dict_name, line.strip()))
    return bad


def main(root):
    declared = collect_declared(root)
    cases = collect_cases(root)
    missing = defaultdict(list)

    # 감시 타입인데 선언을 하나도 못 읽었다 = 지워졌는데 아직 불리고 있다.
    # 예전에는 이런 타입을 조용히 건너뛰어서, 삭제된 `RepotSoil` 호출이 그대로 살아남았다.
    used_types = set()
    for f in sorted(pathlib.Path(root).rglob("*.swift")):
        for n, line in enumerate(f.read_text(encoding="utf8").split("\n"), 1):
            code = line.split("//")[0]
            for typ, member in USE.findall(code):
                used_types.add(typ)
                if not declared.get(typ):
                    missing[typ].append((str(f.relative_to(root)), n,
                                         f"{member}  ← 타입 자체가 없다", line.strip()))
                    continue
                if member in SKIP or member in declared[typ]:
                    continue
                missing[typ].append((str(f.relative_to(root)), n, member, line.strip()))

    total = 0
    for typ in sorted(missing):
        print(f"\n{typ} 에 없는 멤버:")
        for path, n, member, text in missing[typ]:
            total += 1
            print(f"  {path}:{n}  .{member}")
            print(f"      {text[:110]}")

    static_bad = static_scope_errors(root)
    for path, n, fname, name, text in static_bad:
        print(f"\nstatic func {fname} 안에서 인스턴스 `{name}` 를 참조:")
        print(f"  {path}:{n}")
        print(f"      {text[:110]}")
    total += len(static_bad)

    opt_bad = optional_on_nonoptional_errors(root)
    for path, n, var, dname, text in opt_bad:
        print(f"\n사전 `{dname}` 의 값 `{var}` 는 옵셔널이 아닌데 옵셔널로 다룬다:")
        print(f"  {path}:{n}")
        print(f"      {text[:110]}")
    total += len(opt_bad)

    switch_bad = switch_case_errors(root, declared, cases)
    if switch_bad:
        print("\n없는 case 를 쓰는 switch:")
        for path, n, typ, msg, text in switch_bad:
            total += 1
            print(f"  {path}:{n}  {msg}")
            print(f"      {text[:110]}")

    known = sum(len(v) for v in declared.values())
    print(f"\n감시 타입 {len(declared)}개 · 선언 {known}개 · 의심 {total}건")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
