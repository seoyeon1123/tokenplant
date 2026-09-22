import XCTest
@testable import TokenPlant

// MARK: 기준선 · 실측 환산비율 · 설치 시 백필
//
// 화면에서 제일 큰 숫자 두 개가 여기서 나온다: "평소 대비 몇 %"와 "며칠치".
// 둘 다 **남의 평균**으로 계산되면 그 자리에서 거짓말이 된다.
//
// 이 파일이 지키는 것 셋:
//  1. 기준(평소)에 **오늘이 들어가면 안 된다** — 아침엔 오늘 몫이 0인데 분모는 오늘을
//     이미 하루로 세서, 오늘이 끌어내린 평균과 오늘을 견주게 된다. 늘 100% 근처가 된다.
//  2. 못 재면 **nil 로 물러난다** — 틀린 82% 는 아무 숫자도 안 쓴 것보다 나쁘다.
//  3. 백필은 **재기만 한다** — 과거 로그로 적립까지 하면 설치하자마자 첫 화면이 거목이 된다.

@MainActor
final class BaselineTests: XCTestCase {

    private let day1 = "2026-09-01"
    private let day2 = "2026-09-02"
    private let day3 = "2026-09-03"
    private let day4 = "2026-09-04"

    private lazy var dir: URL = {
        let d = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tokenplant-base-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: d) }
        return d
    }()

    private var url: URL { dir.appendingPathComponent("state.json") }

    private func makeStore(_ iso: String = "2026-09-04T04:00:00Z") -> PlantStore {
        let d = ISO8601DateFormatter().date(from: iso)!
        return PlantStore(url: url, clock: { d })
    }

    /// `save` 는 `private(set)` 이라 바깥에서 못 쓴다 — 저장 파일을 직접 깔고 읽게 한다.
    /// 우회로가 아니라 실제 경로다: 앱이 껐다 켰을 때 지나는 길이 이 길이다.
    private func seed(_ json: String, at iso: String = "2026-09-04T04:00:00Z") throws -> PlantStore {
        try json.write(to: url, atomically: true, encoding: .utf8)
        return makeStore(iso)
    }

    private static let cycle = PlantBalance.legacyCycleWater

    private func potJSON(_ id: String = "tomato", water: Int = 0, stage: Int = 0) -> String {
        """
        {"speciesID":"\(id)","water":\(water),"stageIndex":\(stage),"isShiny":false,
         "plantedAt":800000000,"fruitHarvested":false,"cycleWater":\(Self.cycle)}
        """
    }

    // MARK: 기준선

    /// 기준에서 오늘을 뺀다. 가격 환산용 평균(`dailyRawRate`)은 반대로 오늘을 포함해야 한다 —
    /// 그건 "지금 이 순간 하루치가 얼마인가"라서 오늘이 빠지면 안 된다. 두 값은 쓰임이 다르다.
    func testBaselineExcludesToday() {
        let daily = [day1: 30_000, day2: 30_000, day3: 30_000, day4: 300]
        XCTAssertEqual(PlantBalance.baselineRawRate(daily, today: day4), 30_000,
                       "오늘이 기준에 섞였다")
        XCTAssertEqual(PlantBalance.dailyRawRate(daily), 90_300 / 4,
                       "가격 환산용 평균은 오늘을 포함해야 한다")
    }

    /// 표본이 얇으면 nil. 화면은 그때 퍼센트를 **아예 안 쓰고** "평소를 재는 중 · N일째"로 바꾼다.
    func testBaselineIsNilUntilThereIsEnoughPast() {
        XCTAssertNil(PlantBalance.baselineRawRate([:], today: day3))
        XCTAssertNil(PlantBalance.baselineRawRate([day3: 50_000], today: day3),
                     "오늘뿐인데 기준을 냈다")
        XCTAssertNil(PlantBalance.baselineRawRate([day2: 10_000, day3: 10_000], today: day3),
                     "과거 이틀치로 기준을 냈다")
    }

    /// 안 쓴 날도 0으로 센다. 빼고 평균을 내면 "평소"가 부풀어서,
    /// 실제로 평소만큼 쓴 날이 60% 로 보인다.
    func testBaselineCountsIdleDaysAsZero() {
        XCTAssertEqual(PlantBalance.baselineRawRate([day1: 30_000, day3: 0, day4: 0], today: day4),
                       10_000)
    }

    /// 며칠이 쌓였는지도 오늘을 뺀 기준으로 센다 — 화면의 "2일째"가 이 값이다.
    func testCollectedDaysMatchesTheBaselineWindow() throws {
        let store = try seed("""
        {"pot":\(potJSON()),
         "dailyRaw":{"\(day1)":1,"\(day3)":1,"\(day4)":999},"historyBackfilled":true}
        """)
        XCTAssertEqual(store.baselineDaysCollected, 3, "오늘이 며칠째에 섞였다")
        XCTAssertNotNil(store.baselineRate)
        XCTAssertNotNil(store.todayVsBaseline)
    }

    // MARK: 실측 환산비율

    /// 겹치는 날로만 나눈다. 원시만 있는 날이 섞이면 비율이 부풀고,
    /// 사이클 목표가 그 값으로 계산되므로 28일이어야 할 게 33일이 된다.
    func testMeasuredRatioOnlyUsesOverlappingDays() {
        let raw = [day1: 999_999, day2: 80_000, day3: 80_000, day4: 80_000]
        let water = [day2: 10, day3: 10, day4: 10]
        XCTAssertEqual(PlantBalance.measuredRawPerML(raw: raw, water: water), 8_000,
                       "겹치지 않는 날이 섞였다")
    }

    /// 못 재는 경우는 전부 nil — 화면은 그때 상수로 물러난다.
    func testMeasuredRatioNeedsBothSides() {
        let raw = [day1: 80_000, day2: 80_000, day3: 80_000]
        XCTAssertEqual(PlantBalance.measuredRawPerML(raw: raw,
                                                     water: [day1: 10, day2: 10, day3: 10]), 8_000)
        XCTAssertNil(PlantBalance.measuredRawPerML(raw: raw, water: [day1: 10]),
                     "한 날로 비율을 냈다")
        XCTAssertNil(PlantBalance.measuredRawPerML(raw: raw, water: [day1: 0, day2: 0, day3: 0]),
                     "0 으로 나눴다")
        XCTAssertNil(PlantBalance.measuredRawPerML(raw: [:], water: [day1: 10, day2: 10, day3: 10]))
    }

    /// 분모는 **보너스를 먹이기 전** 값이어야 한다.
    /// 스트릭·거름이 섞이면 환산비율이 아니라 "요즘 보너스가 얼마나 붙었나"를 재게 된다.
    func testCreditRecordsWaterBeforeBonuses() {
        var save = PlantSave()
        save.pot = PotState(speciesID: "tomato", cycleWater: Self.cycle)
        save.streakDays = 25
        save.lastUseDay = day1

        PlantEngine.credit(&save, raw: 81_930, water: 10, today: day1)

        XCTAssertEqual(save.dailyWater, [day1: 10], "보너스 먹인 값이 통계에 들어갔다")
        XCTAssertGreaterThan(save.pot?.water ?? 0, 10, "성장에는 보너스가 붙어야 한다")
    }

    // MARK: 백필

    /// 과거 로그로 **통계만** 채운다. 지갑·성장·스트릭은 그대로다.
    func testBackfillMeasuresWithoutPaying() throws {
        let store = try seed("""
        {"pot":\(potJSON()),"rawWallet":0,"rawSinceInstall":0}
        """)
        let history: [String: TokenDelta] = [
            day1: TokenDelta(output: 100_000, cacheRead: 10_000_000),
            day2: TokenDelta(output: 100_000, cacheRead: 10_000_000),
        ]
        XCTAssertTrue(store.needsBackfill)
        store.backfillHistory(history)

        XCTAssertEqual(store.save.rawWallet, 0, "백필이 지갑에 적립했다")
        XCTAssertEqual(store.save.pot?.water, 0, "백필이 성장을 밀었다")
        XCTAssertEqual(store.save.streakDays, 0, "백필이 스트릭을 올렸다")
        XCTAssertEqual(store.save.dailyRaw.keys.sorted(), [day1, day2],
                       "통계가 날짜별로 안 들어갔다")
        XCTAssertTrue(store.save.dailyWater.values.allSatisfy { $0 > 0 }, "환산 분모가 비었다")
    }

    /// 한 번만. 매 실행마다 돌면 같은 날이 두 번 세어져 하루 유입이 배로 부푼다.
    func testBackfillRunsOnlyOnce() throws {
        let store = try seed("""
        {"pot":\(potJSON())}
        """)
        store.backfillHistory([day1: TokenDelta(output: 100_000)])
        let before = store.save.dailyRaw
        XCTAssertFalse(store.needsBackfill)
        store.backfillHistory([day1: TokenDelta(output: 999_999)])
        XCTAssertEqual(store.save.dailyRaw, before, "두 번 세어져 하루 유입이 두 배가 됐다")
    }

    /// 창 밖(14일 초과) 기록은 버린다 — 세이브에 1년치가 쌓이면 읽고 쓰는 비용이 계속 는다.
    func testBackfillDropsDaysOutsideTheWindow() throws {
        // 오늘은 `ingest` 몫이라 백필이 건너뛴다(안 그러면 같은 날이 두 번 세어진다).
        // 그래서 시계를 day3 에 두고 과거 키로만 검증한다.
        let store = try seed("""
        {"pot":\(potJSON())}
        """, at: "2026-09-03T04:00:00Z")
        store.backfillHistory(["2026-08-01": TokenDelta(output: 100_000),
                               day1: TokenDelta(output: 100_000)])
        XCTAssertEqual(store.save.dailyRaw.keys.sorted(), [day1], "창 밖 기록이 남았다")
    }

    /// 백필은 **오늘을 건너뛴다.** `readRecent` 가 오늘을 포함해 돌려주는데 `ingest` 도
    /// 오늘을 적립하므로, 넣으면 하루 유입이 7% 부풀고 그 값이 14일 동안
    /// 모든 가격과 다음 사이클 목표에 들어간다.
    func testBackfillSkipsToday() throws {
        let store = try seed("""
        {"pot":\(potJSON())}
        """, at: "2026-09-03T04:00:00Z")
        store.backfillHistory([day1: TokenDelta(output: 10_000_000),
                               day2: TokenDelta(output: 10_000_000),
                               day3: TokenDelta(output: 10_000_000)])   // day3 == today
        XCTAssertEqual(store.save.dailyRaw.keys.sorted(), [day1, day2], "오늘이 백필에 들어갔다")
    }

    // MARK: 지갑 설명 줄

    /// 다음 목표에서 **장식을 뺀다.** 벤치가 1일치라 늘 제일 먼저 걸리는데,
    /// 성장에 아무 도움이 안 되는 걸 목표로 걸어주면 "저걸 모아봐야 뭐하나"가 된다.
    func testNextGoalSkipsDecorations() throws {
        // 물은 살 수 있고 벤치(1일치)는 못 사는 잔액.
        let store = try seed("""
        {"pot":\(potJSON()),"rawWallet":\(PlantBalance.assumedDailyRaw / 2)}
        """)
        guard let goal = store.nextGoal else { return XCTFail("목표가 없다") }
        XCTAssertFalse(goal.item.isDecoration, "장식(\(goal.item.name))이 목표로 걸렸다")
        XCTAssertEqual(goal.item, .fertilizer, "장식 다음으로 싼 성장 품목이 아니다")
    }

    /// **실제로 화면에 거짓말이 찍혔던 자리다.**
    ///
    /// 예전엔 번 것을 `rawSinceInstall`(로그가 말한 양)로, 쓴 것을 `rawSinceInstall − 지갑`
    /// 으로 뺐다. 첫날은 상한에 걸려 지갑에 일부만 들어오는데 `rawSinceInstall` 에는
    /// 전부 들어간다 — 그 차액이 영원히 "쓴 것"으로 찍혀서, 한 번도 안 산 사람에게도
    /// 지출이 보였다. 그래서 장부를 지갑이 오르는 자리와 내리는 자리에서 각각 센다.
    func testLedgerBalancesAfterTheFirstDayCap() {
        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato", cycleWater: PlantBalance.legacyCycleWater)
        // 첫날 로그가 하루치의 10배 — 상한에 확실히 걸린다.
        let big = ["claude": TokenDelta(output: PlantBalance.assumedDailyRaw * 10)]
        PlantEngine.ingest(&s, todayByProvider: big, today: day1)

        XCTAssertGreaterThan(s.rawSinceInstall, s.rawWallet,
                             "첫날 상한이 안 걸렸다 — 이 검증이 의미가 없다")
        XCTAssertEqual(s.rawSpentTotal, 0, "아무것도 안 샀는데 쓴 것이 있다")
        XCTAssertEqual(s.rawEarnedTotal - s.rawSpentTotal, s.rawWallet, "번 것 − 쓴 것 ≠ 지갑")
    }

    /// 적립 · 창 보너스 · 구매를 섞어도 셋이 계속 맞아야 한다.
    /// 지갑이 움직이는 자리를 하나라도 빠뜨리면 여기서 걸린다.
    func testLedgerBalancesAcrossEveryPath() throws {
        let purse = 20 * ShopItem.water.price(dailyRaw: PlantBalance.assumedDailyRaw)
        let store = try seed("""
        {"pot":\(potJSON()),"rawWallet":\(purse),"rawSinceInstall":\(purse),
         "rawEarnedTotal":\(purse),"rawSpentTotal":0,"claimedTodayByProvider":{}}
        """)
        XCTAssertTrue(store.ledgerBalances, "시작부터 장부가 안 맞는다")

        XCTAssertEqual(store.buy(.water), .ok)
        XCTAssertEqual(store.buy(.water), .ok)
        XCTAssertTrue(store.ledgerBalances, "구매 뒤 장부가 안 맞는다")
        XCTAssertEqual(store.spentTotal, 2 * store.price(.water), "쓴 것이 구매 합계와 다르다")

        store.update(todayUsageByProvider: ["claude": TokenDelta(output: 1_000_000)],
                     todayDate: "2026-09-04")
        XCTAssertTrue(store.ledgerBalances, "적립 뒤 장부가 안 맞는다")
    }

    /// 화면이 "번 것 − 쓴 것 = 지갑"을 그대로 보여주므로 그 뺄셈이 실제로 맞아야 한다.
    /// 창 보너스도 누적에 얹는 이유가 이것이다 — 지갑에만 넣으면 그만큼 어긋난다.
    func testWalletIsEarnedMinusSpent() throws {
        let purse = 10 * ShopItem.water.price(dailyRaw: PlantBalance.assumedDailyRaw)
        let store = try seed("""
        {"pot":\(potJSON()),"rawWallet":\(purse),"rawSinceInstall":\(purse)}
        """)
        let earned = store.earnedTotal
        XCTAssertGreaterThan(earned, store.price(.water), "물값보다 적은 잔액으로 시작했다")

        XCTAssertEqual(store.buy(.water), .ok)
        XCTAssertEqual(store.earnedTotal, earned, "번 것이 구매로 줄었다")
        XCTAssertEqual(store.spentTotal, store.price(.water), "쓴 것이 값과 안 맞는다")
        XCTAssertEqual(store.save.rawWallet, store.earnedTotal - store.spentTotal,
                       "지갑 = 번 것 − 쓴 것 이 아니다")
    }
}
