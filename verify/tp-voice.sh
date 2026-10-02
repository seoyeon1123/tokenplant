#!/bin/bash
# TokenPlant 쇼츠 나레이션 — macOS 내장 음성으로 굽는다.
#
#   bash ~/Downloads/tp-voice.sh          # 한국어 음성 자동 선택
#   bash ~/Downloads/tp-voice.sh Yuna     # 음성 지정
#   say -v '?' | grep ko_KR               # 쓸 수 있는 한국어 음성 보기
#
# 결과: ~/Downloads/tp-voice/01.aiff … 12.aiff
# 음성 이름에 공백이 있을 수 있어서(예: "Eddy (한국어(대한민국))") awk $1 로 자르면 깨진다.

set -e
OUT="$HOME/Downloads/tp-voice"
RATE="${RATE:-190}"
mkdir -p "$OUT"
rm -f "$OUT"/*.aiff

# 깔려 있는 한국어 음성을 전부 보여준다 — 고를 수 있다는 걸 알아야 고른다.
LIST=$(say -v '?' | sed -n 's/^\(.*[^ ]\)  *ko_KR .*/\1/p')
echo "이 맥에 깔린 한국어 음성:"
echo "$LIST" | sed 's/^/  /'
echo

VOICE="$1"
if [ -z "$VOICE" ]; then
  # 기본(compact) 음성은 로봇처럼 들린다. Premium > Enhanced > 나머지 순으로 고른다.
  # 둘 다 없으면 시스템 설정에서 받아야 한다 — 이게 말투 차이의 거의 전부다.
  VOICE=$(echo "$LIST" | grep -i "premium" | head -1)
  [ -z "$VOICE" ] && VOICE=$(echo "$LIST" | grep -i "enhanced" | head -1)
  [ -z "$VOICE" ] && VOICE=$(echo "$LIST" | head -1)
fi
case "$VOICE" in
  *Premium*|*Enhanced*) ;;
  *) echo "⚠ 기본(compact) 음성입니다 — 로봇처럼 들립니다."
     echo "  시스템 설정 → 손쉬운 사용 → 말하기 → 시스템 음성 → 사용자화 에서"
     echo "  한국어의 '고음질/Premium' 을 받으면 훨씬 자연스러워집니다."
     echo ;;
esac
if [ -z "$VOICE" ]; then
  echo "한국어 음성이 안 깔려 있습니다."
  echo "  시스템 설정 → 손쉬운 사용 → 말하기 → 시스템 음성 → 사용자화 에서 한국어 음성을 받아주세요."
  exit 1
fi
echo "음성: $VOICE   속도: $RATE"

i=0
speak() {
  i=$((i + 1))
  printf -v n "%02d" "$i"
  say -v "$VOICE" -r "$RATE" -o "$OUT/$n.aiff" "$1"
  echo "  $n  $1"
}

speak "터미널에서 쓴 토큰이 그대로 물이 됩니다"
speak "따로 켤 것도, 누를 것도 없어요"
speak "씨앗에서 거목까지 열 단계"
speak "메뉴바에 띄워두면 알아서 크고 있습니다"
speak "화분에는 곧바로 새 씨앗이"
speak "그루가 늘수록 정원이 넓어지고"
speak "비밀의 숲까지 모두 일곱 단계"
speak "상점에서 장식을 사서 정원에 놓으면"
speak "바람개비가 돌고, 고양이가 꼬리를 흔들고"
speak "모이통 앞엔 새가 내려앉습니다"
speak "한 줄이면 설치됩니다"
speak "무료 오픈소스, 깃허브에 있어요"

echo
echo "완료 → $OUT"
echo "마음에 안 들면 다른 음성으로:  bash ~/Downloads/tp-voice.sh '다른이름'"
echo "더 천천히:                      RATE=165 bash ~/Downloads/tp-voice.sh"
