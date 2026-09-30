#!/bin/bash
S="$HOME/Library/Application Support/TokenPlant/state.json"
echo "=== 앱 실행 중인가"
pgrep -x TokenPlant >/dev/null && echo "  실행 중 (pid $(pgrep -x TokenPlant))" || echo "  안 돌고 있음"
echo "=== 세이브 파일"
ls -l "$S" 2>/dev/null || echo "  없음!"
echo "=== 세이브 내용"
python3 - "$S" <<'EOF'
import json, sys, datetime
d = json.load(open(sys.argv[1]))
p = d.get("pot") or {}
print(f"  lastDate            {d.get('lastDate')!r}")
print(f"  installBaselineSet  {d.get('installBaselineSet')}")
print(f"  rawSinceInstall     {d.get('rawSinceInstall',0):,}")
print(f"  waterSinceInstall   {d.get('waterSinceInstall',0):,}")
print(f"  rawWallet           {d.get('rawWallet',0):,}")
print(f"  pot.water           {p.get('water',0):,}")
print(f"  pot.cycleWater      {p.get('cycleWater',0):,}")
print(f"  pot.stageIndex      {p.get('stageIndex')}")
print(f"  claimedToday        {json.dumps(d.get('claimedTodayByProvider'), ensure_ascii=False)}")
dr = d.get("dailyRaw") or {}
print(f"  dailyRaw ({len(dr)}일):")
for k in sorted(dr)[-8:]:
    print(f"      {k}  {dr[k]:,}")
EOF
echo "=== 오늘 로그에서 읽히는 사용량"
TODAY=$(date +%Y-%m-%d)
echo "  오늘=$TODAY"
for root in "$HOME/.claude/projects" "$HOME/.codex/sessions"; do
  if [ -d "$root" ]; then
    n=$(find "$root" -name '*.jsonl' -newermt "$TODAY" 2>/dev/null | wc -l | tr -d ' ')
    echo "  $root : 오늘 수정된 jsonl $n 개"
  else
    echo "  $root : 폴더 없음"
  fi
done
