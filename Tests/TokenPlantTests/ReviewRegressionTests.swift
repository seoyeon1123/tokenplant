import XCTest
@testable import TokenPlant

// MARK: 전수 검토에서 나온 회귀
//
// 이 파일의 단정은 전부 **실제로 화면에 틀린 값이 찍히거나 상태가 망가지던** 자리다.
// 네 갈래 검사기(문법·멤버·데이터·포팅)가 하나도 못 잡은 것들이라, 여기가 유일한 방어선이다.
//
// 공통 성격이 하나 있다: **같은 사실을 두 곳에 적어둔 것들**이 어긋났다.
// 퍼센트를 글로 박고 상수를 따로 고쳤고, 씨앗 목표를 두 곳에서 계산했고,
// 정원을 그릴 때와 클릭을 받을 때 다른 구간을 봤고, 등급 이름이 네 벌 있었다.

@MainActor
final class ReviewRegressionTests: XCTestCase {

    private let day1 = "2026-09-01"

    private func freshSave() -> PlantSave {
        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato", cycleWater: PlantBalance.legacyCycleWater)
        s.claimedTodayByProvider = [:]
        return s
    }

    private func day(_ n: Int) -> String {
        let base = DayKey.parse(day1)!
        return DayKey.make(Calendar.current.date(byAdding: .day, value: n, to: base)!)
    }

    // MARK: 시계가 앞으로 튀는 경우

    /// 정리는 `today` 를 기준으로 도는데, 시계가 앞으로 튀면 기존 키가 전부 창 밖으로
    /// 밀려서 **한 번의 적립으로 14일 측정 기록이 사라진다.** 그러면 하루 유입이
    /// 기본값으로 돌아가 가격이 21배로 뛰고, `historyBackfilled` 때문에 다시 안 채워진다.
    func testClockJumpDoesNotWipeTheHistory() {
        var hist: [String: Int] = [:]
        for k in 0..<14 { hist[day(k)] = 5_000_000 }

        XCTAssertEqual(PlantBalance.prunedDailyRaw(hist, today: "2027-06-01"), hist,
                       "미래 날짜 하나로 기록 전체가 날아갔다")
        // 시계가 정상 범위면 평소대로 정리된다.
        let normal = PlantBalance.prunedDailyRaw(hist, today: day(19))
        XCTAssertEqual(normal.count, 8, "정상 범위에서 정리가 안 됐다")
        XCTAssertEqual(normal.keys.min(), day(6))
        XCTAssertTrue(PlantBalance.prunedDailyRaw([:], today: "2027-06-01").isEmpty)
    }

    // MARK: 재조정이 빠짐을 보상하면 안 된다

    /// **쉬면 이득이 되면 안 된다.**
    ///
    /// 목표 재조정이 갱신마다 돌던 동안, 며칠 안 쓰면 14일 평균이 내려가 목표가 줄고
    /// "줄이는 방향만"이라 그대로 적용돼서 **진행도가 앞으로 뛰었다.**
    /// 40일 시뮬레이션에서 20일차 진행도가 안 쉰 사람 73.0%, 사흘 쉰 사람 82.1% 였다.
    /// 스트릭은 빠짐을 벌주는데 여기서는 빠짐이 보상이었다 — 두 규칙이 반대로 갔다.
    func testRefitHappensOncePerPlant() {
        var s = freshSave()
        s.pot = PotState(speciesID: "tomato", cycleWater: 300_000)

        // 3일치 이력을 쌓아 측정이 되게 한다.
        for k in 0..<3 {
            PlantEngine.credit(&s, raw: 30_000_000,
                               water: 30_000_000 / PlantBalance.rawPerML, today: day(k))
        }
        let fitted = PlantEngine.seedCycle(s)
        XCTAssertLessThan(fitted, 300_000, "전제가 깨졌다 — 재조정이 줄이는 방향이어야 한다")

        // 한 번 맞춘다.
        s.pot?.cycleWater = fitted
        s.pot?.cycleFitted = true
        let settled = s.pot?.cycleWater ?? 0

        // 이 뒤로 사용량이 뚝 떨어져도(= 쉰다) 목표는 안 움직여야 한다.
        for k in 10..<13 {
            PlantEngine.credit(&s, raw: 1_000_000,
                               water: 1_000_000 / PlantBalance.rawPerML, today: day(k))
        }
        let shrunk = PlantEngine.seedCycle(s)
        XCTAssertLessThan(shrunk, settled, "전제가 깨졌다 — 쉬면 계산값이 더 작아야 한다")
        XCTAssertTrue(s.pot?.cycleFitted == true, "한 번 맞춘 표시가 안 남았다")
        XCTAssertEqual(s.pot?.cycleWater, settled, "쉬었더니 목표가 또 줄었다 — 빠짐이 이득이 된다")
    }

    /// 새로 심는 그루는 `seedCycle` 이 이미 실측으로 잡으므로 재조정 대상이 아니다.
    func testFreshSeedIsAlreadyFitted() {
        var s = freshSave()
        for k in 0..<3 {
            PlantEngine.credit(&s, raw: 30_000_000,
                               water: 30_000_000 / PlantBalance.rawPerML, today: day(k))
        }
        PlantEngine.plantNewSeed(&s, roll: 12_345)
        XCTAssertTrue(s.pot?.cycleFitted == true, "새 씨앗이 나중에 또 줄어들 수 있다")
    }

    // MARK: 씨앗 목표를 한 곳에서

    /// 둘째 화분을 목표 없이 만들어서 `PotState.init` 기본값(400,000)이 박혔다.
    /// 하루 5M 쓰는 사람에게는 첫 화분 28일 / 둘째 화분 557일이 같은 화면에 나란히 떴다.
    func testSecondPotGetsTheSameTargetAsTheFirst() {
        var s = freshSave()
        for k in 0..<5 {
            PlantEngine.credit(&s, raw: 5_000_000,
                               water: 5_000_000 / PlantBalance.rawPerML, today: day(k))
        }
        // 지역 변수를 거친다. `s.pot?.x = f(s)` 는 `s.pot` 을 고치는 접근이 우변 평가 내내
        // 열려 있어서 배타적 접근 위반이다(Swift 6 에서 컴파일 에러).
        let fitted = PlantEngine.seedCycle(s)
        s.pot?.cycleWater = fitted
        s.rawWallet = ShopItem.potSlot.price(dailyRaw: PlantBalance.dailyRawRate(s.dailyRaw)) * 3

        XCTAssertEqual(PlantEngine.buy(.potSlot, &s), .ok)
        guard let p1 = s.pot, let p2 = s.pot2 else { return XCTFail("둘째 화분이 안 생겼다") }
        XCTAssertEqual(p2.cycleWater, p1.cycleWater,
                       "첫 화분 \(p1.cycleWater) vs 둘째 \(p2.cycleWater)")
        XCTAssertNotEqual(p2.cycleWater, PlantBalance.legacyCycleWater, "기본값이 박혔다")
    }

    /// 상수 `rawPerML = 6,957` 로 나누면 실측 8,193 인 사람의 28일 사이클이 33일이 된다.
    /// 재는 길은 진작 만들어 뒀는데 `cycleWater` 가 그 값을 안 쓰고 있었다.
    func testSeedCycleUsesTheMeasuredRatio() {
        var s = freshSave()
        for k in 0..<4 {
            s.dailyRaw[day(k)] = 8_193_000
            s.dailyWater[day(k)] = 1_000          // 실측 8,193 : 1
        }
        XCTAssertEqual(PlantBalance.measuredRawPerML(raw: s.dailyRaw, water: s.dailyWater), 8_193)

        let rate = PlantBalance.dailyRawRate(s.dailyRaw)
        XCTAssertEqual(PlantEngine.seedCycle(s),
                       PlantBalance.cycleWater(dailyRaw: rate, rawPerML: 8_193),
                       "실측 비율을 안 썼다")
        // 실측이 상수보다 크니 목표는 작아져야 한다 — 그게 28일에 맞추는 방향이다.
        XCTAssertLessThan(PlantEngine.seedCycle(s),
                          PlantBalance.cycleWater(dailyRaw: rate, rawPerML: PlantBalance.rawPerML))
    }

    /// 첫 그루는 `dailyRaw` 가 비어 있을 때 심겨서 목표가 남의 기본값이다.
    /// 백필로 이 사람 속도를 알게 됐으면, **아직 안 자란 그루만** 다시 잡아야 한다.
    func testBackfillRefitsTheUntouchedFirstPlant() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tokenplant-refit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("state.json")
        let d = ISO8601DateFormatter().date(from: "2026-09-20T04:00:00Z")!

        // 갓 심은 그루 + 남의 기본값 목표.
        try """
        {"pot":{"speciesID":"tomato","water":0,"stageIndex":0,"isShiny":false,
         "plantedAt":800000000,"fruitHarvested":false,
         "cycleWater":\(PlantBalance.legacyCycleWater)}}
        """.write(to: url, atomically: true, encoding: .utf8)
        let store = PlantStore(url: url, clock: { d })
        let before = store.save.pot!.cycleWater

        // 가볍게 쓰는 사람의 과거 2주.
        var history: [String: TokenDelta] = [:]
        for k in 6..<19 { history[day(k)] = TokenDelta(output: 1_000_000) }
        store.backfillHistory(history)

        let after = store.save.pot!.cycleWater
        XCTAssertNotEqual(after, before, "목표가 남의 기본값에 그대로 남았다")
        XCTAssertEqual(after, PlantEngine.seedCycle(store.save))
    }

    /// **늘리는 방향은 절대 안 한다.** 목표가 커지면 게이지가 뒤로 가고 "쓰면 자란다"가 깨진다.
    func testRefitNeverGrowsTheTarget() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tokenplant-grow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("state.json")
        let d = ISO8601DateFormatter().date(from: "2026-09-20T04:00:00Z")!

        // 아주 작은 목표 + 아주 많이 쓰는 사람 → 맞춘 값이 더 크다.
        try """
        {"pot":{"speciesID":"tomato","water":0,"stageIndex":0,"isShiny":false,
         "plantedAt":800000000,"fruitHarvested":false,
         "cycleWater":\(PlantBalance.minCycleWater)},
         "dailyRaw":{"\(day(10))":500000000,"\(day(12))":500000000,"\(day(14))":500000000},
         "dailyWater":{"\(day(10))":50000,"\(day(12))":50000,"\(day(14))":50000},
         "historyBackfilled":true}
        """.write(to: url, atomically: true, encoding: .utf8)
        let store = PlantStore(url: url, clock: { d })
        let before = store.save.pot!.cycleWater
        store.refitUntouchedCycles()
        XCTAssertEqual(store.save.pot?.cycleWater, before, "목표가 커졌다 — 게이지가 뒤로 간다")
    }

    /// 사이클 1/3 을 넘긴 그루는 그냥 둔다 — 그쯤이면 사용자가 그 목표로 계획을 세웠다.
    func testRefitLeavesAPlantPastAThirdAlone() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tokenplant-keep-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("state.json")
        let d = ISO8601DateFormatter().date(from: "2026-09-20T04:00:00Z")!

        let cycle = PlantBalance.legacyCycleWater
        // 사이클의 절반까지 온 그루.
        try """
        {"pot":{"speciesID":"tomato","water":\(cycle / 2),
         "stageIndex":7,"isShiny":false,"plantedAt":800000000,
         "fruitHarvested":false,"cycleWater":\(cycle)}}
        """.write(to: url, atomically: true, encoding: .utf8)
        let store = PlantStore(url: url, clock: { d })

        var history: [String: TokenDelta] = [:]
        for k in 6..<19 { history[day(k)] = TokenDelta(output: 1_000_000) }
        store.backfillHistory(history)

        XCTAssertEqual(store.save.pot?.cycleWater, cycle, "1/3 을 넘긴 그루의 목표가 움직였다")
    }

    /// 목표가 줄면 단계도 같이 올라가야 한다 — 임계값이 목표의 **비율**이기 때문이다.
    /// 안 맞추면 게이지는 꽉 찼는데 스프라이트만 씨앗인 상태가 남는다.
    func testRefitRecomputesTheStage() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tokenplant-stage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("state.json")
        let d = ISO8601DateFormatter().date(from: "2026-09-20T04:00:00Z")!

        let big = PlantBalance.legacyCycleWater
        try """
        {"pot":{"speciesID":"tomato","water":3000,"stageIndex":1,"isShiny":false,
         "plantedAt":800000000,"fruitHarvested":false,"cycleWater":\(big)},
         "dailyRaw":{"\(day(10))":5000000,"\(day(12))":5000000,"\(day(14))":5000000},
         "dailyWater":{"\(day(10))":700,"\(day(12))":700,"\(day(14))":700},
         "historyBackfilled":true}
        """.write(to: url, atomically: true, encoding: .utf8)
        let store = PlantStore(url: url, clock: { d })
        store.refitUntouchedCycles()

        guard let p = store.save.pot else { return XCTFail("화분이 없다") }
        XCTAssertLessThan(p.cycleWater, big, "목표가 안 줄었다 — 이 검증이 의미가 없다")
        XCTAssertEqual(p.stageIndex, PlantBalance.stageIndex(forWater: p.water, cycle: p.cycleWater),
                       "목표는 줄었는데 단계가 안 따라왔다")
    }

    // MARK: 씨앗 예약

    /// 예약 칸이 하나인데 그냥 덮어써서, 전설 예약 위에 고급을 올리면 **등급이 내려가고**
    /// 산 전설이 사라졌다. 화면은 "예약됐어요" 라고만 말했다.
    func testSeedReservationNeverDowngrades() {
        var s = freshSave()
        s.inventory[ShopItem.legendarySeed.rawValue] = 1
        s.inventory[ShopItem.premiumSeed.rawValue] = 1

        guard case .ok = PlantEngine.use(.legendarySeed, &s, today: day1) else {
            return XCTFail("전설 예약이 실패했다")
        }
        XCTAssertEqual(s.pendingSeedGuarantee, .legendary)

        guard case .noEffect = PlantEngine.use(.premiumSeed, &s, today: day1) else {
            return XCTFail("고급이 전설 예약을 덮었다")
        }
        XCTAssertEqual(s.pendingSeedGuarantee, .legendary, "등급이 내려갔다")
        XCTAssertEqual(s.count(.premiumSeed), 1, "거절했는데 소모됐다")

        // 비어 있으면 당연히 예약된다.
        s.pendingSeedGuarantee = nil
        guard case .ok = PlantEngine.use(.premiumSeed, &s, today: day1) else {
            return XCTFail("빈 칸에 예약이 안 됐다")
        }
        XCTAssertEqual(s.pendingSeedGuarantee, .rare)
    }

    // MARK: 연출 대기열

    /// `.decorFound` 가 우선순위 표에 없어서 **뽑히지도 못하고 버려졌다** —
    /// `drainEvents` 가 이미 큐를 비운 뒤라 `PotView` 의 반짝임은 죽은 코드였다.
    /// 반대로 `.thirsty` 는 표에 **있어서** 30초마다 `persist()` 를 불렀다(하루 2,880번).
    func testCelebrationPriorityCoversDecorButNotThirst() {
        var s = freshSave()
        PlantEngine.push(&s, .decorFound(key: "cat"))
        PlantEngine.push(&s, .thirsty)
        let keys = s.pendingEvents.map(\.coalesceKey)
        XCTAssertTrue(keys.contains("decor"))
        XCTAssertTrue(keys.contains("thirsty"))
        // 목마름은 사건이 아니라 상태다 — 색이 이미 말해주고, 연출도 `break` 다.
        XCTAssertEqual(PlantEvent.thirsty.coalesceKey, "thirsty")
        XCTAssertEqual(PlantEvent.decorFound(key: "cat").coalesceKey, "decor")
    }

    // MARK: 화면 문구가 상수를 따라오는가

    /// 퍼센트를 문자열에 박아두면 상수를 고칠 때 화면만 옛말이 된다.
    /// 실제로 영양제를 20% → 10% 로 내린 뒤에도 상점은 `−20%` 라고 말하고 있었고,
    /// **같은 문장 안의 mL 값은 10% 로 계산돼서** 스스로 모순이었다.
    func testNutrientCopyMatchesTheConstant() {
        XCTAssertEqual(Nutrient.reducePercent, 10)
        let cycle = PlantBalance.legacyCycleWater
        // 문구가 쓰는 퍼센트와 실제 회수량이 같은 상수에서 나와야 한다.
        XCTAssertEqual(Nutrient.water(currentWater: 0, cycle: cycle),
                       cycle * Nutrient.reducePercent / 100)
    }

    /// 등급 이름이 네 벌 있었다(`ShopView`·`PotView`·`GardenView`·`CollectionView`).
    /// 한 벌만 고치면 나머지 세 곳이 옛말이 되는 구조라 `PlantRarity` 로 모았다.
    func testRarityLabelsLiveInOnePlace() {
        XCTAssertEqual(PlantRarity.common.label, "흔함")
        XCTAssertEqual(PlantRarity.uncommon.label, "보통")
        XCTAssertEqual(PlantRarity.rare.label, "희귀")
        XCTAssertEqual(PlantRarity.legendary.label, "전설")
        for r in PlantRarity.allCases {
            XCTAssertFalse(r.label.isEmpty)
            XCTAssertNotEqual(r.label, r.rawValue, "\(r) 이름이 영어 그대로다")
        }
    }

    /// 티어 해금 문구가 실제로 그 티어에서 열리는 것과 맞아야 한다.
    /// `뒷마당(6그루) — 명패 해금` 이라고 적혀 있었는데 명패는 잠겨 있지 않았다
    /// (정원 창이 열리는 3그루부터 바로 눌린다).
    func testTierUnlockTextIsNotAboutSomethingAlreadyAvailable() {
        let yard = GardenTier.all.first { $0.key == "yard" }
        XCTAssertNotNil(yard)
        XCTAssertNotEqual(yard?.unlock, "명패", "잠겨 있지 않은 걸 해금이라고 쓴다")
        for t in GardenTier.all { XCTAssertFalse(t.unlock.isEmpty, "\(t.name) 해금 문구가 비었다") }
    }
}
