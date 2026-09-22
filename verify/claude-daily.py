#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Claude Code 로그를 **날짜별로** 물(mL)로 환산해 분포를 본다.

전에 돌린 claude-water.py 는 합계만 봤다. 그게 문제였다 —
달력일 평균 하나로 임계값을 잡았더니 무거운 날에 두 배로 자란다.
중위값·상하위를 보고 다시 잡아야 한다.

    python3 ~/Downloads/claude-daily.py
"""

import json
import os
import pathlib
import statistics
from collections import defaultdict
from datetime import datetime, timezone

W_OUT, W_IN, W_CW, W_CR = 500, 100, 125, 10   # ×100 스케일
ROOT = pathlib.Path(os.environ["HOME"]) / ".claude" / "projects"


def find_usage(o):
    if isinstance(o, dict):
        if "input_tokens" in o or "output_tokens" in o:
            return o
        for v in o.values():
            r = find_usage(v)
            if r:
                return r
    elif isinstance(o, list):
        for v in o:
            r = find_usage(v)
            if r:
                return r
    return None


def main():
    if not ROOT.exists():
        print(f"{ROOT} 가 없습니다.")
        return

    daily = defaultdict(lambda: [0, 0, 0, 0])   # in, out, cw, cr
    seen = set()
    files = 0

    for p in ROOT.rglob("*.jsonl"):
        files += 1
        try:
            with p.open(encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    if len(line) < 3:
                        continue
                    try:
                        o = json.loads(line)
                    except Exception:
                        continue
                    ts = o.get("timestamp")
                    if not isinstance(ts, str):
                        continue
                    key = (o.get("requestId")
                           or (o.get("message") or {}).get("id")
                           or o.get("uuid"))
                    if key:
                        if key in seen:
                            continue
                        seen.add(key)
                    u = find_usage(o)
                    if not u:
                        continue
                    # UTC 타임스탬프 → 로컬 날짜
                    try:
                        d = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone()
                    except Exception:
                        continue
                    day = d.strftime("%Y-%m-%d")
                    row = daily[day]
                    row[0] += u.get("input_tokens", 0) or 0
                    row[1] += u.get("output_tokens", 0) or 0
                    row[2] += u.get("cache_creation_input_tokens", 0) or 0
                    row[3] += u.get("cache_read_input_tokens", 0) or 0
        except Exception:
            continue

    if not daily:
        print("읽은 게 없습니다.")
        return

    rows = []
    for day in sorted(daily):
        i, o, cw, cr = daily[day]
        mL = (o * W_OUT + i * W_IN + cw * W_CW + cr * W_CR) // 100_000
        rows.append((day, i + o + cw + cr, mL))

    print(f"파일 {files}개 · 중복 제거 후 {len(seen)}건 · 활동일 {len(rows)}일")
    print(f"{rows[0][0]} ~ {rows[-1][0]}\n")
    print(f"{'날짜':<12}{'원시':>14}{'물(mL)':>10}")
    for day, raw, mL in rows:
        bar = "█" * min(40, mL // 1500)
        print(f"{day:<12}{raw:>14,}{mL:>10,}  {bar}")

    vals = sorted(mL for _, _, mL in rows)
    span = (datetime.strptime(rows[-1][0], "%Y-%m-%d")
            - datetime.strptime(rows[0][0], "%Y-%m-%d")).days + 1
    total = sum(vals)
    print(f"\n총 물        {total:,} mL")
    print(f"달력일 평균  {total // span:,} mL/일   (기간 {span}일)")
    print(f"활동일 평균  {total // len(vals):,} mL/일  (활동 {len(vals)}일)")
    print(f"활동일 중위  {int(statistics.median(vals)):,} mL/일")
    if len(vals) >= 4:
        q = statistics.quantiles(vals, n=4)
        print(f"하위25% {int(q[0]):,} / 상위25% {int(q[2]):,} mL/일")
    print(f"최소 {vals[0]:,} / 최대 {vals[-1]:,} mL/일")

    print("\n--- 이 값으로 만렙(375,000mL)까지 며칠 ---")
    for label, v in [("중위 페이스", statistics.median(vals)),
                     ("활동일 평균", total / len(vals)),
                     ("달력일 평균", total / span),
                     ("최대 페이스", vals[-1])]:
        if v > 0:
            print(f"{label:<12}{375_000 / v:6.1f}일")


if __name__ == "__main__":
    main()
