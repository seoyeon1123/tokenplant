#!/usr/bin/env python3
"""tree-sitter-swift 로 패키지 전체를 파싱한다.

Swift 컴파일러가 없는 환경에서 쓰는 1차 방어선이다. 타입 검사는 못 하지만
괄호·중괄호·문자열이 안 맞거나 리팩터 중 반쪽만 지운 선언은 여기서 잡힌다.

주의: 이 문법에 구멍이 셋 있다(유효한 Swift 인데 못 읽는다).
  - `if let x = try await f() { }`
  - `nonisolated(unsafe) var x`
  - `x as? T ?? 기본값`  (괄호를 치면 읽는다: `(x as? T) ?? 기본값`)
셋 다 소스에서 피해 뒀다 — 원본 PokeTokenBar 는 세 번째에 10군데가 걸린다.
여기서 ERROR 가 나면 진짜 오타로 보는 게 맞다.
"""
import sys
import pathlib
from tree_sitter import Language, Parser
import tree_sitter_swift

LANG = Language(tree_sitter_swift.language())
PARSER = Parser(LANG)


def errors(node, src, out, limit=6):
    if len(out) >= limit:
        return
    if node.type == "ERROR" or node.is_missing:
        line = node.start_point[0] + 1
        text = src.split(b"\n")[node.start_point[0]].decode("utf8", "replace").strip()
        out.append((line, "MISSING" if node.is_missing else "ERROR", text[:100]))
        return
    if node.has_error:
        for c in node.children:
            errors(c, src, out, limit)


def main(root):
    files = sorted(pathlib.Path(root).rglob("*.swift"))
    if not files:
        print("swift 파일이 없다", file=sys.stderr)
        return 1
    bad = 0
    for f in files:
        src = f.read_bytes()
        tree = PARSER.parse(src)
        if not tree.root_node.has_error:
            continue
        found = []
        errors(tree.root_node, src, found)
        if not found:
            continue
        bad += 1
        print(f"\n{f.relative_to(root)}")
        for line, kind, text in found:
            print(f"  {line:>4}  {kind}  {text}")
    print(f"\n{len(files)}개 파일 · 문제 {bad}개")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "."))
