import XCTest
@testable import TokenPlant

// MARK: 쉰 날 · 끊긴 스트릭 · 이어 읽기
//
// 셋 다 테스트가 291개 통과하는 동안 앱에서 틀리게 돌던 것이다.
// 공통점: 테스트는 "쓴 날"만 만들었고, 앱은 **쉬는 날**과 **시간이 흐른 뒤**에 틀렸다.

final class IdleAndTailTests: XCTestCase {

    // MARK: 하루 유입 — 쉰 날도 0 으로 센다

    private func days(_ from: Int, _ n: Int, each: Int) -> [String: Int] {
        var d: [String: Int] = [:]
        for i in 0..<n { d[String(format: "2026-09-%02d", from + i)] = each }
        return d
    }

    /// 9일 매일 10M 쓰고 나흘 쉰 뒤 오늘 → 어제까지 13일 달력 평균 6.9M. 예전엔 10M 이 나왔다.
    /// 오늘(덜 찬 하루)은 안 센다 — 세면 아침 가격이 저녁보다 싸진다.
    func testIdleDaysAfterLastUseCountAsZero() {
        let d = days(10, 9, each: 10_000_000)
        XCTAssertEqual(PlantBalance.dailyRawRate(d, through: "2026-09-23"), 90_000_000 / 13)
        // 날짜를 안 주면 예전처럼 마지막 기록에서 끝난다.
        XCTAssertEqual(PlantBalance.dailyRawRate(d), 10_000_000)
    }

    /// 창 밖으로 완전히 쉬었으면 마지막으로 알던 속도를 쓴다 — 0 이면 모든 값이 1토큰이 된다.
    func testLongIdleFallsBackToLastKnownRate() {
        let d = days(1, 5, each: 10_000_000)
        XCTAssertEqual(PlantBalance.dailyRawRate(d, through: "2026-09-28"), 10_000_000)
    }

    /// 엔진 가격도 쉰 날까지 센다 — 오늘(`lastDate`) 직전 어제까지.
    func testEnginePriceUsesIdleDays() {
        var s = PlantSave()
        s.dailyRaw = days(10, 9, each: 10_000_000)
        s.lastDate = "2026-09-23"
        XCTAssertEqual(PlantEngine.dailyRate(s), 90_000_000 / 13)
        XCTAssertEqual(PlantEngine.price(.water, s), ShopItem.water.price(dailyRaw: 90_000_000 / 13))
    }

    /// "평소"도 어제까지 센다. 사흘 쓰고 이틀 쉰 뒤 오늘 → 90k ÷ 5.
    func testBaselineCountsRecentIdleDays() {
        let d = ["2026-09-01": 30_000, "2026-09-02": 30_000, "2026-09-03": 30_000]
        XCTAssertEqual(PlantBalance.baselineRawRate(d, today: "2026-09-06"), 18_000)
    }

    // MARK: 스트릭 — 끊겼으면 0

    func testStreakIsZeroOnceBroken() {
        var s = PlantSave()
        s.streakDays = 5
        s.lastUseDay = "2026-09-20"
        XCTAssertEqual(PlantEngine.activeStreak(s, today: "2026-09-20"), 5)
        XCTAssertEqual(PlantEngine.activeStreak(s, today: "2026-09-21"), 5, "어제 썼으면 아직 이어지는 중")
        XCTAssertEqual(PlantEngine.activeStreak(s, today: "2026-09-23"), 0)
    }

    /// 끊긴 스트릭 보너스가 창고의 물에 붙으면 안 된다.
    func testBrokenStreakGivesNoBonus() {
        var s = PlantSave()
        s.pot = PotState(speciesID: "dandelion", cycleWater: 1_000_000)
        s.streakDays = 10
        s.lastUseDay = "2026-09-01"
        XCTAssertEqual(PlantEngine.applyWater(&s, mL: 1_000, today: "2026-09-10"), 1_000)
        s.lastUseDay = "2026-09-09"
        XCTAssertEqual(PlantEngine.applyWater(&s, mL: 1_000, today: "2026-09-10"), 1_100)
    }

    // MARK: 이어 읽기 — 전체 읽기와 같은 답

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tokenplant-tail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("p"),
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private var today: String { DayKey.make(Date()) }

    private func line(_ id: String, output: Int) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return #"{"timestamp":"\#(f.string(from: Date()))","requestId":"\#(id)","message":{"usage":{"input_tokens":0,"output_tokens":\#(output)}}}"#
    }

    private func append(_ text: String, to name: String) throws {
        let url = tmp.appendingPathComponent("p/\(name)")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        try h.write(contentsOf: Data(text.utf8))
        try h.close()
    }

    private func tail() -> Int {
        ClaudeTailReader().read(today: today, root: tmp).0.output
    }

    func testAppendedLinesAreAddedOnce() throws {
        let r = ClaudeTailReader()
        try append(line("a", output: 10) + "\n", to: "s.jsonl")
        XCTAssertEqual(r.read(today: today, root: tmp).0.output, 10)
        XCTAssertEqual(r.read(today: today, root: tmp).0.output, 10, "같은 줄을 두 번 셌다")
        try append(line("b", output: 5) + "\n", to: "s.jsonl")
        try append(line("b", output: 5) + "\n", to: "other.jsonl")   // 다른 파일의 중복
        XCTAssertEqual(r.read(today: today, root: tmp).0.output, 15)
        XCTAssertEqual(r.read(today: today, root: tmp).0.output,
                       UsageReader.readClaudeCode(today: today, root: tmp).0.output)
    }

    /// 쓰는 중인 반쪽 줄은 남겨 뒀다가, 끝나면 센다.
    func testHalfWrittenLineIsCountedWhenFinished() throws {
        let r = ClaudeTailReader()
        let full = line("a", output: 7)
        let cut = full.index(full.startIndex, offsetBy: full.count / 2)
        try append(String(full[..<cut]), to: "s.jsonl")
        XCTAssertEqual(r.read(today: today, root: tmp).0.output, 0)
        try append(String(full[cut...]) + "\n", to: "s.jsonl")
        XCTAssertEqual(r.read(today: today, root: tmp).0.output, 7)
    }

    /// 줄바꿈 없이 끝난 완전한 줄도 센다 — 전체 읽기가 그렇게 한다.
    func testFinalLineWithoutNewlineCounts() throws {
        try append(line("a", output: 3), to: "s.jsonl")
        XCTAssertEqual(tail(), 3)
    }

    /// 파일이 줄면 처음부터 다시 센다. 이어 붙이면 사라진 줄을 계속 들고 있다.
    func testShrunkFileIsRecounted() throws {
        let r = ClaudeTailReader()
        try append(line("a", output: 10) + "\n" + line("b", output: 20) + "\n", to: "s.jsonl")
        XCTAssertEqual(r.read(today: today, root: tmp).0.output, 30)
        try (line("c", output: 1) + "\n").write(to: tmp.appendingPathComponent("p/s.jsonl"),
                                               atomically: false, encoding: .utf8)
        XCTAssertEqual(r.read(today: today, root: tmp).0.output, 1)
    }
}

// MARK: 백필 · 측정 판정

@MainActor
final class BackfillOverLiveTests: XCTestCase {

    private func store() -> PlantStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tokenplant-backfill-\(UUID().uuidString).json")
        return PlantStore(url: url, clock: { DayKey.parse("2026-09-23")! })
    }

    /// 이미 실시간으로 적은 날에 백필이 돌아도 두 배가 되면 안 된다.
    /// (`historyBackfilled` 키가 없는 옛 세이브에서 실제로 일어났다.)
    func testBackfillOverLiveDaysDoesNotDouble() {
        let s = store()
        s.update(todayUsageByProvider: [:], todayDate: "2026-09-21")          // 기준선
        s.update(todayUsageByProvider: ["claude": TokenDelta(output: 100_000_000)],
                 todayDate: "2026-09-21")
        XCTAssertEqual(s.save.dailyRaw["2026-09-21"], 100_000_000)
        s.backfillHistory(["2026-09-21": TokenDelta(output: 100_000_000),
                           "2026-09-20": TokenDelta(output: 40_000_000)])
        XCTAssertEqual(s.save.dailyRaw["2026-09-21"], 100_000_000, "실시간 기록 위에 백필이 더해졌다")
        XCTAssertEqual(s.save.dailyRaw["2026-09-20"], 40_000_000)
    }

    /// 중간에 켠 날은 로그(전체)가 실시간 기록(일부)보다 크다 — 로그를 믿는다.
    func testBackfillFillsPartialDayUpToLog() {
        let s = store()
        s.update(todayUsageByProvider: [:], todayDate: "2026-09-22")
        s.update(todayUsageByProvider: ["claude": TokenDelta(output: 30_000_000)], todayDate: "2026-09-22")
        s.backfillHistory(["2026-09-22": TokenDelta(output: 50_000_000)])
        XCTAssertEqual(s.save.dailyRaw["2026-09-22"], 50_000_000)
    }

    /// "측정 중" 표시와 가격이 같은 판정을 쓴다.
    func testMeasuredFlagMatchesPrice() {
        var save = PlantSave()
        save.dailyRaw = ["2026-09-19": 50_000_000]
        save.lastDate = "2026-09-23"
        // 기록은 하루뿐이지만 어제까지 나흘이 지났다 → 측정값(÷4)으로 매긴다. 오늘은 덜 찬 하루라 안 센다.
        XCTAssertEqual(PlantEngine.dailyRate(save), 12_500_000)
        XCTAssertNotNil(PlantBalance.measuredDailyRaw(save.dailyRaw, through: save.lastDate))
    }
}
