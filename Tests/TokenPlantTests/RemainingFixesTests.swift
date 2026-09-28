import XCTest
@testable import TokenPlant

// MARK: 두 번째 화분 · 자정 넘긴 Codex · 망가진 세이브

final class SecondPotTests: XCTestCase {

    private func richSave() -> PlantSave {
        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato", cycleWater: 100_000)
        s.rawWallet = ShopItem.potSlot.price * 2
        return s
    }

    /// 화분 슬롯을 사면 1번 화분을 **복제하지 않고** 새 씨앗을 뽑는다.
    func testPotSlotPlantsAFreshSeed() {
        var s = richSave()
        // 1번과 다른 종이 나오는 roll 을 고른다.
        let roll = (0..<1_000).map(UInt64.init).first {
            PlantOdds.pickSpecies(roll: $0, guarantee: nil).id != "tomato"
        }!
        XCTAssertEqual(PlantEngine.buy(.potSlot, &s, roll: roll), .ok)
        XCTAssertNotNil(s.pot2)
        XCTAssertNotEqual(s.pot2?.speciesID, "tomato", "1번 화분의 종이 복제됐다")
        XCTAssertTrue(s.pendingEvents.contains { $0.coalesceKey == "newSeed" }, "새 씨앗 연출이 없다")
    }

    /// 산 등급 보증은 1번 화분 몫이다 — 슬롯을 산다고 소비되면 안 된다.
    func testPotSlotKeepsSeedGuarantee() {
        var s = richSave()
        s.pendingSeedGuarantee = .legendary
        _ = PlantEngine.buy(.potSlot, &s, roll: 1)
        XCTAssertEqual(s.pendingSeedGuarantee, .legendary)
    }

    /// 영양제를 2번 화분에 줄 수 있고, 그 그루에만 들어간다.
    func testNutrientCanTargetSecondPot() {
        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato", water: 50_000, cycleWater: 100_000)
        s.pot2 = PotState(speciesID: "rose", water: 0, cycleWater: 100_000)
        s.inventory[ShopItem.nutrient.rawValue] = 2
        guard case .ok(let gained) = PlantEngine.use(.nutrient, &s, today: "2026-09-10", slot: 1) else {
            return XCTFail("2번 화분에 영양제를 못 줬다")
        }
        XCTAssertEqual(gained, 10_000, "2번 화분의 남은 거리(100,000)의 10% 가 아니다")
        XCTAssertEqual(s.pot2?.water, 10_000)
        XCTAssertEqual(s.pot?.water, 50_000, "1번 화분에도 들어갔다")
        XCTAssertEqual(s.pot2?.nutrientUses, 1)
        XCTAssertEqual(s.pot?.nutrientUses, 0)
        // 1번 화분 몫은 그대로 남아 있다.
        guard case .ok = PlantEngine.use(.nutrient, &s, today: "2026-09-10", slot: 0) else {
            return XCTFail("1번 화분 몫이 사라졌다")
        }
    }
}

final class CodexCarryOverTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tokenplant-codex-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private var today: String { DayKey.make(Date()) }

    private func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: d)
    }

    private func line(at ts: String?, output: Int) -> String {
        var obj: [String: Any] = [
            "type": "event_msg",
            "payload": ["info": ["total_token_usage": [
                "input_tokens": 0, "cached_input_tokens": 0, "output_tokens": output]]],
        ]
        if let ts { obj["timestamp"] = ts }
        return String(decoding: try! JSONSerialization.data(withJSONObject: obj), as: UTF8.self)
    }

    private func writeSession(dayBack: Int, _ lines: [String]) throws {
        let day = DayKey.shifted(today, by: -dayBack)!
        let p = day.split(separator: "-")
        let dir = tmp.appendingPathComponent("\(p[0])/\(p[1])/\(p[2])", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n")
            .write(to: dir.appendingPathComponent("rollout.jsonl"), atomically: true, encoding: .utf8)
    }

    /// 어제 시작해 오늘도 이어 쓴 세션 — 오늘 몫(150 − 100)만 센다.
    func testSessionCrossingMidnightCountsTodaysShare() throws {
        let startOfToday = DayKey.parse(today)!
        try writeSession(dayBack: 1, [
            line(at: iso(startOfToday.addingTimeInterval(-3_600)), output: 100),
            line(at: iso(Date()), output: 150),
        ])
        let (d, _) = UsageReader.readCodex(today: today, root: tmp)
        XCTAssertEqual(d.output, 50)
    }

    /// 타임스탬프가 없어 0시 직전 값을 모르면 세지 않는다 — 세션 전체를 오늘로 치면 안 된다.
    func testUntimestampedOldSessionIsNotCounted() throws {
        try writeSession(dayBack: 2, [line(at: nil, output: 100), line(at: nil, output: 900)])
        let (d, _) = UsageReader.readCodex(today: today, root: tmp)
        XCTAssertEqual(d.output, 0)
    }

    /// 1MB 가 넘는 줄 너머에 있는 0시 직전 값도 찾는다(청크 경계에서 줄을 버리면 못 찾는다).
    func testBaselineBehindLongLineIsFound() throws {
        let startOfToday = DayKey.parse(today)!
        let filler = #"{"type":"x","pad":""# + String(repeating: "a", count: 1_500_000) + #""}"#
        try writeSession(dayBack: 1, [
            line(at: iso(startOfToday.addingTimeInterval(-60)), output: 70),
            filler,
            line(at: iso(Date()), output: 100),
        ])
        let (d, _) = UsageReader.readCodex(today: today, root: tmp)
        XCTAssertEqual(d.output, 30)
    }
}

@MainActor
final class UnreadableSaveTests: XCTestCase {

    /// 파일째 망가진 세이브는 새 세이브로 덮기 전에 옆으로 치워 둔다.
    func testUnreadableSaveIsSetAside() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tokenplant-bad-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("state.json")
        try Data("{ 망가진".utf8).write(to: url)

        _ = PlantStore(url: url)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let aside = names.first { $0.hasPrefix("state.json.unreadable-") }
        XCTAssertNotNil(aside, "원본이 보존되지 않았다")
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(aside!)), Data("{ 망가진".utf8))
    }
}
