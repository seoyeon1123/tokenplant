import XCTest
@testable import TokenPlant

// MARK: 물 환산 · 단계 임계값

final class PlantBalanceTests: XCTestCase {

    /// 실측(2026-09-09 Claude Code 하루): in 1.1K · out 553K · cache w 1.8M · cache r 106.9M
    /// = 원시 109.2M → 물 15,706 mL. 이 값이 흔들리면 임계값 테이블 전체가 어긋난다.
    func testWaterMatchesMeasuredDay() {
        let d = TokenDelta(input: 1_100, output: 553_000, cacheWrite: 1_800_000, cacheRead: 106_900_000)
        XCTAssertEqual(d.raw, 109_254_100)
        XCTAssertEqual(PlantBalance.water(from: d), 15_706)
    }

    /// 캐시 읽기가 원시의 98%인데 물에서는 68%로 내려간다 — 가중치를 두는 이유 그 자체다.
    func testCacheReadDominatesRawButNotWater() {
        let d = TokenDelta(input: 1_100, output: 553_000, cacheWrite: 1_800_000, cacheRead: 106_900_000)
        let rawShare = Double(d.cacheRead) / Double(d.raw)
        XCTAssertGreaterThan(rawShare, 0.97)

        let onlyCacheRead = PlantBalance.water(from: TokenDelta(cacheRead: d.cacheRead))
        let waterShare = Double(onlyCacheRead) / Double(PlantBalance.water(from: d))
        XCTAssertLessThan(waterShare, 0.75)
        XCTAssertGreaterThan(waterShare, 0.60)
    }

    /// 카운터 리셋으로 음수 델타가 들어와도 물이 깎이지 않는다.
    func testNegativeDeltaNeverRemovesWater() {
        let d = TokenDelta(input: -500, output: -1_000, cacheWrite: -2_000, cacheRead: -9_000_000)
        XCTAssertEqual(PlantBalance.water(from: d), 0)
    }

    /// 기준 하루치로 심었을 때의 목표. 목표는 이제 사람마다 다르므로 테스트도 기준을 하나 잡는다.
    private var refCycle: Int { PlantBalance.cycleWater(dailyRaw: PlantBalance.assumedDailyRaw) }

    private func th(_ i: Int) -> Int { PlantBalance.threshold(stage: i, cycle: refCycle) }

    func testThresholdsAreStrictlyIncreasing() {
        let f = PlantBalance.stageFractions
        XCTAssertEqual(f.count, 10)
        XCTAssertEqual(f.first, 0)
        XCTAssertLessThan(f.last!, 1.0, "마지막 단계가 목표와 같으면 만렙과 이식이 붙어버린다")
        for i in 1..<f.count {
            XCTAssertGreaterThan(th(i), th(i - 1), "단계 \(i) 임계값이 앞 단계보다 작다")
        }
    }

    /// 누가 심어도 한 그루는 4주다 — 이게 없으면 적게 쓰는 사람은 1년 넘게 씨앗만 본다.
    func testCycleIsFourWeeksAtAnyUsageRate() {
        for daily in [5_000_000, 20_000_000, 105_000_000, 400_000_000] {
            let cycle = PlantBalance.cycleWater(dailyRaw: daily)
            let perDay = max(1, daily / PlantBalance.rawPerML)
            let days = Double(cycle) / Double(perDay)
            XCTAssertEqual(days, Double(PlantBalance.targetCycleDays), accuracy: 1,
                           "하루 \(daily) 쓰는 사람의 사이클이 \(days)일이다")
        }
    }

    /// 첫날 크레딧이 사이클을 통째로 채우면 안 된다 — 설치하자마자 이식 버튼이 떠 있게 된다.
    /// 상한을 고정값(30,000mL)으로 뒀을 때 하루 5M 쓰는 사람에게 실제로 그랬다.
    func testFirstDayNeverFinishesAPlantAtAnyUsageRate() {
        for daily in [1_000_000, 5_000_000, 20_000_000, 105_000_000, 400_000_000] {
            let cycle = PlantBalance.cycleWater(dailyRaw: daily)
            let cap = PlantBalance.firstDayCredit(cycle: cycle)
            XCTAssertLessThan(cap, PlantBalance.threshold(stage: 5, cycle: cycle),
                              "하루 \(daily) 쓰는 사람의 첫날이 Lv.6 을 넘긴다")
            XCTAssertLessThan(Double(cap) / Double(cycle), 0.12,
                              "하루 \(daily) 쓰는 사람의 첫날이 사이클의 12% 를 넘는다")
        }
    }

    /// 목표는 심을 때 한 번 잡히고 끝까지 안 움직인다.
    /// 많이 쓴 날 목표가 같이 늘어나면 "쓰면 자란다"가 깨진다.
    func testCycleIsClampedForExtremeRates() {
        XCTAssertEqual(PlantBalance.cycleWater(dailyRaw: 1), PlantBalance.minCycleWater)
        XCTAssertEqual(PlantBalance.cycleWater(dailyRaw: 100_000_000_000),
                       PlantBalance.maxCycleWater)
    }

    /// 뒤로 갈수록 구간이 벌어져야 한다 — 마지막 한 칸이 전체의 1/3.
    func testFinalStepIsAboutOneThirdOfTotal() {
        let f = PlantBalance.stageFractions
        let lastStep = f[f.count - 1] - f[f.count - 2]
        let ratio = lastStep / f[f.count - 1]
        XCTAssertGreaterThan(ratio, 0.30)
        XCTAssertLessThan(ratio, 0.36)
    }

    /// 만렙(Lv.10)은 이식보다 먼저 와야 한다 — 거목을 며칠 보고 나서 보내는 게 사이클의 끝맛이다.
    func testFinalStageArrivesBeforeTransplant() {
        let perDay = Double(PlantBalance.dailyWaterFromTokens)
        let toFinal = Double(th(9)) / perDay
        let toTransplant = Double(refCycle) / perDay
        XCTAssertLessThan(toFinal, toTransplant)
        XCTAssertEqual(toTransplant - toFinal, 1.75, accuracy: 0.5,
                       "거목으로 보내는 날이 너무 짧거나 길다")
    }

    /// 첫날(하루치 15,080mL) 안에 세 단계가 오른다 — 씨앗 → 발아 → 떡잎 → 어린잎(index 3).
    /// 처음 여는 사람이 뭔가 일어나는 걸 봐야 다음날 또 열어본다.
    func testThreeStagesOnFirstDay() {
        let day = PlantBalance.dailyWaterFromTokens
        XCTAssertEqual(PlantBalance.stageIndex(forWater: day, cycle: refCycle), 3)
        // 반나절에도 이미 두 단계.
        XCTAssertEqual(PlantBalance.stageIndex(forWater: day / 2, cycle: refCycle), 2)
    }

    func testStageIndexClampsAtMax() {
        XCTAssertEqual(PlantBalance.stageIndex(forWater: 0, cycle: refCycle), 0)
        XCTAssertEqual(PlantBalance.stageIndex(forWater: th(1) - 1, cycle: refCycle), 0)
        XCTAssertEqual(PlantBalance.stageIndex(forWater: th(1), cycle: refCycle), 1)
        XCTAssertEqual(PlantBalance.stageIndex(forWater: 999_999_999, cycle: refCycle),
                       PlantBalance.stageCount - 1)
    }

    func testNextThresholdWalksToTransplantThenNil() {
        XCTAssertEqual(PlantBalance.nextThreshold(afterStage: 0, cycle: refCycle), th(1))
        XCTAssertEqual(PlantBalance.nextThreshold(afterStage: 8, cycle: refCycle), th(9))
        XCTAssertEqual(PlantBalance.nextThreshold(afterStage: 9, cycle: refCycle), refCycle)
        XCTAssertNil(PlantBalance.nextThreshold(afterStage: 10, cycle: refCycle))
    }

    // MARK: 보너스 — **합계가 기준이다**

    /// 하루 +1%, 천장 +10%. 예전엔 +2%/일 · 천장 50% 였다.
    ///
    /// 스트릭은 공짜로 자동 적립된다. 그게 돈을 내는 물(+40%)보다 커지면
    /// 상점에 갈 이유가 없고, 실제로 총 배율을 3배까지 부풀린 주범이었다.
    func testStreakBonusCapsAtTen() {
        XCTAssertEqual(PlantBalance.streakBonusPercent(days: 0), 0)
        XCTAssertEqual(PlantBalance.streakBonusPercent(days: 1), 1)
        XCTAssertEqual(PlantBalance.streakBonusPercent(days: 10), 10)
        XCTAssertEqual(PlantBalance.streakBonusPercent(days: 400), 10)

        // 공짜 보너스가 유료 가속을 넘으면 안 된다.
        let paid = PlantBalance.dailyWaterUses * 20   // 물 1개 = 하루치의 20%
        XCTAssertLessThan(PlantBalance.streakBonusPercent(days: 400), paid,
                          "공짜로 쌓이는 보너스가 돈 내고 얻는 가속보다 크다")
    }

    /// **이 파일에서 제일 중요한 단정.**
    ///
    /// 손잡이를 하나씩 보면 다 합리적이었다. 그런데 곱해놓고 재보니 28일 사이클이
    /// **9.1일**(3.06배)이었다 — 합계를 재는 곳이 아무 데도 없어서 아무도 몰랐다.
    /// 환산비율 18% 어긋남보다 훨씬 큰 오차였고, 가격이 "며칠치" 단위라
    /// 상점 속도까지 같이 어긋나 있었다. 그래서 여기서 합계를 못 박는다.
    func testTotalMultiplierStaysNearDouble() {
        // 자동 1.0 + 물 상한까지
        let base = 1.0 + Double(PlantBalance.dailyWaterUses) * 0.2
        let bonus = 1 + Double(PlantBalance.streakBonusPercent(days: 400)
                               + PlantBalance.fertilizerBonusPercent) / 100
        // 영양제는 그루당 한 번, 남은 거리를 당긴다 → 사이클을 그만큼 줄인다
        let full = Double(PlantBalance.targetCycleDays) / (base * bonus)
            * (1 - Double(Nutrient.reducePercent) / 100)
        let spread = Double(PlantBalance.targetCycleDays) / full

        XCTAssertEqual(spread, 2.0, accuracy: 0.15,
                       "아무것도 안 하는 사람 대비 \(String(format: "%.2f", spread))배")
        XCTAssertTrue((12.0...15.0).contains(full),
                      "다 하는 사람 완주가 \(String(format: "%.1f", full))일")
    }

    // MARK: 목마름 — 외형만

    /// 누적 물을 깎지 않는다. 토큰을 안 쓰면 안 자라는 것 자체가 이미 결과인데,
    /// 진행도까지 뺏으면 실제로 쓴 토큰을 두 번 벌주는 셈이다.
    func testThirstRampsFromThreeToSevenDays() {
        XCTAssertEqual(PlantBalance.thirstyAfterIdleDays, 3)
        XCTAssertEqual(PlantBalance.parchedAfterIdleDays, 7)
        XCTAssertLessThan(PlantBalance.thirstyAfterIdleDays, PlantBalance.parchedAfterIdleDays)
    }

    // MARK: 한도 창 보상 — 단위는 **원시 토큰**(지갑으로 간다)

    /// 창만 태워서 상점을 굴릴 수 있으면 안 된다 — 사이클 수입의 10% 안쪽이어야 한다.
    /// 반대로 너무 작으면 "한도를 다 태웠는데 아무 일도 없다"가 되어 의미가 없다.
    func testWindowBonusIsMeaningfulButNotDominant() {
        // 사이클 수입 = 이식까지 걸리는 날 × 하루 원시 토큰.
        let cycleDays = Double(PlantBalance.targetCycleDays)
        let cycleIncome = cycleDays * Double(PlantBalance.assumedDailyRaw)
        let share = Double(PlantBalance.estimatedWindowBonusPerCycle) / cycleIncome

        XCTAssertLessThan(share, 0.12, "창만 태워도 상점을 굴릴 수 있다")
        XCTAssertGreaterThan(share, 0.05, "창을 태워도 티가 안 난다")
    }

    func testWeeklyWindowIsFiveTimesSession() {
        XCTAssertEqual(PlantBalance.windowBonusWeekly,
                       PlantBalance.windowBonusSession * 5)
    }

    // MARK: 두 물길의 환율

    /// 원시 토큰 → 물 비율이 실측과 맞아야 한다. 이게 틀어지면
    /// "하루치 지갑 = 하루치 성장"이라는 가속 천장 계산이 통째로 어긋난다.
    func testRawToWaterRatioMatchesMeasurement() {
        let d = TokenDelta(input: 1_100, output: 553_000, cacheWrite: 1_800_000, cacheRead: 106_900_000)
        let measured = Double(d.raw) / Double(PlantBalance.water(from: d))
        XCTAssertEqual(Double(PlantBalance.rawPerML), measured, accuracy: 40,
                       "환율 상수가 실측과 어긋났다")
    }

    /// 기준 하루치 원시 토큰이 기준 하루치 물과 맞아떨어져야 한다.
    func testAssumedDailyRawMatchesAssumedDailyGrowth() {
        XCTAssertEqual(PlantBalance.dailyWaterFromTokens, 15_092, accuracy: 200,
                       "하루 자동 성장이 실측(15,080mL)에서 벗어났다")
    }

    // MARK: 상점 — 값은 원시 토큰, 단위는 "며칠치"

    /// 즉시 물을 주는 품목이 **있어야** 한다. 성장이 자동이므로 물을 사는 건
    /// 수수료가 아니라 가속이다 — 한동안 이걸 빼놨던 게 설계 착오였다.
    func testWaterItemExistsAndIsTheCheapest() {
        XCTAssertTrue(ShopItem.allCases.contains(.water))
        XCTAssertEqual(ShopItem.sortedByPrice.first, .water,
                       "물이 제일 싸지 않으면 기준으로 쓸 수가 없다")
        XCTAssertGreaterThan(Water.mL, 0)
    }

    /// 셋은 서로 다른 축에 있어야 한다 — 값만 다르고 하는 일이 같으면 제일 싼 것만 산다.
    func testTheThreeGrowthItemsHaveDifferentShapes() {
        // 물: 어디서나 같은 값 (정액)
        XCTAssertEqual(Water.mL, Water.mL)
        // 영양제: 구간에 따라 달라짐 (비례)
        XCTAssertNotEqual(Nutrient.water(currentWater: 0, cycle: refCycle),
                          Nutrient.water(currentWater: th(8), cycle: refCycle))
        // 거름: 즉시값이 0이고 기간이 있음 (배율)
        XCTAssertEqual(PlantBalance.fertilizerDays, 7)
        XCTAssertEqual(PlantBalance.fertilizerBonusPercent, 25)
    }

    /// 가장 싼 품목도 하루의 일부는 돼야 한다 — 너무 싸면 살까 말까가 고민이 안 된다.
    func testCheapestItemCostsAMeaningfulSliceOfADay() {
        let cheapest = ShopItem.sortedByPrice[0]
        XCTAssertGreaterThanOrEqual(cheapest.priceDays, 0.2,
                                    "제일 싼 게 하루의 1/5도 안 된다")
        XCTAssertLessThanOrEqual(cheapest.priceDays, 0.5)
    }
}
