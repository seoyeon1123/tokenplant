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

## 3. 커밋 · 태그 **먼저**

빌드보다 먼저 한다. 순서가 뒤집히면 태그가 실제로 배포된 소스보다 뒤처진다
(v0.2.3 에서 실제로 그렇게 됐다 — 릴리스 zip 은 맞는데 태그는 한 커밋 전을 가리켰다).

```bash
V=$(cat VERSION)
git add -A && git commit -m "v$V — 무엇을 왜"
git tag "v$V" && git push origin main && git push origin "v$V"
```

## 4. 빌드 · 서명된 appcast

```bash
V=$(cat VERSION)
rm -f "dist/TokenPlant-$V.zip"
./build-app.sh --zip
shasum -a 256 "dist/TokenPlant-$V.zip"        # cask 에 넣을 값

# zip 에 EdDSA 서명을 하고 appcast.xml 을 갱신한다.
# 비밀키는 로그인 키체인에 있다 — 여기서 꺼내 쓰고 파일로는 안 남는다.
#
# **`dist/appcast/` 에 이번 zip 하나만 둔다.** generate_appcast 는 준 폴더의 아카이브를
# 전부 훑어서 항목을 만드는데, dist/ 를 통째로 주면 옛 버전 zip 까지 appcast 에 들어간다.
# `rm -f dist/appcast/*.zip` 로 쓰면 zsh 에서 깨진다 — 매칭이 없으면
# "no matches found" 로 **줄 전체를 죽여서** 뒤의 cp 가 안 돈다(bash 와 다르다).
rm -rf dist/appcast && mkdir -p dist/appcast
cp "dist/TokenPlant-$V.zip" dist/appcast/
"$(find .build -name generate_appcast -type f | head -1)" \
  --download-url-prefix "https://github.com/seoyeon1123/tokenplant/releases/download/v$V/" \
  -o appcast.xml dist/appcast/
```

`appcast.xml` 이 바뀌었으면 커밋해서 올린다 — **사용자 앱이 보는 파일이 이거다.**

```bash
git add appcast.xml && git commit -m "appcast $V" && git push
```

## 5. 릴리스 · cask

```bash
V=$(cat VERSION)
gh release create "v$V" "dist/TokenPlant-$V.zip" --title "v$V" --notes "변경 사항"
```

`homebrew-tap` 의 `Casks/tokenplant.rb` 에서 `version` 과 `sha256`(4단계 값)을 바꾼다.
**`auto_updates true` 가 있어야 한다** — 없으면 brew 와 Sparkle 이 같은 앱을 서로 관리한다.

```bash
cd ../homebrew-tap
git add -A && git commit -m "tokenplant $(cat ../TokenPlant-core/VERSION)" && git push
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

## 자동 업데이트 (Sparkle)

앱이 하루 한 번 `appcast.xml` 을 보고, 새 버전이 있으면 받아서 깐다.
Apple Developer ID 는 없다 — Sparkle 2 는 코드 서명이 안 맞아도 **EdDSA 서명이 맞으면**
업데이트를 받아들인다. 그래서 ad-hoc 서명으로도 된다.

### 키 만들기 (한 번만)

```bash
"$(find .build -name generate_keys -type f | head -1)"
```

비밀키는 **로그인 키체인**에 들어가고 공개키가 화면에 찍힌다. 그 공개키를 저장소에 둔다:

```bash
echo "찍힌_공개키" > sparkle-key.pub
git add sparkle-key.pub && git commit -m "Sparkle 공개키"
```

### 백업 — 이게 제일 중요하다

**비밀키를 잃어버리면 그 뒤로 아무도 업데이트를 못 받는다.** 새 키로 바꾸면 기존
사용자는 전원이 수동 재설치를 해야 한다. 맥을 새로 사거나 키체인을 날리면 끝이다.

```bash
"$(find .build -name generate_keys -type f | head -1)" -x sparkle-key-backup.txt
```

이 파일을 **저장소 밖** 안전한 곳(비밀번호 관리자 등)에 두고, 로컬 파일은 지운다.
`.gitignore` 가 막고 있지만 실수로 커밋되면 남이 서명한 업데이트를 사용자에게 밀어넣을 수 있다.
