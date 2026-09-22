import XCTest
@testable import TokenPlant

// MARK: 하루에 줄 수 있는 양
//
// 지갑은 계속 이월된다. 그래서 상한이 없으면 며칠 안 쓰고 모았다가 하루에 다 쏟을 수 있었고,
// 실제로 30일치를 모으면 **하루 만에** 한 사이클이 끝났다(물 98개). 4주짜리 사이클이
// 하루로 무너지면 나머지 설계가 전부 의미를 잃는다.
//
// "최대 2배"는 하루 **수입** 기준 평균이었지, 하루에 **쓸 수 있는 양**의 상한이 아니었다.
// 그 구분을 안 해둔 게 구멍이었다.

final class DailyCapTests: XCTestCase {

    private let day1 = "2026-09-01"
    private let day2 = "2026-09-02"

    private func freshSave() -> PlantSave {
        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato",
                         cycleWater: PlantBalance.cycleWater(dailyRaw: PlantBalance.assumedDailyRaw))
        return s
    }

    // MARK: 물 — 하루 5번

    func testWaterIsCappedAtFiveUsesPerDay() {
        var s = freshSave()
        s.inventory[ShopItem.water.rawValue] = 50

        var ok = 0
        for _ in 0..<50 {
            if case .ok = PlantEngine.use(.water, &s, today: day1) { ok += 1 }
        }
        XCTAssertEqual(ok, PlantBalance.dailyWaterUses, "하루에 \(ok)번 줬다")
    }

    /// 막힌 물은 **소모되면 안 된다.** 먼저 consume 하고 나서 막으면 산 물이 그냥 사라진다.
    func testBlockedWaterIsNotConsumed() {
        var s = freshSave()
        s.inventory[ShopItem.water.rawValue] = 10
        for _ in 0..<10 { _ = PlantEngine.use(.water, &s, today: day1) }
        XCTAssertEqual(s.count(.water), 10 - PlantBalance.dailyWaterUses,
                       "상한에 걸린 물이 소모됐다")
    }

    func testWaterAllowanceResetsNextDay() {
        var s = freshSave()
        s.inventory[ShopItem.water.rawValue] = 50
        for _ in 0..<50 { _ = PlantEngine.use(.water, &s, today: day1) }

        var ok = 0
        for _ in 0..<50 {
            if case .ok = PlantEngine.use(.water, &s, today: day2) { ok += 1 }
        }
        XCTAssertEqual(ok, PlantBalance.dailyWaterUses, "다음 날 상한이 안 풀렸다")
    }

    /// 막혔을 때 **이유**를 돌려줘야 한다. 회색 버튼만 두면 고장으로 읽힌다.
    func testBlockedWaterExplainsWhy() {
        var s = freshSave()
        s.inventory[ShopItem.water.rawValue] = 10
        for _ in 0..<PlantBalance.dailyWaterUses { _ = PlantEngine.use(.water, &s, today: day1) }

        guard case .noEffect(let reason) = PlantEngine.use(.water, &s, today: day1) else {
            return XCTFail("상한에 걸렸는데 막히지 않았다")
        }
        XCTAssertFalse(reason.isEmpty, "막은 이유가 비어 있다")
    }

    // MARK: 영양제 — 한 그루에 한 번

    /// 비례 품목이라 횟수로는 못 막는다. 갓 심었을 때 한 개가 자동 성장 5.6일치라,
    /// 물과 똑같이 "하루 5회"로 세면 영양제만 다섯 번 써서 나흘 만에 끝난다.
    func testNutrientIsOncePerPlant() {
        var s = freshSave()
        s.inventory[ShopItem.nutrient.rawValue] = 5

        guard case .ok = PlantEngine.use(.nutrient, &s, today: day1) else {
            return XCTFail("첫 영양제가 안 들어갔다")
        }
        if case .ok = PlantEngine.use(.nutrient, &s, today: day1) {
            XCTFail("같은 그루에 두 번 들어갔다")
        }
        // 날이 바뀌어도 안 된다 — 그루 기준이지 날짜 기준이 아니다.
        if case .ok = PlantEngine.use(.nutrient, &s, today: day2) {
            XCTFail("날이 바뀌니 같은 그루에 또 들어갔다")
        }
        XCTAssertEqual(s.count(.nutrient), 4, "막힌 영양제가 소모됐다")
    }

    /// 그루에 기록하므로 이식하면 저절로 풀려야 한다.
    func testNutrientAllowanceResetsOnTransplant() {
        var s = freshSave()
        s.inventory[ShopItem.nutrient.rawValue] = 3
        _ = PlantEngine.use(.nutrient, &s, today: day1)

        PlantEngine.applyWater(&s, mL: s.pot!.cycleWater, today: day1)
        XCTAssertTrue(PlantEngine.transplant(&s, roll: 7), "이식이 안 됐다")

        guard case .ok = PlantEngine.use(.nutrient, &s, today: day1) else {
            return XCTFail("새 그루인데 영양제가 막혔다")
        }
    }

    // MARK: 구멍이 막혔나

    /// 30일치를 모아 새 화분에 쏟아도 하루 만에 끝나면 안 된다.
    func testHoardingCannotCollapseTheCycle() {
        var s = freshSave()
        // 한 달치 지갑. 이월되므로 실제로 이만큼 모을 수 있다.
        s.rawWallet = PlantBalance.assumedDailyRaw * 30

        var poured = 0
        while PlantEngine.buy(.water, &s) == .ok {
            guard case .ok = PlantEngine.use(.water, &s, today: day1) else { break }
            poured += 1
        }
        XCTAssertEqual(poured, PlantBalance.dailyWaterUses, "하루에 물 \(poured)개가 들어갔다")
        XCTAssertFalse(s.pot!.isReadyToTransplant, "하루 만에 이식 가능해졌다 — 사이클이 무너진다")
    }

    /// 하루 상한까지 부어도 **하루 자동 성장량의 40%** 다. 예전엔 100% 였다(5개).
    ///
    /// 100% 라는 건 곧 유입 전부를 물로 쓴다는 뜻이고, 그러면 지갑이 영원히 0이라
    /// 상점이 존재하지 않는 것과 같다. 40% 로 내려서 60% 가 남게 했다 —
    /// 잃은 건 가속 0.6배, 얻은 건 상점 전체다.
    func testCapSpendsOnlyPartOfADaysIncome() {
        let rate = PlantBalance.assumedDailyRaw
        let auto = PlantBalance.dailyWaterFromTokens
        let bought = Water.mL(dailyRaw: rate) * PlantBalance.dailyWaterUses
        let share = Double(bought) / Double(auto)
        XCTAssertEqual(share, 0.4, accuracy: 0.05,
                       "상한까지 부으면 하루 자동 성장의 \(Int(share * 100))% 다")
        XCTAssertLessThan(share, 0.6, "유입의 절반 이상이 물로 나가면 지갑이 안 쌓인다")
    }

    /// 상한이 지갑을 태우면 안 된다 — 못 준 물은 다음 날로 밀릴 뿐이어야 한다.
    func testUnusedAllowanceDoesNotBurnTheWallet() {
        var s = freshSave()
        s.rawWallet = PlantBalance.assumedDailyRaw * 10
        s.inventory[ShopItem.water.rawValue] = 20
        let before = s.rawWallet
        for _ in 0..<20 { _ = PlantEngine.use(.water, &s, today: day1) }
        XCTAssertEqual(s.rawWallet, before, "상한에 걸렸는데 지갑이 줄었다")
    }
}
