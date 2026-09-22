#!/bin/bash
#
# 앱이 왜 꺼지는지 한 번에 모아 본다.
#
#   ./diagnose.sh
#
# 제일 먼저 가르는 것: **정말 죽었나, 아니면 살아 있는데 아이콘만 안 보이나.**
# 메뉴바가 꽉 차면(특히 노치 있는 맥북) macOS 가 오른쪽 항목부터 조용히 숨긴다.
# 그러면 앱은 멀쩡히 돌고 있는데 사용자 눈에는 "꺼졌다"로 보인다.

APP_NAME="TokenPlant"
APP="/Applications/$APP_NAME.app"

echo "════════ 1. 지금 살아 있나 ════════"
if pgrep -x "$APP_NAME" > /dev/null; then
  PID="$(pgrep -x "$APP_NAME" | head -1)"
  echo "  살아 있음 (pid $PID)"
  # 언제부터 떠 있었나 — 방금 재시작됐다면 크래시 후 되살아난 것이다.
  ps -p "$PID" -o lstart=,etime= 2>/dev/null | sed 's/^/  시작: /'
  echo
  echo "  → 프로세스는 도는데 안 보인다면 앱이 꺼진 게 아니라"
  echo "    메뉴바가 꽉 차서 macOS 가 아이콘을 숨긴 것입니다."
  echo "    확인: 메뉴바 항목을 몇 개 줄이거나(Command 누른 채 드래그해서 왼쪽으로),"
  echo "    노치 있는 모델이면 Bartender/Ice 같은 도구가 필요할 수 있습니다."
else
  echo "  안 돌고 있음 — 진짜로 꺼졌습니다."
fi

echo
echo "════════ 2. 크래시 리포트 ════════"
CRASH_DIR="$HOME/Library/Logs/DiagnosticReports"
LATEST="$(ls -t "$CRASH_DIR"/$APP_NAME*.ips 2>/dev/null | head -1)"
if [[ -n "$LATEST" ]]; then
  echo "  파일: $LATEST"
  echo "  시각: $(stat -f '%Sm' "$LATEST" 2>/dev/null)"
  echo "  ── 원인 ──"
  # .ips 는 첫 줄이 JSON 헤더, 그 뒤가 본문 JSON 이다. 핵심만 뽑는다.
  python3 - "$LATEST" <<'PY' 2>/dev/null || sed -n '1,40p' "$LATEST"
import json, sys
raw = open(sys.argv[1], encoding="utf-8", errors="replace").read()
head, _, body = raw.partition("\n")
try:
    d = json.loads(body)
except Exception:
    print(raw[:2000]); raise SystemExit

ex = d.get("exception", {})
print(f"  종류   : {ex.get('type')} / {ex.get('signal')}")
if d.get("termination"):
    t = d["termination"]
    print(f"  종료   : {t.get('namespace')} code={t.get('code')} {t.get('indicator','')}")
    for r in t.get("details", [])[:3]:
        print(f"           {r}")
if d.get("asi"):
    for lib, msgs in d["asi"].items():
        for m in msgs[:3]:
            print(f"  메시지 : {m}")
# 죽은 스레드의 위쪽 프레임만 — TokenPlant 프레임이 어디서 터졌는지가 핵심이다.
imgs = d.get("usedImages", [])
faulting = next((t for t in d.get("threads", []) if t.get("triggered")), None)
if faulting:
    print("  ── 죽은 지점 (위에서부터) ──")
    for f in faulting.get("frames", [])[:12]:
        idx = f.get("imageIndex", -1)
        name = imgs[idx].get("name", "?") if 0 <= idx < len(imgs) else "?"
        print(f"           {name}  {f.get('symbol', hex(f.get('imageOffset', 0)))}")
PY
else
  echo "  크래시 리포트 없음."
  echo "  → 크래시가 아니라 스스로 종료했거나, 시스템이 조용히 죽였을 수 있습니다."
fi

echo
echo "════════ 3. 시스템이 죽였나 ════════"
# Gatekeeper·코드서명 위반으로 죽으면 크래시 리포트 대신 여기에 남는다.
log show --last 30m --style compact 2>/dev/null \
  | grep -i "$APP_NAME" \
  | grep -iE "kill|denied|invalid|taskgated|signature|quarantine|XPC|exited" \
  | tail -15 | sed 's/^/  /' \
  || echo "  (로그 조회 실패 — 권한이 없을 수 있습니다)"
[[ -z "$(log show --last 30m --style compact 2>/dev/null | grep -i "$APP_NAME" | grep -icE 'kill|denied|invalid')" ]] \
  && echo "  강제 종료 흔적 없음."

echo
echo "════════ 4. 서명 상태 ════════"
if [[ -d "$APP" ]]; then
  codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Signature|Identifier|Format|flags|TeamIdentifier" | sed 's/^/  /'
  echo "  ── 검증 ──"
  codesign --verify --deep --strict "$APP" 2>&1 | sed 's/^/  /' && echo "  서명 정상"
  echo "  ── 격리 속성 ──"
  xattr -l "$APP" 2>/dev/null | grep -i quarantine | sed 's/^/  /' || echo "  없음 (정상)"
else
  echo "  $APP 이 없습니다 — 설치가 안 됐습니다."
fi

echo
echo "════════ 5. 세이브 파일 ════════"
# 손상된 세이브로 시작하자마자 죽는 경우가 있다. 크기와 유효성만 본다.
SAVE="$HOME/Library/Application Support/TokenPlant/state.json"
if [[ -f "$SAVE" ]]; then
  echo "  $SAVE ($(stat -f '%z' "$SAVE") bytes)"
  python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
print('    JSON 정상')
pot=d.get('pot') or {}
print(f\"    화분: {pot.get('speciesID')} Lv.{(pot.get('stageIndex') or 0)+1} \"
      f\"물 {pot.get('water')} / 목표 {pot.get('cycleWater')}\")
print(f\"    지갑: {d.get('rawWallet')}  정원: {len(d.get('garden') or [])}그루\")
" "$SAVE" 2>&1 | sed 's/^/  /'
  echo
  echo "  세이브가 의심되면 옆으로 치워두고 새로 시작해 보세요(지우지 않습니다):"
  echo "      mv \"$SAVE\" \"$SAVE.bak\""
else
  echo "  세이브 없음 — 아직 한 번도 저장이 안 됐습니다."
fi

echo
echo "════════ 6. 터미널에서 직접 실행 ════════"
echo "  아래를 복사해서 실행하면 죽는 순간의 메시지가 그대로 보입니다."
echo "  (메뉴바에 뜬 뒤 꺼질 때까지 기다렸다가 Ctrl+C)"
echo
echo "      $APP/Contents/MacOS/$APP_NAME"
echo
