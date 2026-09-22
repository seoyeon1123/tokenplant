#!/bin/bash
#
# TokenPlant.app 을 만든다. macOS 에서 한 번만 돌리면 된다.
#
#   ./build-app.sh              릴리스 빌드 → dist/TokenPlant.app
#   ./build-app.sh --install    거기에 더해 /Applications 로 옮기고 실행
#   ./build-app.sh --zip        배포용 zip 도 만든다
#
# 왜 스크립트인가: SwiftPM 은 실행 파일만 뱉는다(`.build/release/TokenPlant`).
# 메뉴바 앱이 되려면 Info.plist 와 아이콘이 든 번들 구조가 필요하고, 그걸 여기서 조립한다.

set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="TokenPlant"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUM="$(date +%Y%m%d%H%M)"
DIST="dist"
APP="$DIST/$APP_NAME.app"

INSTALL=0
MAKE_ZIP=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --zip)     MAKE_ZIP=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "모르는 옵션: $arg" >&2; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "macOS 에서만 됩니다 (지금: $(uname -s))." >&2
  exit 1
fi

command -v swift >/dev/null || { echo "swift 가 없습니다. Xcode 또는 Command Line Tools 를 설치하세요." >&2; exit 1; }

# ── 0. 툴체인 점검 ──────────────────────────────────────────────
# 라이선스 미동의를 빌드 실패로 오해하면 안 된다. 그냥 두면 swift 가 라이선스 전문을
# 통째로 뱉고 입력을 기다리는데, 그게 빌드 에러처럼 보여서 엉뚱한 데를 고치게 된다.
# `< /dev/null` 이 없으면 라이선스 프롬프트("Press enter…")에서 그냥 멈춰 선다.
PROBE="$(swift --version 2>&1 < /dev/null || true)"
if grep -q "agreed to the Xcode" <<< "$PROBE"; then
  cat >&2 <<'MSG'
Xcode 라이선스에 아직 동의하지 않았습니다. 한 번만 하면 됩니다:

    sudo xcodebuild -license accept

그 다음 이 스크립트를 다시 실행하세요.
MSG
  exit 1
fi
if grep -qi "unable to find utility\|no developer tools\|xcode-select" <<< "$PROBE"; then
  cat >&2 <<'MSG'
Swift 툴체인을 찾지 못했습니다. 둘 중 하나가 필요합니다:

    xcode-select --install                                   # Command Line Tools
    sudo xcode-select -s /Applications/Xcode.app             # Xcode 가 이미 있다면

MSG
  exit 1
fi

echo "▸ $APP_NAME $VERSION 빌드 ($BUILD_NUM)"

# ── 1. 릴리스 빌드 ──────────────────────────────────────────────
# Apple Silicon 과 Intel 둘 다 담는다. 한쪽만 담으면 받은 사람이 Rosetta 없이는 못 연다.
#
# 빈 배열을 `set -u` 아래서 펼치면 macOS 기본 bash 3.2 는 unbound variable 로 죽는다.
# 그래서 배열 대신 문자열로 두고 일부러 단어 분리시킨다(플래그에 공백이 없어 안전하다).
ARCH_ARGS="--arch arm64 --arch x86_64"

# `mktemp -t 접두사` 는 BSD(macOS)와 GNU 가 문법이 다르다. XXXXXX 를 직접 주면 양쪽 다 된다.
BUILD_LOG="$(mktemp "${TMPDIR:-/tmp}/tokenplant-build.XXXXXX")"
trap 'rm -f "$BUILD_LOG"' EXIT

if ! swift build -c release $ARCH_ARGS > "$BUILD_LOG" 2>&1 < /dev/null; then
  # 실패 이유를 정규식으로 알아맞히려 들지 않는다 — "Search.swift ... not found" 같은
  # 진짜 컴파일 에러가 arch 문제로 오인돼서 엉뚱한 재시도를 한다.
  # 대신 한 줄만 보여주고 이 기계 아키텍처로 다시 해본다. 그래도 실패하면
  # **그때의** 로그를 통째로 보여준다 — 그게 사용자가 고쳐야 할 진짜 에러다.
  echo "  universal 빌드 실패 — 이 기계 아키텍처로만 다시 시도합니다"
  grep -m1 "error:" "$BUILD_LOG" | sed 's/^/    /' || true
  ARCH_ARGS=""
  if ! swift build -c release > "$BUILD_LOG" 2>&1 < /dev/null; then
    echo "▸ 빌드 실패:" >&2
    cat "$BUILD_LOG" >&2
    exit 1
  fi
fi

BIN="$(swift build -c release $ARCH_ARGS --show-bin-path < /dev/null)/$APP_NAME"
[[ -f "$BIN" ]] || { echo "실행 파일이 없습니다: $BIN" >&2; exit 1; }

# ── 2. 번들 조립 ────────────────────────────────────────────────
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

# 아이콘은 스프라이트에서 만든다 — 손으로 그린 PNG 를 따로 두면 금방 어긋난다.
if [[ ! -f Resources/AppIcon.icns ]] && command -v python3 >/dev/null; then
  python3 verify/make_icon.py || true
fi
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUM/" \
    Resources/Info.plist > "$APP/Contents/Info.plist"

printf 'APPL????' > "$APP/Contents/PkgInfo"

# ── 3. 서명 ─────────────────────────────────────────────────────
# ad-hoc(`-`) 서명이다. 이 기계에서 쓰기엔 충분하지만 남에게 보내면 Gatekeeper 가 막는다.
# 받는 사람이 경고 없이 열게 하려면 Apple Developer Program($99/년)의
# Developer ID 서명 + 공증(notarization)이 필요하다.
#
# `--options runtime`(하드닝)은 **일부러 뺐다.** 공증할 때나 의미가 있는데,
# ad-hoc 서명과 묶이면 라이브러리 검증에 걸려 앱이 조용히 죽는 일이 있다.
# 공증을 붙일 때 같이 켜는 게 맞다.
codesign --force --deep --sign - "$APP"

codesign --verify --deep --strict "$APP" && echo "▸ 서명 확인됨 (ad-hoc)"

SIZE="$(du -sh "$APP" | cut -f1)"
echo "▸ 완성: $APP ($SIZE)"

# ── 4. 선택 동작 ────────────────────────────────────────────────
if [[ $MAKE_ZIP -eq 1 ]]; then
  ZIP="$DIST/$APP_NAME-$VERSION.zip"
  rm -f "$ZIP"      # zip 은 기존 아카이브에 **덧붙인다** — 지우지 않으면 옛 파일이 섞인다
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "▸ 배포용: $ZIP"
fi

if [[ $INSTALL -eq 1 ]]; then
  pkill -x "$APP_NAME" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  echo "▸ /Applications/$APP_NAME.app 에 설치됨"
  open "/Applications/$APP_NAME.app"
  echo "▸ 실행했습니다. 메뉴바 오른쪽을 보세요."
else
  echo
  echo "  설치:  ./build-app.sh --install"
  echo "  또는:  open $DIST  → TokenPlant.app 을 응용 프로그램으로 끌어다 놓기"
fi
