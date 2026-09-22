# PokeTokenBar → TokenPlant 포크 계획

`chattymin/PokeTokenBar` 는 **MIT** 다. 포크해서 고쳐 쓸 수 있고, 저작권 표시만 남기면 된다.

새로 만들지 말고 포크하는 게 맞다. 어려운 부분이 이미 다 돼 있다 —
11개 도구 로그 파서, 공식 한도 조회(Keychain·OAuth), 증분 캐싱, 메뉴바 렌더,
팝오버 셸, 다국어, 크래시 리포터, 릴리스 스크립트. 1MB 짜리 Swift 코드에
테스트 60여 개가 붙어 있다. 우리가 바꿀 건 **키우는 대상뿐**이다.

## 접점은 한 군데다

```
UsageStore  ──(오늘 사용량)──▶  CompanionStore.update(...)
                                      │
                                      ├─ applyUsage(delta: Int)   ← 성장 진입점
                                      └─ graduate() / hatch()
```

`applyUsage(_ delta: Int)` 하나가 성장의 전부다. 여길 갈면 나머지는 따라온다.

## 파일별 처분

### 그대로 둔다 (건드릴 이유 없음)

| 파일 | 왜 |
|---|---|
| `Core/LocalUsageReader.swift` (1,654줄) | Claude Code·Codex·Gemini·Cursor 등 로그 파서. **이게 포크하는 이유다** |
| `Core/LocalUsageProvider.swift`, `LocalUsageCache.swift` | 증분 스캔 + 캐싱 |
| `Core/UsageStore.swift` | 집계·주기 갱신 (한 곳만 추가 — 아래) |
| `Core/*RateLimitsProvider.swift`, `KeychainAccess.swift`, `OAuthLimitsProvider.swift` | 공식 한도 |
| `Core/ModelPricing.swift`, `TokenFormatter.swift` | 비용 계산·숫자 포맷 |
| `Core/AppEnv/AppLog/CrashReporter/SingleInstance/LoginItem/UpdateChecker` | 앱 인프라 |
| `Core/Localization.swift` | 다국어 (문자열만 교체) |
| `UI/PopoverView.swift` | 탭 셸·푸터 구조 유지, 내용만 교체 |
| `OutsideClickMonitor.swift`, `UI/FloatingPetPanel.swift` | 그대로 |
| `scripts/*` | build-app.sh · release.sh · test-gate.sh 전부 재사용 |

### 교체한다

| 지운다 | 대신 넣는다 |
|---|---|
| `Core/CompanionModel.swift` (637줄) | `Core/PlantModel.swift` + `Core/PlantBalance.swift` + `Core/PlantShop.swift` |
| `Core/CompanionStore.swift` (1,246줄) | `Core/PlantEngine.swift` (순수 로직) + 얇은 `Core/PlantStore.swift` (@MainActor 껍데기) |
| `UI/CompanionView.swift` (1,163줄) | `UI/PotView.swift` + `UI/GardenView.swift` |
| `UI/SpriteLoader.swift`, `UI/SpriteAnimation.swift` | `Core/PlantSprites.swift` + `UI/PixelSpriteView.swift` |
| `UI/ShopView.swift` | `UI/ShopView.swift` (품목만 교체 — 레이아웃 재사용) |
| `UI/BagView.swift` | `UI/BagView.swift` (같음) |

### 삭제한다

| 파일 | 왜 |
|---|---|
| `Core/PokeAPIClient.swift` | **네트워크가 아예 필요 없어진다.** 스프라이트·종 정보가 전부 로컬 픽셀맵이다. PokeTokenBar 는 오프라인이면 부화가 막히는데 우리는 안 막힌다 |
| `Core/NetworkReachabilityMonitor.swift` | 위와 같은 이유 (한도 조회만 쓰면 남겨도 됨) |
| `Tests/.../Ditto*·ShinyCharm*·RareCandy*·EvoLine*·FreshEgg*` | 포켓몬 전용 |

이건 순수한 이득이다 — 의존성이 줄고, 오프라인에서 동작하고, 부화가 즉시 끝난다.

## UsageStore 에 한 곳만 추가

`applyUsage` 는 총합 `Int` 만 받는데, 가중 환산에는 **4종 분해**가 필요하다.
`UsageStore` 내부에는 이미 `dailyByID: [String: DailyUsage]` 가 있으니
계산 프로퍼티 하나만 노출하면 된다:

```swift
// UsageStore.swift — todayTokensByProvider(현재 225행) 옆에 추가
var todayUsageByProvider: [String: TokenDelta] {
    dailyByID.mapValues {
        TokenDelta(input: $0.inputTokens, output: $0.outputTokens,
                   cacheWrite: $0.cacheCreationTokens, cacheRead: $0.cacheReadTokens)
    }
}
```

그리고 `PokeTokenBarApp.swift:227` 의 `updateCompanion()` 을 바꾼다:

```swift
private func updatePlant() {
    plant.update(todayUsageByProvider: store.todayUsageByProvider,
                 todayDate: LocalUsageReader.todayKey(),
                 burnTier: store.burnTier,
                 limitWarning: store.isLimitWarning,
                 hasUsageData: store.hasUsageData)
}
```

`grantCandies(from:limitsReady:)` 는 그대로 살려 **지갑 보너스**로 바꾼다
(`PlantEngine.grantWindowBonus`). 창 판정 로직이 이미 검증돼 있다.

## 경제 구조를 바꾸는 이유

PokeTokenBar 는 재화가 곧 사용한 토큰이다 —
`쓸 수 있는 재화 = usedSinceInstall − spentTokens`. 성장 미터와 상점 지갑이 같은 값이다.
그래서 이상한 사탕을 XP 값어치(100M)의 **5배**(500M)로 매겨야만
구매가 순손실이 되어 무한 자가성장을 막을 수 있었다. 코드 주석에 그 고민이 그대로 남아 있다.

여기서는 그 문제가 없다. **같은 강에서 물길이 둘로 갈릴 뿐**이다.

```
                ┌─▶ 가중 환산 mL ──▶ 화분이 저절로 자란다
쓴 토큰 ────────┤
                └─▶ 원시 토큰 ────▶ 지갑 · 물/거름/영양제를 산다 ─▶ 가속
```

둘은 서로 뺏지 않는다. 상점에서 다 써도 이미 자란 건 1mL도 안 줄어든다.
`쓸 수 있는 재화 = 쓴 토큰 − 쓴 재화` 가 아니기 때문이다.

가속의 천장은 가격이 아니라 **수입**이 막는다 —
지갑 하루치를 통째로 물에 쏟으면 하루 자동 성장만큼 더 자라서 **최대 2배**다.
아무리 부지런해도 사이클이 절반 밑으로 안 내려가고, 아무것도 안 사도 멈추지 않는다.

세 소모품은 **모양**이 다르다(정액 / 배율 / 비례). 값만 다르고 하는 일이 같으면
제일 싼 것만 사게 되므로, 갈리는 건 값이 아니라 **언제 쓰느냐**여야 한다.

값의 단위는 토큰 수가 아니라 **일**이다 — `가격 = 일수 × 하루 유입`.
절대 수치로 두면 화면에서 `157,500,000` 이 며칠인지 알 수 없어 상점이 "영영 못 사는 곳"이 된다.
하루 유입은 앱이 최근 14일 달력일 평균으로 **직접 잰다**(사람마다 10배씩 다르다).

`TwoStreamsTests` 가 이 불변식을 지킨다 — 첫 줄은 **쓴 토큰 하나가 두 곳으로 간다**.

> 중간에 한 번 이걸 하나로 합쳐 "부는 것 자체가 지출"로 만든 적이 있다. 그건 잘못이었다.
> 쓰면 자란다는 약속이 사라져서 앱을 안 열면 화분이 멈췄고, 이중 사용을 피하려던 건데
> 애초에 여기 해당이 없는 문제였다.

## 이 패키지에 들어 있는 것

`Sources/TokenPlant/Core/` — Foundation 전용, AppKit/SwiftUI 없음.
그래서 UI 를 건드리기 전에 `swift test` 로 초록불을 먼저 확인할 수 있다.

| 파일 | 내용 |
|---|---|
| `PlantBalance.swift` | 물 환산(가중치), 10단계 임계값, **두 물길 환율·하루 유입 측정**, 목마름·스트릭, 창 보너스 |
| `PlantModel.swift` | 종 카탈로그(15종), 등급·실루엣, `PotState`·`GardenEntry`·`GardenTier` |
| `PlantShop.swift` | 상점 10품목(성장 3 · 씨앗 2 · 보유형 2 · 장식 3), 값은 **일**로 정하고 토큰 수는 파생 |
| `PlantEngine.swift` | 적립(화분+지갑 동시)·아이템·단계 상승·목마름·상점·이식 (전부 순수 함수) |
| `PlantSprites.swift` | 24×24 화분 10단계 + 16×16 정원 3실루엣, 아웃라인·음영 자동 생성 |
| `IconSprites.swift` | 16×16 상점 아이콘 7 · 정원 장식 3 · 메뉴바 전용 10단계 |
| `PlantStore.swift` | `@MainActor @Observable` 껍데기 — 저장·연출 신호·파생값. 판정은 안 한다 |
| `UsageReader.swift` | Claude Code / Codex JSONL 파싱 (포크에서는 버린다 — `UsageStore` 가 대체) |

`Sources/TokenPlant/UI/` — SwiftUI. 포크에서 그대로 옮겨오는 부분.

| 파일 | 내용 |
|---|---|
| `PixelSpriteView.swift` | 픽셀 격자 렌더러 3종: 식물(`PixelSpriteView`) · 아이콘(`PixelIconView`) · 메뉴바 `NSImage` |
| `PotView.swift` | 홈 화분. 물방울·거름 알갱이·단계 교차 페이드 + 아이템 퀵 슬롯. `slot`/`compact` 로 두 그루 |
| `GardenScene.swift` | 7티어 레이아웃, 계절 팔레트 3종, 슬롯 좌표 (생성물) |
| `GardenView.swift` | 정원 창. `GardenComposer` 가 씬을 hex 격자로 조립하고 Canvas·PNG 가 그걸 공유한다 |
| `ShopView.swift` | 상점 + 가방. 며칠치·부족분을 기다림으로·거름/영양제는 물 대비 손익까지 |
| `CollectionView.swift` | 정원 미니뷰 + 15종 도감 + 기록 |

`Tests/TokenPlantTests/` — 194개.

| 파일 | 개수 | 무엇을 고정하나 |
|---|---|---|
| `TwoStreamsTests` | 24 | **두 물길** — 쓰면 자란다, 사도 안 줄어든다, 가속 천장 2배, 세 아이템의 모양 |
| `DailyRateTests` | 11 | **기준** — 하루 유입 측정·창 정리, 가격이 일수에서 파생되는가 |
| `PlantBalanceTests` | 18 | 물 환산 가중치, 임계값, 스트릭, 목마름, 두 물길 환율, 상점 경제 |
| `PlantEngineTests` | 26 | 중복 적립, 날짜 넘김, 단계, 상점, 이식, 슬롯 2개, 장식 |
| `PlantSpritesTests` | 19 | 화분·정원 스프라이트, 아이콘, 메뉴바 격자 무결성 |
| `PlantStoreTests` | 23 | 저장 왕복, 손상된 파일 흡수, 아이템·연출 신호, 슬롯 파생값 |
| `UsageReaderTests` | 25 | 로그 파싱 — 중복 제거, 날짜 창, 누적값, 청크 경계 |
| `GardenSceneTests` | 24 | 씬 조립, 슬롯 좌표, 배경 구멍, PNG 크기 |
| `LimitsReaderTests` | 24 | 실측 응답 픽스처 — Claude 레거시/신형, Codex RPC camelCase, Keychain 파싱 |

## 설계에서 물린 자리 세 곳

포크에 옮길 때 이 세 가지는 그대로 지켜야 한다.

**1. 연출 이벤트를 뷰가 소비하지 않는다.** 화분이 두 개면 먼저 그려진 쪽이 이벤트를
먹어버리고 다른 쪽은 조용히 게이지만 오른다. `celebrationSeq` 카운터로 재생을 한 번만
통과시키고, `celebration` 값 자체는 다음 이벤트가 덮어쓴다.

**2. 아이템 버튼은 화분 수와 무관하게 한 벌이다.** 물은 나뉘지 않고 **양쪽에 똑같이**
들어간다(`applyWater` 가 `\.pot` 과 `\.pot2` 를 같이 키운다). 나눠 주면 슬롯을 사는 게
성장 반토막이라 아무도 안 산다. 슬롯마다 버튼을 두면 같은 걸 두 번 살 수 있다고 오해한다.
이식 버튼만 슬롯별로 있다.

**3. 씬 조립과 그리기를 분리했다.** `GardenComposer.compose()` 가 hex 격자를 돌려주고
Canvas 와 PNG 내보내기가 **같은 격자**를 쓴다. 그리기 코드를 두 곳에 두면 내보낸 PNG 가
화면과 달라지는 게 시간문제다.

## 빌드

```bash
swift build
swift test           # 194개
```

이 패키지는 **Swift 컴파일러로 검증되지 않았다.** Cowork 샌드박스에 Swift 툴체인이 없고
(`download.swift.org` 가 프록시에서 막힌다) 로컬 VM 에도 없다.
수치와 로직은 Python 으로 같은 계산을 돌려 대조했지만, 문법·타입 오류는 남아 있을 수 있다.
`swift build` 출력을 붙여주면 바로 잡는다.

---

## 검증 상태 (2026-09-14)

Swift 툴체인을 양쪽 샌드박스에 못 깔았다 — `download.swift.org` 가 클라우드 컨테이너와
로컬 VM 모두에서 프록시 allowlist 에 막힌다(403 `blocked-by-allowlist`).
그래서 컴파일러 대신 다섯 갈래로 검증했다.

**1. 문법** — `python3 verify/check_syntax.py .` — `tree-sitter-swift` 로 26개 파일 전부 파싱.
ERROR/MISSING 노드 0개. 타입 검사는 아니지만 손으로 적다 생긴 문법 오류는 여기서 걸러진다.
이 문법에 구멍이 셋 있다(`try await` 바인딩 · `nonisolated(unsafe)` · `x as? T ?? 기본값`).
셋 다 소스에서 피해 뒀다 — 원본 PokeTokenBar 는 세 번째에만 10군데가 걸린다.

**2. 로직** — `verify/engine_port.py` 가 `PlantEngine.swift` 를 그대로 포팅한 것이고,
`verify/run_tests.py` 가 Swift 테스트 본문을 그대로 실행한다.
단정 **235개 전부 통과**.

**3. 스프라이트 데이터** — `icons.py` / `plant_sprites.py` 의 원본 픽셀맵과
생성된 Swift 배열을 줄 단위로 대조한다(품목 144줄 · 장식 48줄 · 메뉴바 115줄, 전부 일치).
16×16 이 아닌 줄이 하나라도 있으면 렌더에서 인덱스가 밀리는데 컴파일은 통과한다.

**4. 데이터 불변식** — `python3 verify/check_data.py`.
씬 슬롯이 해금 조건보다 적은지, 좌표가 캔버스를 넘는지, 스프라이트 줄 길이,
팔레트에 없는 문자, 품목↔아이콘 누락, 단계 수 일치를 Swift 소스에서 직접 읽어 검사한다.
이 검사가 실제로 슬롯 부족 버그를 잡았다(아래).

**5. 멤버 참조** — `python3 verify/check_members.py .` — 감시 타입 27개의 멤버 465개를
선언과 대조한다. 이름을 바꾼 자리에 남은 옛 호출을 잡는다. 잔액 모델로 갈아엎을 때
이 검사가 `store.waterByHand` / `save.sunlight` / `s.carryoverWater` 잔재를 전부 짚어냈다.

### 이 과정에서 잡은 실제 버그

`ingest()` 의 순서 문제. 날짜 갱신을 seed 판정보다 먼저 하면:

```swift
if save.lastDate != today { save.claimedTodayByProvider = [:] }   // ← 여기서 [:] 로 채워짐
guard let baseline = save.claimedTodayByProvider else { ... }     // ← 영영 안 탄다
```

새 세이브는 `lastDate == ""` 이므로 첫 갱신에서 무조건 이 분기를 탄다.
그러면 기준값이 `[:]` 가 되어 **그날 누적 사용량 전체가 델타로 잡힌다**.
실측 하루(캐시읽기 3B)면 300,000mL — **설치 직후 Lv.9 열매**다.

seed 판정을 먼저 하도록 순서를 뒤집고, 회귀 테스트
`testFreshInstallOnNewDayStillTakesSeedPathWithCap` 을 박아뒀다.

### 남은 위험

**타입 검사는 안 됐다.** Swift 6 strict concurrency, Optional 승격,
`CodingKeys` 자동 생성, `WritableKeyPath` 쓰기 같은 건 컴파일러만 확정할 수 있다.
`swift build` 출력이 필요하다.

Swift 를 고치면 `verify/engine_port.py` 도 같이 고쳐야 한다(의도적 중복).
