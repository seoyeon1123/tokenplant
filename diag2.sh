#!/bin/bash
# 앱의 리더와 **같은 규칙**으로 직접 센다 — 앱이 못 읽는지, 읽을 게 없는지를 가른다.
python3 - <<'EOF'
import json, os, pathlib, datetime, collections
root = pathlib.Path.home() / ".claude/projects"
print("루트:", root, "존재:", root.is_dir())
today = datetime.date.today().isoformat()

def find_usage(o):
    if isinstance(o, dict):
        if "input_tokens" in o or "output_tokens" in o:
            return (int(o.get("input_tokens") or 0), int(o.get("output_tokens") or 0),
                    int(o.get("cache_creation_input_tokens") or 0),
                    int(o.get("cache_read_input_tokens") or 0))
        for v in o.values():
            r = find_usage(v)
            if r: return r
    elif isinstance(o, list):
        for v in o:
            r = find_usage(v)
            if r: return r
    return None

files = list(root.rglob("*.jsonl")) if root.is_dir() else []
todays = [f for f in files
          if datetime.date.fromtimestamp(f.stat().st_mtime).isoformat() == today]
print(f"전체 jsonl {len(files)}개 · 오늘 수정된 것 {len(todays)}개\n")

per_day = collections.Counter()
lines_seen = usage_seen = 0
for f in todays:
    try: text = f.read_text(errors="replace")
    except Exception as e:
        print("  못 읽음:", f, e); continue
    for line in text.splitlines():
        line = line.strip()
        if not line: continue
        lines_seen += 1
        try: obj = json.loads(line)
        except Exception: continue
        ts = obj.get("timestamp") or ""
        u = find_usage(obj)
        if not u: continue
        usage_seen += 1
        day = ts[:10] if len(ts) >= 10 else "?"
        per_day[day] += sum(u)

print(f"오늘 파일 안의 줄 {lines_seen:,}개 · usage 가 붙은 줄 {usage_seen:,}개")
print("타임스탬프 날짜별 합계:")
for d, v in sorted(per_day.items()):
    mark = "  ← 오늘" if d == today else ""
    print(f"   {d}  {v:,}{mark}")
if not per_day:
    print("   (없음)")
print()
print("오늘 수정된 파일 5개:")
for f in sorted(todays, key=lambda x: -x.stat().st_mtime)[:5]:
    t = datetime.datetime.fromtimestamp(f.stat().st_mtime).strftime("%H:%M")
    print(f"   {t}  {f.stat().st_size:>9,}B  {f.name}")
EOF
