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


def _strip_comments(line):
    """줄 주석을 뗀다. 문자열 안의 `//` 는 남긴다(따옴표 개수로 대충 판단)."""
    out, i, in_str = [], 0, False
    while i < len(line):
        c = line[i]
        if c == '"' and (i == 0 or line[i - 1] != "\\"):
            in_str = not in_str
        if not in_str and c == "/" and i + 1 < len(line) and line[i + 1] == "/":
            break
        out.append(c)
        i += 1
    return "".join(out)


def _split_top_level(text):
    """괄호·대괄호 깊이를 보며 최상위 쉼표로 자른다."""
    parts, depth, cur, in_str = [], 0, [], False
    for i, c in enumerate(text):
        if c == '"' and (i == 0 or text[i - 1] != "\\"):
            in_str = not in_str
        if not in_str:
            if c in "([{":
                depth += 1
            elif c in ")]}":
                depth -= 1
            elif c == "," and depth == 0:
                parts.append("".join(cur)); cur = []; continue
        cur.append(c)
    if "".join(cur).strip():
        parts.append("".join(cur))
    return [p.strip() for p in parts]


PARAM_LABEL = re.compile(r"^(?:(_|[A-Za-z_]\w*)\s+)?([A-Za-z_]\w*)\s*:")
ARG_LABEL = re.compile(r"^([A-Za-z_]\w*)\s*:(?!:)")
FUNC_SIG = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
                      r"(?:public\s+|internal\s+|private(?:\(set\))?\s+|fileprivate\s+|"
                      r"static\s+|class\s+|final\s+|@discardableResult\s+|"
                      r"nonisolated(?:\(unsafe\))?\s+|mutating\s+)*"
                      r"func\s+([A-Za-z_]\w*)\s*(?:<[^>]*>)?\s*\(")


def _balanced(text, open_idx):
    """`text[open_idx]` 의 여는 괄호에 맞는 닫는 괄호 위치. 못 찾으면 None."""
    depth, i, in_str = 0, open_idx, False
    while i < len(text):
        c = text[i]
        if c == '"' and (i == 0 or text[i - 1] != "\\"):
            in_str = not in_str
        if not in_str:
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    return None


def collect_signatures(root):
    """감시 타입의 `func` 시그니처 → {(타입, 함수명): [ [(레이블, 기본값있음)], ... ]}"""
    sigs = defaultdict(list)
    for f in sorted(pathlib.Path(root).rglob("*.swift")):
        blocks, lines = type_blocks(str(f))
        code = [_strip_comments(l) for l in lines]
        for name, lo, hi in blocks:
            if name not in WATCHED:
                continue
            for i in range(lo, min(hi + 1, len(code))):
                m = FUNC_SIG.match(code[i])
                if not m:
                    continue
                # 시그니처가 여러 줄에 걸칠 수 있다 — 괄호가 닫힐 때까지 이어 붙인다.
                joined = "\n".join(code[i:min(i + 12, len(code))])
                start = joined.index("(", m.end() - 1) if "(" in joined[m.end() - 1:] else m.end() - 1
                close = _balanced(joined, m.end() - 1)
                if close is None:
                    continue
                params = _split_top_level(joined[m.end():close])
                labels = []
                for p in params:
                    pm = PARAM_LABEL.match(p)
                    if not pm:
                        continue
                    ext = pm.group(1) if pm.group(1) else pm.group(2)
                    labels.append(("" if ext == "_" else ext, "=" in p.split(":", 1)[-1]))
                sigs[(name, m.group(1))].append(labels)
    return sigs


def argument_label_errors(root, sigs):
    """호출부의 인자 레이블이 어느 오버로드와도 안 맞는 곳을 찾는다.

    **실제로 맥에서 `swift test` 가 이걸로 터졌다.** `PotSprites.grid` 에 `motif:` 가
    추가됐는데 테스트 5곳이 옛 호출 그대로였다. 이 검사기는 "멤버가 있는가"만 봤고
    이름은 멀쩡했으므로 통과했다 — 컴파일러가 있는 데서 빌드할 때까지 아무도 몰랐다.

    기본값이 있는 인자는 빠져도 되고, 없는 인자는 반드시 있어야 한다.
    """
    call = re.compile(r"\b(" + "|".join(sorted(WATCHED)) + r")\.([A-Za-z_]\w*)\s*\(")
    bad = []
    for f in sorted(pathlib.Path(root).rglob("*.swift")):
        lines = f.read_text(encoding="utf8").split("\n")
        text = "\n".join(_strip_comments(l) for l in lines)
        for m in call.finditer(text):
            typ, fname = m.group(1), m.group(2)
            overloads = sigs.get((typ, fname))
            if not overloads:
                continue                      # enum case·프로퍼티·모르는 것은 건드리지 않는다
            close = _balanced(text, m.end() - 1)
            if close is None:
                continue
            args = _split_top_level(text[m.end():close])
            used = []
            for a in args:
                am = ARG_LABEL.match(a)
                used.append(am.group(1) if am else "")
            ok = False
            for labels in overloads:
                required = [l for l, has_def in labels if not has_def]
                # 호출 레이블이 선언 레이블의 부분수열이고, 기본값 없는 건 다 있어야 한다.
                it = iter(labels)
                if all(any(l == u for l, _ in it) for u in used) and \
                   all(r in used for r in required) and len(used) <= len(labels):
                    ok = True
                    break
            if not ok:
                n = text.count("\n", 0, m.start()) + 1
                want = " / ".join("(" + ", ".join(l or "_" for l, _ in o) + ")"
                                  for o in overloads)
                bad.append((str(f.relative_to(root)), n, f"{typ}.{fname}",
                            "(" + ", ".join(u or "_" for u in used) + ")", want,
                            lines[n - 1].strip()))
    return bad


# 루트 변수와 `?.` 사이에 경로가 낄 수 있다 — `s.pot?.cycleWater` 가 바로 그 모양이다.
EXCLUSIVITY_LHS = re.compile(
    r"^\s*([a-z]\w*)((?:\.[A-Za-z_]\w*|[?!])+)\s*(?:\+|-|\*|/)?=(?!=)\s*(.+)$")


def exclusivity_errors(root):
    """`x?.y = f(x)` 처럼 우변에서 같은 루트를 읽는 옵셔널 체이닝 대입을 찾는다.

    **맥에서 `swift test` 가 이걸로 터졌다.**

        s.pot?.cycleWater = PlantEngine.seedCycle(s)
        // error: overlapping accesses to 's.pot',
        //        but modification requires exclusive access

    `s.pot?.x = ...` 는 `s.pot` 을 읽고-고치고-되쓴다. 그 **수정 접근이 우변을 계산하는
    내내 열려 있어서**, 우변이 같은 `s` 를 읽으면 접근이 겹친다.
    `save.dailyRaw = f(save.dailyRaw)` 처럼 직접 저장 프로퍼티에 대입하는 건 괜찮다 —
    우변을 다 계산한 뒤에 쓰기 접근이 시작되기 때문이다. 그래서 `?.`/`!.` 만 본다.

    고치는 법은 언제나 같다. 우변을 **지역 변수에 먼저 담는다.**
    tree-sitter 는 이 줄을 아무 문제 없이 파싱하므로 여기서 안 잡으면 맥에서만 안다.
    """
    bad = []
    for f in sorted(pathlib.Path(root).rglob("*.swift")):
        lines = f.read_text(encoding="utf8").split("\n")
        for n, line in enumerate(lines, 1):
            m = EXCLUSIVITY_LHS.match(_strip_comments(line))
            if not m:
                continue
            root_var, path, rhs = m.group(1), m.group(2), m.group(3)
            # 옵셔널 체이닝(또는 강제 언랩)을 거치는 대입만 본다.
            if "?." not in path and "!." not in path:
                continue
            # 문자열 리터럴 안의 이름은 세지 않는다.
            rhs_code = re.sub(r'"[^"]*"', '""', rhs)
            if re.search(rf"\b{re.escape(root_var)}\b", rhs_code):
                bad.append((str(f.relative_to(root)), n, root_var, line.strip()))
    return bad


# `count`·`joined` 처럼 체인을 **끝내는** 것도 센다 — 빠뜨렸다가 실제로 터진 줄을
# 2개로 세서 못 잡았다. 연쇄의 길이가 문제지 마지막 항이 무엇인지는 상관없다.
CHAIN_OPS = re.compile(r"\.(flatMap|compactMap|filter|map|reduce|sorted|"
                       r"first|allSatisfy|contains|prefix|suffix|drop\w*|"
                       r"count|joined|enumerated|reversed|split)\b")
LITERAL_EQ = re.compile(r"[=!]=\s*\"")


def slow_typecheck_errors(root):
    """한 줄에 연쇄 연산 3개 이상 + 문자열 리터럴 비교 2개 이상인 식을 찾는다.

    **맥에서 `swift test` 가 이걸로 터졌다.**

        grid.flatMap { $0 }.filter { $0 == "G" || $0 == "L" || $0 == "d" }.count
        // error: the compiler is unable to type-check this expression
        //        in reasonable time

    문법도 타입도 멀쩡하다. 문제는 `"G"` 같은 리터럴이 `Character`/`String`/
    `StringLiteralConvertible` 후보를 모두 열어 두는데, 그게 제네릭 체인마다 곱해져서
    탐색 공간이 터지는 것이다. 컴파일러는 "오래 걸린다"며 포기한다.

    고치는 법: 리터럴 집합에 **타입을 박아** 지역 변수로 빼고 체인을 쪼갠다.

        let leafChars: Set<Character> = ["G", "L", "d"]

    기준을 3·2 로 둔 이유는 이 저장소에서 실제로 터진 줄만 정확히 걸리고
    나머지는 하나도 안 걸리기 때문이다. 더 느슨하게 잡으면 멀쩡한 체인이 쏟아진다.
    """
    bad = []
    for f in sorted(pathlib.Path(root).rglob("*.swift")):
        for n, line in enumerate(f.read_text(encoding="utf8").split("\n"), 1):
            code = _strip_comments(line)
            if len(CHAIN_OPS.findall(code)) >= 3 and len(LITERAL_EQ.findall(code)) >= 2:
                bad.append((str(f.relative_to(root)), n, line.strip()))
    return bad



# ── 디코더가 모든 저장 프로퍼티를 채우는가 ─────────────────────
#
# 이 실수로 두 번 깨졌다. 저장 프로퍼티를 하나 추가하고 `init(from decoder:)` 에
# 한 줄 넣는 걸 빼먹으면 **"return from initializer without initializing all stored
# properties"** 로 빌드가 통째로 멈춘다. 스위프트 컴파일러가 없는 환경에서는
# 이 한 줄 때문에 왕복이 한 번 더 생긴다 — 그래서 여기서 먼저 잡는다.
#
# 기본값(`= ...`)이 있는 프로퍼티는 뺀다. 컴파일은 통과하기 때문이다.
# (그건 "조용히 기본값을 먹는" 다른 문제고, 여기서 섞으면 경고가 시끄러워진다.)
STORED = re.compile(
    r"^    (?:@\w+\s+)?(?:private\s+|fileprivate\s+|public\s+|internal\s+)?"
    r"(?:var|let)\s+(\w+)\s*:\s*[^={]+$")


def decoder_init_errors(root):
    out = []
    for f in sorted(pathlib.Path(root).rglob("*.swift")):
        lines = f.read_text(encoding="utf8").split("\n")
        for i, line in enumerate(lines):
            if "init(from decoder" not in line or line.lstrip().startswith("//"):
                continue

            # 이 init 을 감싼 타입 본문의 범위를 찾는다 — 바로 위로 올라가며
            # 들여쓰기 0칸의 타입 선언을 만나는 지점이 시작이다.
            start = None
            for j in range(i, -1, -1):
                if re.match(r"^(?:final\s+)?(?:struct|class|actor|enum)\s+\w+", lines[j]):
                    start = j
                    break
            if start is None:
                continue
            end = len(lines)
            for j in range(i + 1, len(lines)):
                if lines[j] == "}":
                    end = j
                    break

            props = []
            for j in range(start, end):
                code = _strip_comments(lines[j])
                if "static" in code.split(":")[0]:
                    continue
                m = STORED.match(code.rstrip())
                if m:
                    props.append((m.group(1), j + 1))

            # init 본문 — 여는 중괄호부터 균형이 맞을 때까지.
            depth, body, k = 0, [], i
            while k < end:
                depth += lines[k].count("{") - lines[k].count("}")
                body.append(lines[k])
                if depth <= 0 and "{" in "".join(body):
                    break
                k += 1
            text = "\n".join(body)

            for name, ln in props:
                if re.search(rf"(?:^|[^.\w]){re.escape(name)}\s*=[^=]", text):
                    continue
                out.append((str(f.relative_to(root)), ln, name, lines[ln - 1].strip()))
    return out

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

    sigs = collect_signatures(root)
    label_bad = argument_label_errors(root, sigs)
    for path, n, fn, got, want, text in label_bad:
        print(f"\n{fn} 호출의 인자 레이블이 선언과 안 맞는다:")
        print(f"  {path}:{n}  받은 것 {got}  ·  선언 {want}")
        print(f"      {text[:110]}")
    total += len(label_bad)

    excl_bad = exclusivity_errors(root)
    for path, n, var, text in excl_bad:
        print(f"\n`{var}?.…= ` 의 우변이 같은 `{var}` 를 읽는다 (배타적 접근 위반):")
        print(f"  {path}:{n}   → 우변을 지역 변수에 먼저 담을 것")
        print(f"      {text[:110]}")
    total += len(excl_bad)

    slow_bad = slow_typecheck_errors(root)
    for path, n, text in slow_bad:
        print(f"\n타입 체커가 포기할 만한 식 (연쇄 + 리터럴 비교가 겹쳤다):")
        print(f"  {path}:{n}   → 리터럴 집합에 타입을 박아 지역 변수로 뺄 것")
        print(f"      {text[:110]}")
    total += len(slow_bad)

    dec_bad = decoder_init_errors(root)
    for path, n, name, text in dec_bad:
        print(f"\n`init(from decoder:)` 가 저장 프로퍼티 `{name}` 를 안 채운다:")
        print(f"  {path}:{n}   → 디코더에 한 줄 추가할 것 (기본값을 주는 것도 방법)")
        print(f"      {text[:110]}")
    total += len(dec_bad)

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
