import XCTest
@testable import TokenPlant

// MARK: 사용자 시나리오 점검에서 나온 것들
//
// 테스트 311개가 다 통과하는 동안 실제 사용자가 겪을 수 있던 것들이다.
// 공통점: 테스트는 "이력을 먼저 쌓고", "시계는 앞으로만", "세이브는 멀쩡하게" 두었다.

/// 날짜를 바꿔 가며 스토어를 굴리기 위한 시계.
private final class Clock: @unchecked Sendable {
    var now: Date
    init(_ day: String) { now = DayKey.parse(day)!.addingTimeInterval(12 * 3_600) }
    func set(_ day: String) { now = DayKey.parse(day)!.addingTimeInterval(12 * 3_600) }
}

private func tempURL(_ tag: String) -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("tokenplant-\(tag)-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("state.json")
}

// MARK: 첫 그루 목표

@MainActor
final class FirstSeedTargetTests: XCTestCase {

    /// 설치 직후엔 이력이 없어 첫 그루 목표가 기본값(하루 105M)으로 잡힌다.
    /// 예전엔 그 값에도 `cycleFitted = true` 가 찍혀 재조정이 영영 안 돌았고,
    /// 하루 5M 쓰는 사람의 첫 그루가 이식까지 538일이었다.
    func testFirstSeedIsRefittedOnceUsageIsMeasured() throws {
        let url = tempURL("firstseed")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let clock = Clock("2026-09-01")
        let store = PlantStore(url: url, clock: { clock.now })
        let initial = try XCTUnwrap(store.save.pot)
        XCTAssertFalse(initial.cycleFitted, "기본값으로 잡은 목표에 '맞춤 완료' 표시가 붙었다")

        // 설치일 기준선 → 사흘 동안 하루 5M.
        store.update(todayUsageByProvider: [:], todayDate: "2026-09-01")
        for day in ["2026-09-01", "2026-09-02", "2026-09-03"] {
            clock.set(day)
            store.update(todayUsageByProvider: ["claude": TokenDelta(output: 1_000_000, cacheRead: 4_000_000)],
                         todayDate: day)
        }
        clock.set("2026-09-04")
        store.update(todayUsageByProvider: [:], todayDate: "2026-09-04")

        let pot = try XCTUnwrap(store.save.pot)
        XCTAssertTrue(pot.cycleFitted)
        XCTAssertLessThan(pot.cycleWater, initial.cycleWater,
                          "하루 5M 사용자의 목표가 기본값 그대로다 — 첫 그루가 완주하지 못한다")
        // 이 사람 하루 물로 4주 안팎이어야 한다.
        let perDay = PlantBalance.water(from: TokenDelta(output: 1_000_000, cacheRead: 4_000_000))
        let days = Double(pot.cycleWater) / Double(perDay)
        XCTAssertTrue((20...40).contains(days), "목표가 \(days)일치다")

        // 저장도 됐어야 한다 — 재조정이 persist 뒤에 불리면 다음 갱신까지 파일에 안 남는다.
        let reloaded = PlantStore(url: url, clock: { clock.now })
        XCTAssertEqual(reloaded.save.pot?.cycleWater, pot.cycleWater)
    }

    /// 판정은 그루당 한 번이다. 줄이지 않기로 했어도 표시가 남아야, 며칠 쉬어 평균이 내려간 날
    /// 다시 와서 목표가 줄지 않는다.
    func testRefitDecisionIsMadeOnlyOnce() {
        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato", water: 0, cycleWater: 50_000, cycleFitted: false)
        s.claimedTodayByProvider = [:]
        let url = tempURL("refit-once")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? JSONEncoder().encode(s).write(to: url)
        let clock = Clock("2026-09-10")
        let store = PlantStore(url: url, clock: { clock.now })
        // 하루 200M — 측정된 목표가 지금(50,000)보다 커서 줄이지 않는다.
        for day in ["2026-09-06", "2026-09-07", "2026-09-08", "2026-09-09"] {
            store.update(todayUsageByProvider: [:], todayDate: day)
            store.update(todayUsageByProvider: ["claude": TokenDelta(output: 40_000_000,
                                                                     cacheRead: 160_000_000)],
                         todayDate: day)
        }
        store.update(todayUsageByProvider: [:], todayDate: "2026-09-10")
        XCTAssertEqual(store.save.pot?.cycleWater, 50_000)
        XCTAssertEqual(store.save.pot?.cycleFitted, true, "판정 기회가 남아 있다 — 쉬면 목표가 줄어든다")
    }
}

// MARK: 시계 되돌림 · 서쪽 비행

final class ClockBackwardsTests: XCTestCase {

    private func seeded() -> PlantSave {
        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato", cycleWater: 1_000_000)
        s.claimedTodayByProvider = [:]
        s.lastDate = "2026-09-28"
        return s
    }

    /// 되돌렸다가 돌아와도 같은 날이 두 번 적립되면 안 된다.
    /// 예전엔 51M 쓴 날이 한 번 왕복으로 지갑 153M 이 됐다.
    func testGoingBackAndForthDoesNotCreditTwice() {
        var s = seeded()
        let today = ["claude": TokenDelta(output: 1_000_000, cacheRead: 50_000_000)]
        PlantEngine.ingest(&s, todayByProvider: today, today: "2026-09-28")
        XCTAssertEqual(s.rawWallet, 51_000_000)

        // 어제로 — 어제 로그는 이미 지난 사용량이다. 적립하지 않는다.
        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(output: 2_000_000,
                                                                      cacheRead: 90_000_000)],
                           today: "2026-09-27")
        XCTAssertEqual(s.rawWallet, 51_000_000, "지난날 로그가 소급 적립됐다")

        // 제자리로 — 이어서 센다.
        PlantEngine.ingest(&s, todayByProvider: today, today: "2026-09-28")
        XCTAssertEqual(s.rawWallet, 51_000_000, "돌아온 날의 누적이 다시 적립됐다")
        let more = ["claude": TokenDelta(output: 1_000_000, cacheRead: 51_000_000)]
        PlantEngine.ingest(&s, todayByProvider: more, today: "2026-09-28")
        XCTAssertEqual(s.rawWallet, 52_000_000)
    }

    /// 시계가 미래로 튀었다가 바로잡혀도 적립이 멈추거나 두 번 들어가면 안 된다.
    func testForwardJumpThenCorrectionResumes() {
        var s = seeded()
        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(output: 10)], today: "2026-09-28")
        PlantEngine.ingest(&s, todayByProvider: [:], today: "2026-10-20")          // 잘못된 시계
        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(output: 10)], today: "2026-09-28")
        XCTAssertEqual(s.rawWallet, 10)
        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(output: 25)], today: "2026-09-28")
        XCTAssertEqual(s.rawWallet, 25, "바로잡은 뒤로 적립이 멈췄다")
    }

    /// 날짜가 뒤로 가도 스트릭이 끊기면 안 된다.
    func testStreakSurvivesClockGoingBack() {
        var s = seeded()
        s.lastDate = "2026-09-26"
        for d in ["2026-09-26", "2026-09-27", "2026-09-28"] {
            PlantEngine.ingest(&s, todayByProvider: [:], today: d)
            PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(output: 100)], today: d)
        }
        XCTAssertEqual(s.streakDays, 3)
        PlantEngine.ingest(&s, todayByProvider: [:], today: "2026-09-27")
        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(output: 200)], today: "2026-09-27")
        XCTAssertEqual(s.streakDays, 3, "시계를 하루 되돌렸더니 스트릭이 1로 끊겼다")
    }

    /// 하루 물 횟수는 날짜가 **앞으로** 갈 때만 되돌아간다.
    func testWaterAllowanceIsNotRefilledByClockBack() {
        var s = seeded()
        s.inventory[ShopItem.water.rawValue] = 5
        s.waterUseDay = "2026-09-28"
        s.waterUsesToday = PlantBalance.dailyWaterUses
        XCTAssertEqual(PlantEngine.waterUsesLeft(s, today: "2026-09-27"), 0)
        if case .ok = PlantEngine.use(.water, &s, today: "2026-09-27") {
            XCTFail("시계를 되돌려 물 횟수를 다시 받았다")
        }
        XCTAssertEqual(PlantEngine.waterUsesLeft(s, today: "2026-09-29"), PlantBalance.dailyWaterUses)
    }

    /// 양력이 아닌 달력(태국 불기 · 일본 연호) 설정에서도 키는 양력 연도다 —
    /// 아니면 `~/.codex/sessions/2026/…` 경로와 어긋나 Codex 가 늘 0 이다.
    func testDayKeyIsAlwaysGregorian() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = .current
        let date = DayKey.parse("2026-09-28")!.addingTimeInterval(3_600)
        XCTAssertTrue(DayKey.make(buddhist.date(from: buddhist.dateComponents([.era, .year, .month, .day, .hour],
                                                                             from: date))!)
                        .hasPrefix("2026-"))
        XCTAssertEqual(DayKey.gregorian.identifier, .gregorian)
    }
}

// MARK: 헛소모

final class WastedItemTests: XCTestCase {

    /// 거름은 7일치가 온전히 들어갈 자리가 있을 때만 쓴다. 예전엔 3개 뒤 네 번째가 통과해
    /// 몇 초만 늘고 사라졌다.
    func testFourthFertilizerIsBlockedBeforeConsuming() {
        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato", cycleWater: 100_000)
        s.inventory[ShopItem.fertilizer.rawValue] = 4
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        for _ in 0..<3 {
            XCTAssertEqual(PlantEngine.use(.fertilizer, &s, today: "2026-09-28", now: t0), .ok(waterGained: 0))
        }
        let later = t0.addingTimeInterval(5)
        XCTAssertNotNil(PlantEngine.fertilizerBlockReason(s, now: later))
        if case .ok = PlantEngine.use(.fertilizer, &s, today: "2026-09-28", now: later) {
            XCTFail("네 번째 거름이 거의 효과 없이 소모됐다")
        }
        XCTAssertEqual(s.count(.fertilizer), 1)
        // 일주일 지나면(남은 14일) 다시 붙일 수 있다.
        let week = t0.addingTimeInterval(7 * 86_400 + 60)
        XCTAssertNil(PlantEngine.fertilizerBlockReason(s, now: week))
    }

    /// 모든 화분이 이식 대기면 물은 넘쳐서 버려진다 — 소모 전에 막는다.
    func testWaterIsNotSpentWhenEveryPotIsReady() {
        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato", water: 100_000,
                         stageIndex: PlantBalance.stageCount - 1, cycleWater: 100_000)
        XCTAssertTrue(s.pot!.isReadyToTransplant)
        s.inventory[ShopItem.water.rawValue] = 2
        if case .ok = PlantEngine.use(.water, &s, today: "2026-09-28") {
            XCTFail("이식 대기 중인 그루에 물이 소모됐다")
        }
        XCTAssertEqual(s.count(.water), 2)
        XCTAssertEqual(s.waterUsesToday, 0, "효과 없이 오늘 횟수만 빠졌다")

        // 한 그루라도 자랄 수 있으면 쓸 수 있다.
        s.pot2 = PotState(speciesID: "rose", cycleWater: 100_000)
        XCTAssertNil(PlantEngine.waterBlockReason(s, today: "2026-09-28"))
    }
}

@MainActor
final class SharedBlockReasonTests: XCTestCase {

    /// 창고와 퀵 슬롯이 같은 판정을 본다 — 예전엔 창고만 물 하루 상한을 안 봐서 버튼이 켜져 있었다.
    func testStorageSeesDailyWaterCap() throws {
        let url = tempURL("block")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let clock = Clock("2026-09-28")
        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato", cycleWater: 100_000)
        s.inventory[ShopItem.water.rawValue] = 3
        s.waterUseDay = "2026-09-28"
        s.waterUsesToday = PlantBalance.dailyWaterUses
        try JSONEncoder().encode(s).write(to: url)
        let store = PlantStore(url: url, clock: { clock.now })
        XCTAssertNotNil(store.blockReason(.water))
        clock.set("2026-09-29")
        XCTAssertNil(store.blockReason(.water))
    }
}

// MARK: 세이브 일부 손상

@MainActor
final class PartialSaveTests: XCTestCase {

    /// 정원 항목 하나가 깨져도 나머지 정원은 살고, 원본은 덮기 전에 옆에 남는다.
    /// 예전엔 정원 전체가 `[]` 가 됐고 백업도 없이 다음 저장에서 사라졌다.
    func testOneBrokenGardenEntryKeepsTheRest() throws {
        let url = tempURL("partial")
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato", cycleWater: 100_000)
        s.claimedTodayByProvider = [:]
        s.garden = (0..<3).map { GardenEntry(speciesID: "rose", plantedAt: Date(), totalWater: 10 * ($0 + 1)) }
        s.dailyRaw = ["2026-09-26": 1, "2026-09-27": 2]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        var garden = try XCTUnwrap(json["garden"] as? [[String: Any]])
        garden[1]["totalWater"] = "망가짐"
        json["garden"] = garden
        var daily = try XCTUnwrap(json["dailyRaw"] as? [String: Any])
        daily["2026-09-26"] = "x"
        json["dailyRaw"] = daily
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let store = PlantStore(url: url)
        XCTAssertEqual(store.save.garden.map(\.totalWater), [10, 30], "깨진 한 그루 때문에 정원 전체가 사라졌다")
        XCTAssertEqual(store.save.dailyRaw, ["2026-09-27": 2])
        XCTAssertNotNil(store.save.pot, "키우던 그루가 사라졌다")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("state.json.partial-") }, "원본이 보존되지 않았다")
    }

    /// 멀쩡한 세이브에는 백업을 만들지 않는다 — 켤 때마다 파일이 쌓이면 안 된다.
    func testHealthySaveMakesNoBackup() throws {
        let url = tempURL("healthy")
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = PlantStore(url: url)
        _ = PlantStore(url: url)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(names, ["state.json"])
    }
}

// MARK: 앱이 꺼져 있던 날

final class CatchUpTests: XCTestCase {

    private func save(lastDate: String, claimed: [String: TokenDelta]) -> PlantSave {
        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato", cycleWater: 10_000_000)
        s.claimedTodayByProvider = claimed
        s.lastDate = lastDate
        s.lastUseDay = lastDate
        s.streakDays = 2
        return s
    }

    /// 사흘 꺼져 있던 동안 쓴 몫이 그날 날짜로 들어오고, 스트릭도 이어진다.
    /// 마지막 날은 이미 적립한 몫을 빼고 나머지(자정 직전 몫)만 넣는다.
    func testMissedDaysAreCreditedOnceUnderTheirOwnDate() {
        var s = save(lastDate: "2026-09-25", claimed: ["claude": TokenDelta(output: 100)])
        let byDay: [String: [String: TokenDelta]] = [
            "2026-09-25": ["claude": TokenDelta(output: 130)],
            "2026-09-26": ["claude": TokenDelta(output: 200)],
            "2026-09-27": ["codex": TokenDelta(output: 50)],
            "2026-09-28": ["claude": TokenDelta(output: 999)],     // 오늘 — ingest 몫이라 안 센다
        ]
        PlantEngine.catchUp(&s, byDay: byDay, from: "2026-09-25", today: "2026-09-28")
        XCTAssertEqual(s.rawWallet, 30 + 200 + 50)
        XCTAssertEqual(s.dailyRaw["2026-09-26"], 200)
        XCTAssertNil(s.dailyRaw["2026-09-28"])
        XCTAssertEqual(s.streakDays, 4, "꺼져 있던 동안 쓴 날이 스트릭에 안 잡혔다")

        // 두 번 불려도 두 번 세지 않는다.
        PlantEngine.catchUp(&s, byDay: byDay, from: "2026-09-25", today: "2026-09-28")
        XCTAssertEqual(s.rawWallet, 280)

        // 이어서 오늘을 적립하면 오늘은 0부터 센다.
        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(output: 10)], today: "2026-09-28")
        XCTAssertEqual(s.rawWallet, 290)
    }

    /// 오늘 몫이 먼저 적립돼 날이 넘어간 뒤에 도착해도 마지막 날의 기준을 찾아 뺀다.
    func testLateCatchUpAfterIngestUsesStashedBaseline() {
        var s = save(lastDate: "2026-09-27", claimed: ["claude": TokenDelta(output: 100)])
        PlantEngine.ingest(&s, todayByProvider: [:], today: "2026-09-28")
        PlantEngine.catchUp(&s, byDay: ["2026-09-27": ["claude": TokenDelta(output: 150)]],
                            from: "2026-09-27", today: "2026-09-28")
        XCTAssertEqual(s.rawWallet, 50)
    }

    /// 첫 설치 전(기준선 없음)에는 소급하지 않는다.
    func testNoCatchUpBeforeInstallBaseline() {
        var s = PlantSave()
        s.lastDate = "2026-09-20"
        PlantEngine.catchUp(&s, byDay: ["2026-09-21": ["claude": TokenDelta(output: 500)]],
                            from: "2026-09-20", today: "2026-09-28")
        XCTAssertEqual(s.rawWallet, 0)
    }
}

// MARK: 한도 창 시드

final class WindowSeedTests: XCTestCase {

    /// Codex 만 먼저 읽힌 날 시드가 끝나도, 나중에 처음 보이는 Claude 창이 이미 100% 면
    /// 소급 지급하지 않는다. 한 번 내려갔다 다시 100% 가 되면 그때 준다.
    func testLateWindowIsSeededOnFirstSight() {
        var s = PlantSave()
        let codex = LimitWindowInfo(key: "codex.weekly", name: "Codex 주간", kind: .weekly, utilization: 40)
        XCTAssertEqual(PlantEngine.grantWindowBonus(&s, windows: [codex], isReady: true), 0)
        let full = LimitWindowInfo(key: "claude.sevenDay", name: "Claude 주간", kind: .weekly, utilization: 100)
        XCTAssertEqual(PlantEngine.grantWindowBonus(&s, windows: [codex, full], isReady: true), 0,
                       "처음 보는 창이 소급 지급됐다")
        let reset = LimitWindowInfo(key: "claude.sevenDay", name: "Claude 주간", kind: .weekly, utilization: 10)
        _ = PlantEngine.grantWindowBonus(&s, windows: [codex, reset], isReady: true)
        XCTAssertEqual(PlantEngine.grantWindowBonus(&s, windows: [codex, full], isReady: true),
                       PlantBalance.windowBonusWeekly)
    }
}

// MARK: 가격 — 하루 안에서 흔들리지 않는다

final class StablePriceTests: XCTestCase {

    /// 아침(오늘 몫 0)과 저녁(오늘 몫 가득)의 가격이 같아야 한다.
    /// 예전엔 오늘을 하루로 세서 설치 3일째 아침이 저녁보다 33% 쌌다.
    func testPriceDoesNotDependOnTimeOfDay() {
        var morning = PlantSave()
        morning.dailyRaw = ["2026-09-25": 30_000_000, "2026-09-26": 30_000_000, "2026-09-27": 30_000_000]
        morning.lastDate = "2026-09-28"
        var evening = morning
        evening.dailyRaw["2026-09-28"] = 30_000_000
        XCTAssertEqual(PlantEngine.dailyRate(morning), 30_000_000)
        XCTAssertEqual(PlantEngine.dailyRate(evening), 30_000_000)
        XCTAssertEqual(PlantEngine.price(.water, morning), PlantEngine.price(.water, evening))
    }
}

// MARK: 표기

final class TokenFormatTests: XCTestCase {

    /// 반올림하면 윗 단위가 되는 값은 윗 단위로 쓴다 — "1000K" · "1000.0M" 이 찍혔다.
    func testBoundariesRollOverToTheNextUnit() {
        XCTAssertEqual(TokenFormat.short(999), "999")
        XCTAssertEqual(TokenFormat.short(999_499), "999K")
        XCTAssertEqual(TokenFormat.short(999_500), "1.0M")
        XCTAssertEqual(TokenFormat.short(999_949_999), "999.9M")
        XCTAssertEqual(TokenFormat.short(999_950_000), "1.00B")
    }
}

// MARK: Codex 세션 카운터 리셋

final class CodexResetTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenplant-codexreset-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func line(at date: Date, output: Int) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        let obj: [String: Any] = [
            "timestamp": f.string(from: date),
            "type": "event_msg",
            "payload": ["info": ["total_token_usage": [
                "input_tokens": 0, "cached_input_tokens": 0, "output_tokens": output]]],
        ]
        return String(decoding: try! JSONSerialization.data(withJSONObject: obj), as: UTF8.self)
    }

    /// 같은 파일에 이어 쓴 resume 에서 누적이 다시 시작되면(실측 240,988,725 → 180,698),
    /// 예전엔 음수가 0 으로 잘려 그날 그 세션 몫이 통째로 빠졌다.
    func testCounterResetAfterMidnightStillCountsTodaysUsage() throws {
        let today = DayKey.make(Date())
        let yesterday = DayKey.shifted(today, by: -1)!
        let p = yesterday.split(separator: "-")
        let dir = tmp.appendingPathComponent("\(p[0])/\(p[1])/\(p[2])", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let startOfToday = DayKey.parse(today)!
        try ([line(at: startOfToday.addingTimeInterval(-3_600), output: 240_000),
              line(at: Date(), output: 1_800)].joined(separator: "\n") + "\n")
            .write(to: dir.appendingPathComponent("rollout.jsonl"), atomically: true, encoding: .utf8)

        let (d, _) = UsageReader.readCodex(today: today, root: tmp)
        XCTAssertEqual(d.output, 1_800, "카운터가 리셋된 세션의 오늘 몫이 0이 됐다")
    }
}
