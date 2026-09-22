import XCTest
@testable import TokenPlant

// MARK: 두 물길 — 이 앱의 전부
//
// 이 파일이 지키는 것 하나: **쓴 토큰 하나가 두 곳으로 간다.**
//
//                ┌─▶ 가중 환산 mL ──▶ 화분이 저절로 자란다. 아무것도 안 눌러도
// 쓴 토큰 ───────┤
//                └─▶ 원시 토큰 ────▶ 지갑. 물·거름·영양제를 사서 더 빨리 자란다
//
// 둘은 **서로 뺏지 않는다.** 상점에서 다 써도 이미 자란 건 그대로다.
//
// 한동안 이걸 하나로 합쳐 "부는 것 자체가 지출"로 만들었었다. 그건 잘못이었다 —
// 쓰면 자란다는 약속이 사라져서, 앱을 안 열면 화분이 멈췄다.
// PokeTokenBar 의 이중 사용 문제(사탕을 값어치의 5배로 팔아야 억제됨)를 피하려던 건데,
// 그건 저쪽이 `쓸 수 있는 재화 = 쓴 토큰 − 쓴 재화` 라 성장 게이지와 지갑이
// **같은 값**이어서 생긴 문제였다. 여기선 강 하나에서 물길이 둘로 갈릴 뿐이라 해당이 없고,
// 가속 폭은 가격이 아니라 **수입**이 막는다 — `testAccelerationCeilingIsExactlyDouble`.

final class TwoStreamsTests: XCTestCase {

    private let day1 = "2026-09-01"
    private let day2 = "2026-09-02"
    private let day3 = "2026-09-03"

    private func freshSave(species: String = "tomato") -> PlantSave {
        var s = PlantSave()
        s.pot = PotState(speciesID: species, plantedAt: Date(timeIntervalSince1970: 0))
        s.claimedTodayByProvider = [:]      // seed 완료 상태로 시작
        return s
    }

    // MARK: 1. 쓰면 자란다 — 아무것도 안 눌러도

    /// 이 앱의 약속. 토큰을 쓰면 화분이 자란다. 버튼도, 붓기도, 앱을 여는 것도 필요 없다.
    func testUsingTokensGrowsThePlantWithNoUserAction() {
        var s = freshSave()
        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(output: 400_000)],
                           today: day1)
        XCTAssertGreaterThan(s.pot!.water, 0, "토큰을 썼는데 화분이 안 자랐다")
        XCTAssertGreaterThan(s.pot!.stageIndex, 0, "단계가 안 올랐다")
    }

    /// 같은 토큰이 지갑에도 들어간다. 성장에서 떼어 온 게 아니다.
    func testTheSameTokensAlsoFillTheWallet() {
        var s = freshSave()
        let snap = ["claude": TokenDelta(output: 100_000, cacheRead: 20_000_000)]
        PlantEngine.ingest(&s, todayByProvider: snap, today: day1)

        XCTAssertGreaterThan(s.pot!.water, 0)
        XCTAssertEqual(s.rawWallet, 20_100_000, "지갑에 원시 토큰이 그대로 안 들어갔다")
    }

    /// **핵심 불변식**: 지갑을 다 써도 이미 자란 건 1mL도 안 줄어든다.
    func testSpendingTheWalletNeverShrinksThePlant() {
        var s = freshSave()
        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(cacheRead: 3_000_000_000)],
                           today: day1)
        let grown = s.pot!.water
        let stage = s.pot!.stageIndex
        XCTAssertGreaterThan(grown, 0)

        s.rawWallet = ShopItem.shinyCharm.price
        XCTAssertEqual(PlantEngine.buy(.shinyCharm, &s), .ok)

        XCTAssertEqual(s.rawWallet, 0, "지갑에서 안 나갔다")
        XCTAssertEqual(s.pot!.water, grown, "구매가 성장을 갉아먹었다")
        XCTAssertEqual(s.pot!.stageIndex, stage)
    }

    /// 앱을 안 열어도 며칠치가 통째로 들어온다 — 방치는 성장을 멈추지 않는다.
    func testDaysAwayStillGrowTheePlant() {
        var s = freshSave()
        for (i, day) in [day1, day2, day3].enumerated() {
            _ = i
            PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(output: 200_000)],
                               today: day)
        }
        XCTAssertGreaterThanOrEqual(s.pot!.water, 3_000, "사흘치가 안 들어왔다")
    }

    // MARK: 2. 가속의 천장은 **값이 아니라 하루 상한**이 막는다

    /// 하루에 물에 쓸 수 있는 몫은 유입의 40% 다 — 2개 × 0.2일치. 나머지 60% 는 지갑에 남는다.
    ///
    /// **예전에는 천장을 값이 정했다**: 0.2일치 × 5개 = 정확히 하루치 = 가속 2.0배.
    /// 숫자로는 깔끔했지만 그게 상점을 통째로 죽였다. 물 버튼은 항상 눈에 보이고 항상
    /// 살 수 있고 즉시 보상이 있으니 사람은 상한까지 붓는다 — 그러면 유입 100% 가
    /// 물로 나가서 지갑이 영원히 0이다. 실제로 일주일 넘게 써도 물밖에 못 샀다.
    ///
    /// 값을 내리는 건 답이 아니다. 물은 토큰과 1:1 등가 교환이라 값을 내리면
    /// 거름(1.17배)·영양제(초반 2.24배)가 전부 물보다 나빠져 상점의 나머지가 죽는다.
    /// 그래서 손잡이를 **횟수 상한**으로 옮겼다.
    func testDailyCapBoundsAccelerationNotThePrice() {
        let auto = PlantBalance.dailyWaterFromTokens
        let bought = PlantBalance.dailyWaterUses * Water.mL

        // 값만 보면 하루치로 다섯 개를 살 수 있다. 상한이 그걸 둘로 막는다.
        XCTAssertEqual(PlantBalance.assumedDailyRaw / ShopItem.water.price, 5,
                       "물값이 하루치의 1/5 이 아니다")
        XCTAssertLessThan(PlantBalance.dailyWaterUses, 5,
                          "상한이 값과 같으면 유입을 100% 먹는다 — 지갑이 안 쌓인다")

        XCTAssertEqual(Double(auto + bought) / Double(auto), 1.4, accuracy: 0.01,
                       "최대 가속이 1.4배가 아니다")

        // 진짜 지켜야 하는 것: 상한까지 써도 유입의 **절반 이상**이 지갑에 남는다.
        // 이게 상점이 살아 있다는 조건이다.
        let spent = Double(PlantBalance.dailyWaterUses) * ShopItem.water.priceDays
        XCTAssertLessThan(spent, 0.5, "하루 유입의 \(Int(spent * 100))% 가 물로 나간다")
    }

    /// 실제로 돌려봐도 1.4배여야 한다 — 상수 계산만 맞고 코드가 다르면 소용없다.
    ///
    /// 그리고 **지갑이 남은 채로 멈춰야 한다.** 지갑이 먼저 마르면 막은 건 상한이 아니라
    /// 값이고, 그건 고치기 전 상태와 같다.
    func testPouringToTheCapStillLeavesMostOfTheWallet() {
        let snap = ["claude": TokenDelta(cacheRead: PlantBalance.assumedDailyRaw)]

        var lazy = freshSave()
        PlantEngine.ingest(&lazy, todayByProvider: snap, today: day1)

        var busy = freshSave()
        PlantEngine.ingest(&busy, todayByProvider: snap, today: day1)
        let purse = busy.rawWallet
        var poured = 0
        while PlantEngine.buy(.water, &busy) == .ok {
            guard case .ok = PlantEngine.use(.water, &busy, today: day1) else { break }
            poured += 1
        }

        let ratio = Double(busy.pot!.water) / Double(lazy.pot!.water)
        XCTAssertEqual(ratio, 1.4, accuracy: 0.1, "부지런히 사도 1.4배가 안 나온다 (\(ratio))")
        XCTAssertEqual(poured, PlantBalance.dailyWaterUses, "상한이 아니라 지갑이 먼저 떨어졌다")
        XCTAssertGreaterThan(Double(busy.rawWallet) / Double(purse), 0.5,
                             "상한까지 부었는데 지갑이 절반도 안 남았다")
    }

    // MARK: 3. 세 아이템이 모양이 다르다

    /// 기준 하루치로 심었을 때의 목표. 목표가 사람마다 달라진 뒤로 테스트도 한 기준을 잡아야 한다.
    private var refCycle: Int { PlantBalance.cycleWater(dailyRaw: PlantBalance.assumedDailyRaw) }

    /// 물은 **정액** — 갓 심었든 거목 직전이든 같은 양이다.
    func testWaterIsFlatWhereverYouAre() {
        var young = freshSave()
        young.inventory[ShopItem.water.rawValue] = 1
        var old = freshSave()
        old.pot!.water = PlantBalance.threshold(stage: 8, cycle: old.pot!.cycleWater)
        old.pot!.stageIndex = 8
        old.inventory[ShopItem.water.rawValue] = 1

        guard case .ok(let a) = PlantEngine.use(.water, &young, today: day1),
              case .ok(let b) = PlantEngine.use(.water, &old, today: day1) else {
            return XCTFail("물을 못 썼다")
        }
        XCTAssertEqual(a, b, "물이 구간에 따라 달라졌다")
        XCTAssertEqual(a, Water.mL)
    }

    /// 영양제는 **비례** — 초반에 크고 후반에 작다. 그게 이 품목의 성격이다.
    func testNutrientIsProportionalSoTimingMatters() {
        let early = Nutrient.water(currentWater: 0, cycle: refCycle)
        let late = Nutrient.water(currentWater: PlantBalance.threshold(stage: 8, cycle: refCycle),
                                  cycle: refCycle)
        XCTAssertGreaterThan(early, late * 2, "영양제가 언제 써도 비슷하다 — 고를 이유가 없다")

        // 같은 값으로 물을 샀을 때와 견준다: 초반엔 이득, 후반엔 손해여야 한다.
        let alt = Int(ShopItem.nutrient.priceDays / ShopItem.water.priceDays) * Water.mL
        XCTAssertGreaterThan(early, alt, "갓 심은 그루에도 물만 못하다")
        XCTAssertLessThan(late, alt, "거목 앞에서도 이득이면 쓸 때를 고를 이유가 없다")
    }

    /// 거름은 **배율** — 즉시 주는 물이 0이다. 앞으로 쓸 때만 값을 한다.
    func testFertilizerGivesNothingNowAndMultipliesLater() {
        var s = freshSave()
        s.inventory[ShopItem.fertilizer.rawValue] = 1
        let before = s.pot!.water

        guard case .ok(let gained) = PlantEngine.use(.fertilizer, &s, today: day1) else {
            return XCTFail("거름을 못 썼다")
        }
        XCTAssertEqual(gained, 0, "거름이 즉시 물을 줬다 — 그러면 물과 구분이 안 된다")
        XCTAssertEqual(s.pot!.water, before)

        // 이제부터 들어오는 물이 25% 늘어난다.
        var plain = freshSave()
        let snap = ["claude": TokenDelta(output: 200_000)]
        PlantEngine.ingest(&plain, todayByProvider: snap, today: day2)
        PlantEngine.ingest(&s, todayByProvider: snap, today: day2)
        XCTAssertGreaterThan(s.pot!.water, plain.pot!.water, "거름이 안 먹혔다")
    }

    /// 거름은 **평평한** 품목이라 물과 직접 견줄 수 있다. 마진이 얇아야 고민이 된다.
    func testFertilizerMarginIsThin() {
        let perWater = Double(Water.mL) / ShopItem.water.priceDays
        let dailyML = PlantBalance.dailyWaterFromTokens
        let fertBack = Double(dailyML * PlantBalance.fertilizerDays
                              * PlantBalance.fertilizerBonusPercent / 100)
        let ratio = (fertBack / ShopItem.fertilizer.priceDays) / perWater

        XCTAssertGreaterThan(ratio, 1.0, "거름이 물보다 나쁘다 — 살 이유가 없다")
        XCTAssertLessThan(ratio, 1.2, "거름이 물보다 너무 좋다 — 물이 장식이 된다")
    }

    /// 영양제는 **비례**라서 한 점에서 물과 견주는 게 의미가 없다 — 구간마다 값이 다른 게 성격이다.
    /// 봐야 하는 건 **손익분기가 어디냐**다.
    ///
    /// 10% 였을 때 손익분기가 사이클의 6% 지점이라 이득 구간이 첫 1.5일뿐이었다.
    /// 그건 "초반 전용"이 아니라 그냥 죽은 품목이다. 절반쯤에서 갈려야 고를 이유가 생긴다.
    func testNutrientBreakEvenLandsMidCycle() {
        let alt = (ShopItem.nutrient.priceDays / ShopItem.water.priceDays) * Double(Water.mL)
        let breakEven = Double(refCycle) - alt / (Double(Nutrient.reducePercent) / 100)
        let share = breakEven / Double(refCycle)

        XCTAssertGreaterThan(share, 0.40, "이득 구간이 너무 좁다 — 사실상 죽은 품목이다")
        XCTAssertLessThan(share, 0.60, "이득 구간이 너무 넓다 — 언제 써도 되면 고를 이유가 없다")

        // 갓 심었을 때는 물보다 확실히 나아야 새 사이클까지 아껴둘 이유가 생긴다.
        XCTAssertGreaterThan(Double(Nutrient.water(currentWater: 0, cycle: refCycle)), alt * 1.5)
        // 거목 앞에서는 확실히 손해여야 "언제 쓰느냐"가 선택이 된다.
        XCTAssertLessThan(
            Double(Nutrient.water(currentWater: PlantBalance.threshold(stage: 9, cycle: refCycle),
                                  cycle: refCycle)), alt)
    }

    // MARK: 4. 보너스는 한 길로만

    /// 아이템으로 준 물도 자동 성장과 **같은 보너스**를 받는다.
    /// 경로마다 규칙이 갈리면 나중에 아무도 못 맞춘다.
    func testItemWaterGetsTheSameBonusesAsAutomaticGrowth() {
        var plain = freshSave()
        plain.inventory[ShopItem.water.rawValue] = 1
        var fed = freshSave()
        fed.inventory[ShopItem.water.rawValue] = 1
        fed.fertilizerExpiresAt = Date().addingTimeInterval(86_400)

        guard case .ok(let a) = PlantEngine.use(.water, &plain, today: day1),
              case .ok(let b) = PlantEngine.use(.water, &fed, today: day1) else {
            return XCTFail("물을 못 썼다")
        }
        XCTAssertGreaterThan(b, a, "거름이 아이템 물에는 안 붙었다")
    }

    // MARK: 5. 화분 두 개

    /// 물은 나뉘지 않고 **양쪽에 똑같이** 들어간다.
    /// 나눠 주면 슬롯을 사는 게 성장 반토막이라 아무도 안 산다.
    func testWaterReachesBothPotsEqually() {
        var s = freshSave()
        s.pot2 = PotState(speciesID: "rose")
        s.inventory[ShopItem.water.rawValue] = 1

        PlantEngine.use(.water, &s, today: day1)
        XCTAssertEqual(s.pot!.water, s.pot2!.water, "두 화분이 다른 양을 받았다")
        XCTAssertGreaterThan(s.pot!.water, 0)
    }

    func testAutomaticGrowthAlsoReachesBothPots() {
        var s = freshSave()
        s.pot2 = PotState(speciesID: "rose")
        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(output: 400_000)],
                           today: day1)
        XCTAssertEqual(s.pot!.water, s.pot2!.water)
        XCTAssertGreaterThan(s.pot2!.water, 0)
    }

    // MARK: 6. 스트릭 · 목마름

    /// 스트릭은 **토큰을 쓴 날**을 센다. 앱을 연 날이 아니다 —
    /// 열어보지 않아도 자라는 게 이 앱의 약속이라, 출석을 세면 그 약속이 깨진다.
    func testStreakCountsTokenDaysNotAppOpens() {
        var s = freshSave()
        let snap = ["claude": TokenDelta(output: 10_000)]
        PlantEngine.ingest(&s, todayByProvider: snap, today: day1)
        XCTAssertEqual(s.streakDays, 1)
        PlantEngine.ingest(&s, todayByProvider: snap, today: day2)
        XCTAssertEqual(s.streakDays, 2)
        PlantEngine.ingest(&s, todayByProvider: snap, today: "2026-09-06")
        XCTAssertEqual(s.streakDays, 1, "사흘 비었는데 스트릭이 이어졌다")
    }

    /// 창 보너스는 지갑으로 간다 — 성장에도 스트릭에도 안 섞인다.
    func testWindowBonusGoesToTheWalletOnly() {
        var s = freshSave()
        s.windowsSeeded = true
        let before = s.pot!.water
        let w = LimitWindowInfo(key: "s", name: "5시간", kind: .session, utilization: 100)

        let gained = PlantEngine.grantWindowBonus(&s, windows: [w], isReady: true)
        XCTAssertEqual(gained, PlantBalance.windowBonusSession)
        XCTAssertEqual(s.rawWallet, PlantBalance.windowBonusSession)
        XCTAssertEqual(s.pot!.water, before, "창 보너스가 화분을 키웠다")
        XCTAssertEqual(s.streakDays, 0, "창 보너스가 스트릭을 올렸다")
        XCTAssertTrue(s.dailyRaw.isEmpty, "창 보너스가 하루 유입 통계에 섞였다")
    }

    /// 목마름은 색만 마른다 — 누적 물은 안 깎인다.
    func testThirstNeverEatsProgress() {
        var s = freshSave()
        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(output: 400_000)],
                           today: day1)
        let grown = s.pot!.water

        XCTAssertEqual(PlantEngine.thirstLevel(s, today: "2026-09-11"), 1, accuracy: 0.001)
        XCTAssertEqual(s.pot!.water, grown, "방치가 누적 물을 깎았다")
    }

    /// 한 번 자라면 색이 바로 돌아온다.
    func testGrowingResetsThirst() {
        var s = freshSave()
        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(output: 400_000)],
                           today: day1)
        XCTAssertGreaterThan(PlantEngine.thirstLevel(s, today: "2026-09-11"), 0)

        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(output: 500_000)],
                           today: "2026-09-11")
        XCTAssertEqual(PlantEngine.thirstLevel(s, today: "2026-09-11"), 0, accuracy: 0.001)
    }

    // MARK: 7. 상점 · 첫 설치 · 저장

    func testInsufficientWalletReportsTheShortfall() {
        var s = freshSave()
        s.rawWallet = 300
        guard case .insufficientBalance(let short) = PlantEngine.canBuy(.fertilizer, s) else {
            return XCTFail("모자란데 살 수 있다고 한다")
        }
        XCTAssertEqual(short, ShopItem.fertilizer.price - 300)
    }

    /// 가격은 **그 사람의** 하루 유입으로 환산된다. 하루를 절반 쓰는 사람에게는 절반 값이다.
    func testPriceFollowsTheMeasuredDailyRate() {
        var s = freshSave()
        let half = PlantBalance.assumedDailyRaw / 2
        s.dailyRaw = [day1: half, day2: half, day3: half]

        XCTAssertEqual(PlantEngine.price(.water, s), Int(ShopItem.water.priceDays * Double(half)))
        XCTAssertLessThan(PlantEngine.price(.water, s), ShopItem.water.price)
    }

    /// 첫 설치에 전체 로그가 소급되면 첫 화면부터 거목에 지갑이 가득이다.
    func testFirstInstallCapsBothStreams() {
        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato")
        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(cacheRead: 30_000_000_000)],
                           today: day1)
        XCTAssertLessThanOrEqual(s.rawWallet, PlantBalance.firstDayRawCap(dailyRaw: PlantBalance.assumedDailyRaw))
        XCTAssertLessThan(s.pot!.stageIndex, 6, "설치 직후 만렙 근처가 됐다")
    }

    func testWalletAndDailyRawSurviveSaveRoundTrip() throws {
        var s = freshSave()
        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(output: 123_456)],
                           today: day1)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(PlantSave.self, from: data)

        XCTAssertEqual(back.rawWallet, s.rawWallet)
        XCTAssertEqual(back.dailyRaw, s.dailyRaw)
        XCTAssertEqual(back.pot?.water, s.pot?.water)
    }

    /// 손상된 파일에서 지갑이 음수로 들어와도 0으로 잘린다.
    func testNegativeWalletIsClamped() throws {
        let json = #"{"rawWallet":-500}"#
        let back = try JSONDecoder().decode(PlantSave.self, from: Data(json.utf8))
        XCTAssertEqual(back.rawWallet, 0)
    }
}
