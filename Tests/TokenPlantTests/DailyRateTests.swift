import XCTest
@testable import TokenPlant

// MARK: 기준 — 상점의 모든 큰 숫자가 여기를 지난다
//
// 이 파일이 지키는 것 하나: **숫자에는 단위가 붙어야 한다.**
//
// `157,500,000` 만 띄우면 하루만 모으면 되는 건지 한 달을 써야 하는 건지 알 수가 없다.
// 그러면 상점은 "영영 못 사는 곳"으로 읽힌다. 실제로 그렇게 됐다 —
// 전 품목에 `19,848 부족` 만 뜨는 화면을 보고 "이게 뭔지를 모르겠다"는 말이 나왔다.
//
// 그래서 값을 **일**로 정하고 토큰 수를 파생값으로 뒀다. 그리고 환산의 분모(하루 유입)를
// 상수로 박지 않고 앱이 직접 잰다 — 사람마다 하루 유입이 10배씩 다르므로,
// 남의 평균으로 "1.3일치"라고 쓰면 그건 그냥 거짓말이다.

final class DailyRateTests: XCTestCase {

    private let day1 = "2026-09-01"
    private let day2 = "2026-09-02"
    private let day3 = "2026-09-03"

    private func freshSave() -> PlantSave {
        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato")
        s.claimedTodayByProvider = [:]
        return s
    }

    // MARK: 측정

    /// 표본이 얇으면 측정값을 안 믿고 기본값으로 물러난다.
    ///
    /// 하루치로 평균을 내면 그날이 무거웠는지 가벼웠는지에 따라 환산이 11배 튄다
    /// (실측 중위 7,552 · 최대 83,717). 틀린 "0.2일치"는 아무 숫자도 안 쓴 것보다 나쁘다.
    func testRateFallsBackUntilThereIsEnoughData() {
        XCTAssertEqual(PlantBalance.dailyRawRate([:]), PlantBalance.assumedDailyRaw)
        XCTAssertEqual(PlantBalance.dailyRawRate([day1: 90_000]), PlantBalance.assumedDailyRaw,
                       "하루치로 평균을 냈다")
        XCTAssertEqual(PlantBalance.dailyRawRate([day1: 90_000, day2: 0]),
                       PlantBalance.assumedDailyRaw, "이틀치로 평균을 냈다")
    }

    /// **달력일** 평균이어야 한다 — 안 쓴 날도 0으로 센다.
    ///
    /// 활동일만 세면 실제보다 빠른 속도가 나오고, "1.3일치"가 실제로는 사흘이 된다.
    /// 아끼면 살 수 있다는 약속이 거기서 깨진다.
    func testRateIsCalendarAverageIncludingIdleDays() {
        XCTAssertEqual(PlantBalance.dailyRawRate([day1: 30_000, day3: 0]), 10_000)
        XCTAssertEqual(PlantBalance.dailyRawRate([day1: 10_000, day2: 10_000, day3: 10_000]), 10_000)
    }

    /// 창(14일) 밖은 버린다. 세이브에 1년치가 쌓이면 읽고 쓰는 비용이 계속 늘고,
    /// 반년 전 습관이 오늘의 환산에 섞인다.
    func testWindowDropsOldDaysAndKeepsRecentOnes() {
        let old = "2026-08-20"
        let pruned = PlantBalance.prunedDailyRaw([old: 99_999, day1: 10_000], today: day3)
        XCTAssertEqual(pruned, [day1: 10_000], "14일 밖이 남았다")

        let kept = PlantBalance.prunedDailyRaw([day1: 1, day2: 1, day3: 1], today: day3)
        XCTAssertEqual(kept.count, 3, "창 안쪽이 버려졌다")
    }

    /// 같은 날 유입은 합산된다.
    func testCreditAccumulatesWithinADay() {
        var s = freshSave()
        PlantEngine.credit(&s, raw: 5_000, water: 1, today: day1)
        PlantEngine.credit(&s, raw: 3_000, water: 1, today: day1)
        XCTAssertEqual(s.dailyRaw, [day1: 8_000], "같은 날 유입이 합산되지 않았다")
        XCTAssertEqual(s.rawWallet, 8_000)
    }

    /// 오래 안 쓰다 돌아와도 기록이 무한정 쌓이지 않는다.
    func testDailyRawDoesNotGrowForever() {
        var s = freshSave()
        PlantEngine.credit(&s, raw: 1_000, water: 1, today: "2026-08-20")
        PlantEngine.credit(&s, raw: 1_000, water: 1, today: "2026-09-10")
        XCTAssertEqual(Array(s.dailyRaw.keys), ["2026-09-10"], "창 밖 기록이 안 지워졌다")
    }

    /// 세이브를 왕복해도 측정이 남아야 한다 — 재시작마다 기본값으로 돌아가면 영영 측정이 안 된다.
    func testDailyRawSurvivesSaveRoundTrip() throws {
        var s = freshSave()
        PlantEngine.credit(&s, raw: 12_345, water: 1, today: day1)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(PlantSave.self, from: data)
        XCTAssertEqual(back.dailyRaw, [day1: 12_345])
    }

    // MARK: 가격 — 일이 먼저, 토큰 수는 파생값

    func testPriceIsDerivedFromDays() {
        for item in ShopItem.allCases {
            XCTAssertEqual(item.price,
                           Int(item.priceDays * Double(PlantBalance.assumedDailyRaw)),
                           "\(item.name) 가격이 일수와 안 맞는다")
        }
    }

    /// 제일 싼 건 물(0.2일). 장식 최저가는 하루다 —
    /// 하루도 못 모을 만큼 비싸면 상점이 닫힌 것과 같다.
    func testCheapestItemsAreWithinADay() {
        XCTAssertEqual(ShopItem.sortedByPrice[0], .water)
        XCTAssertEqual(ShopItem.water.priceDays, 0.2)
        XCTAssertEqual(ShopItem.bench.priceDays, 1)
    }

    /// 사이클보다 비싼 품목이 있으면 한 그루를 통째로 포기해도 못 산다.
    func testNoItemCostsMoreThanAWholeCycle() {
        let cycleDays = Double(PlantBalance.targetCycleDays)
        for item in ShopItem.allCases {
            XCTAssertLessThan(item.priceDays, cycleDays,
                              "\(item.name) 이 사이클(\(Int(cycleDays))일)보다 비싸다")
        }
    }

    /// 며칠치 환산이 가격표를 그대로 되읽어야 한다 — 화면에 쓰는 값이 이 함수다.
    func testDayConversionReadsBackAsThePriceTable() {
        for item in ShopItem.allCases {
            let d = PlantBalance.days(forRaw: item.price, rate: PlantBalance.assumedDailyRaw)
            XCTAssertEqual(d, item.priceDays, accuracy: 0.001, "\(item.name)")
        }
    }

    /// 하루 유입이 절반이면 같은 값이 두 배 오래 걸린다 — 환산이 자기 속도를 따라야 한다.
    func testConversionFollowsTheMeasuredRateNotTheDefault() {
        let half = PlantBalance.assumedDailyRaw / 2
        XCTAssertEqual(PlantBalance.days(forRaw: ShopItem.bench.price, rate: half),
                       2, accuracy: 0.001)
    }
}
