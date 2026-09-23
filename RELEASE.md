# 릴리스 절차

버전을 올릴 때마다 이 순서대로.

## 1. 버전 올리기

```bash
echo "0.2.0" > VERSION
```

## 2. 검증

```bash
swift test
python3 verify/check_data.py
python3 verify/run_tests.py
```

`check_syntax.py` · `check_members.py` 는 `tree_sitter` 가 있어야 돈다.
둘은 **Swift 컴파일러가 없는 환경**(클라우드 컨테이너)용이라, 맥에서는 `swift test` 가
같은 일을 이미 한다. 맥에서도 돌리고 싶으면:

```bash
pip3 install tree_sitter tree_sitter_swift
```

## 3. 빌드 · 체크섬

```bash
./build-app.sh --zip
shasum -a 256 dist/TokenPlant-$(cat VERSION).zip
```

## 4. 태그 · 릴리스

```bash
V=$(cat VERSION)
git add -A && git commit -m "v$V"
git tag "v$V" && git push origin main --tags

gh release create "v$V" "dist/TokenPlant-$V.zip" \
  --title "v$V" --notes "변경 사항을 여기에"
```

## 5. cask 갱신

`homebrew-tap` 저장소의 `Casks/tokenplant.rb` 에서 두 줄을 바꾼다.

```ruby
version "0.2.0"
sha256 "3단계에서 나온 값"
```

```bash
cd ../homebrew-tap
git add -A && git commit -m "tokenplant 0.2.0" && git push
```

## 6. 확인

```bash
brew update
brew upgrade --cask tokenplant
```

---

**주의 — zip 은 덧붙인다.** `build-app.sh --zip` 은 기존 아카이브를 먼저 지우지만,
손으로 zip 을 만들 때는 반드시 `rm -f` 를 먼저 해야 한다. 안 그러면 옛 파일이 섞여 나간다.

**주의 — ad-hoc 서명은 빌드마다 신원이 바뀐다.** 새 버전을 깔면 한도 조회용 키체인
접근 허용을 다시 물어본다. 릴리스 노트에 한 줄 적어두면 문의가 줄어든다.
