import XCTest
@testable import TokenPlant

// MARK: 로컬 로그 파싱
//
// 여기가 앱 전체에서 가장 위험한 자리다. 물이 0이면 앱이 죽은 것처럼 보이고,
// 중복을 못 걸러 두 배로 들어오면 하루에 만렙이 된다.
// 실측 로그를 그대로 못 쓰므로(개인 데이터) 같은 모양의 픽스처를 만들어 검증한다.
//
// 실측에서 확인된 특징을 픽스처에 그대로 넣는다:
//   · Claude Code — 같은 메시지가 여러 세션 파일에 중복(8,019건 → 중복 포함 10,179건)
//   · Codex — 턴마다 누적값이 실리고, 세션 파일이 2.2GB까지 간다
//   · `cached_input_tokens` 는 `input_tokens` 에 **포함된** 값이다

final class UsageReaderTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tokenplant-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: 픽스처 도구

    /// 오늘. 픽스처 파일의 mtime 이 지금이므로 mtime 필터를 통과하려면 오늘이어야 한다.
    private var today: String { DayKey.make(Date()) }

    /// 지금 시각의 UTC ISO 문자열. `utcWindow` 가 잡는 구간 안에 확실히 들어간다.
    private func nowISO(offsetSeconds: TimeInterval = 0) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: Date().addingTimeInterval(offsetSeconds))
    }

    private func write(_ lines: [String], to relativePath: String) throws {
        let url = tmp.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Claude Code 한 줄. 실제 스키마대로 `message.usage` 안에 넣는다.
    private func ccLine(requestID: String?,
                        messageID: String? = nil,
                        uuid: String? = nil,
                        timestamp: String? = nil,
                        input: Int = 0, output: Int = 0,
                        cacheWrite: Int = 0, cacheRead: Int = 0) -> String {
        var message: [String: Any] = [
            "usage": [
                "input_tokens": input,
                "output_tokens": output,
                "cache_creation_input_tokens": cacheWrite,
                "cache_read_input_tokens": cacheRead,
            ]
        ]
        if let messageID { message["id"] = messageID }

        var obj: [String: Any] = ["type": "assistant", "message": message]
        obj["timestamp"] = timestamp ?? nowISO()
        if let requestID { obj["requestId"] = requestID }
        if let uuid { obj["uuid"] = uuid }

        let data = try! JSONSerialization.data(withJSONObject: obj)
        return String(decoding: data, as: UTF8.self)
    }

    /// Codex 한 줄. `payload.info.total_token_usage` 는 **누적**이다.
    private func codexLine(input: Int, cached: Int, output: Int) -> String {
        let obj: [String: Any] = [
            "type": "event_msg",
            "payload": [
                "info": [
                    "total_token_usage": [
                        "input_tokens": input,
                        "cached_input_tokens": cached,
                        "output_tokens": output,
                    ]
                ]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Claude Code

    func testSumsUsageAcrossNestedProjectFolders() throws {
        try write([ccLine(requestID: "r1", output: 1_000)],
                  to: "projects/-Users-me-alpha/a.jsonl")
        try write([ccLine(requestID: "r2", input: 500, cacheRead: 20_000)],
                  to: "projects/-Users-me-beta/deeper/b.jsonl")

        let (d, skipped) = UsageReader.readClaudeCode(today: today,
                                                      root: tmp.appendingPathComponent("projects"))
        XCTAssertEqual(skipped, 0)
        XCTAssertEqual(d.output, 1_000)
        XCTAssertEqual(d.input, 500)
        XCTAssertEqual(d.cacheRead, 20_000)
    }

    /// 실측에서 중복이 25%였다. 못 걸러내면 물이 그만큼 부풀어 오른다.
    func testDeduplicatesSameRequestIdAcrossFiles() throws {
        let dup = ccLine(requestID: "same", output: 10_000)
        try write([dup], to: "projects/one/a.jsonl")
        try write([dup, ccLine(requestID: "other", output: 7)], to: "projects/two/b.jsonl")

        let (d, _) = UsageReader.readClaudeCode(today: today,
                                                root: tmp.appendingPathComponent("projects"))
        XCTAssertEqual(d.output, 10_007, "같은 requestId 가 두 번 세어졌다")
    }

    /// requestId 가 없는 줄도 있다 — message.id, 그다음 uuid 로 내려간다.
    func testFallsBackToMessageIdThenUuid() throws {
        try write([
            ccLine(requestID: nil, messageID: "m1", output: 100),
            ccLine(requestID: nil, messageID: "m1", output: 100),   // 중복
            ccLine(requestID: nil, messageID: nil, uuid: "u1", output: 3),
            ccLine(requestID: nil, messageID: nil, uuid: "u1", output: 3),   // 중복
        ], to: "projects/one/a.jsonl")

        let (d, _) = UsageReader.readClaudeCode(today: today,
                                                root: tmp.appendingPathComponent("projects"))
        XCTAssertEqual(d.output, 103, "message.id / uuid 폴백이 중복을 못 걸렀다")
    }

    /// 파일 mtime 은 오늘이어도 안에 어제 줄이 섞여 있다. 타임스탬프로 다시 걸러야 한다.
    func testIgnoresLinesOutsideTodayWindow() throws {
        try write([
            ccLine(requestID: "today", output: 500),
            ccLine(requestID: "yesterday", timestamp: nowISO(offsetSeconds: -60 * 60 * 30), output: 90_000),
            ccLine(requestID: "tomorrow", timestamp: nowISO(offsetSeconds: 60 * 60 * 30), output: 90_000),
        ], to: "projects/one/a.jsonl")

        let (d, _) = UsageReader.readClaudeCode(today: today,
                                                root: tmp.appendingPathComponent("projects"))
        XCTAssertEqual(d.output, 500, "오늘 창을 벗어난 줄이 들어왔다")
    }

    /// 타임스탬프가 없는 줄은 버린다 — 파일 mtime 만으로는 오늘인지 못 믿는다.
    func testDropsLinesWithoutTimestamp() throws {
        let noTS = #"{"requestId":"x","message":{"usage":{"input_tokens":5,"output_tokens":99999}}}"#
        try write([noTS, ccLine(requestID: "ok", output: 1)],
                  to: "projects/one/a.jsonl")

        let (d, _) = UsageReader.readClaudeCode(today: today,
                                                root: tmp.appendingPathComponent("projects"))
        XCTAssertEqual(d.output, 1)
    }

    /// 로그가 쓰이는 중에 읽으면 마지막 줄이 잘려 있다. 한 줄이 깨졌다고 파일 전체를 버리면 안 된다.
    func testSurvivesMalformedAndEmptyLines() throws {
        // 마지막 줄이 쓰이는 중에 끊긴 모양 — 실제로 이렇게 생긴 줄을 만난다.
        let truncated = String(ccLine(requestID: "broken", output: 99_999).dropLast(30))
        try write([
            "",
            "not json at all",
            "{",
            truncated,
            ccLine(requestID: "good", output: 42),
            "   ",
        ], to: "projects/one/a.jsonl")

        let (d, skipped) = UsageReader.readClaudeCode(today: today,
                                                      root: tmp.appendingPathComponent("projects"))
        XCTAssertEqual(skipped, 0, "깨진 줄은 파일 실패가 아니다")
        XCTAssertEqual(d.output, 42)
    }

    /// 스키마가 버전마다 움직인다 — usage 가 최상위에 있는 줄도 처리해야 한다.
    func testFindsUsageAtAnyNestingDepth() throws {
        let topLevel: [String: Any] = [
            "timestamp": nowISO(),
            "requestId": "flat",
            "usage": ["input_tokens": 11, "output_tokens": 22],
        ]
        let deep: [String: Any] = [
            "timestamp": nowISO(),
            "requestId": "deep",
            "a": ["b": ["c": ["usage": ["input_tokens": 1, "output_tokens": 2]]]],
        ]
        func line(_ o: [String: Any]) -> String {
            String(decoding: try! JSONSerialization.data(withJSONObject: o), as: UTF8.self)
        }
        try write([line(topLevel), line(deep)], to: "projects/one/a.jsonl")

        let (d, _) = UsageReader.readClaudeCode(today: today,
                                                root: tmp.appendingPathComponent("projects"))
        XCTAssertEqual(d.input, 12)
        XCTAssertEqual(d.output, 24)
    }

    func testIgnoresNonJsonlFiles() throws {
        try write([ccLine(requestID: "r", output: 1)], to: "projects/one/a.jsonl")
        try write([ccLine(requestID: "z", output: 999_999)], to: "projects/one/b.json")
        try write([ccLine(requestID: "y", output: 999_999)], to: "projects/one/c.txt")

        let (d, _) = UsageReader.readClaudeCode(today: today,
                                                root: tmp.appendingPathComponent("projects"))
        XCTAssertEqual(d.output, 1)
    }

    /// 며칠 전 파일을 매번 파싱하면 갱신이 몇 초씩 걸린다 — mtime 으로 먼저 걸러야 한다.
    func testMtimeFilterSkipsOldFiles() throws {
        try write([ccLine(requestID: "old", output: 5_000)], to: "projects/one/old.jsonl")
        let old = tmp.appendingPathComponent("projects/one/old.jsonl")
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-60 * 60 * 24 * 5)],
            ofItemAtPath: old.path)

        let files = UsageReader.jsonlFiles(under: tmp.appendingPathComponent("projects"),
                                           modifiedOn: today)
        XCTAssertEqual(files?.count, 0, "5일 전 파일이 후보에 남았다")
    }

    /// 폴더가 없는 건 정상이다(그 도구를 안 쓰는 사람). 0을 돌려주고 조용히 넘어가야 한다.
    func testMissingRootIsZeroNotError() {
        let (d, skipped) = UsageReader.readClaudeCode(today: today,
                                                      root: tmp.appendingPathComponent("nope"))
        XCTAssertTrue(d.isZero)
        XCTAssertEqual(skipped, 0)
    }

    // MARK: Codex

    /// 누적값이므로 마지막 줄만 쓴다. 다 더하면 몇 배로 부푼다.
    func testTakesOnlyLastCumulativeUsagePerFile() throws {
        let parts = today.split(separator: "-")
        try write([
            codexLine(input: 100, cached: 0, output: 10),
            codexLine(input: 900, cached: 400, output: 90),
            codexLine(input: 2_000, cached: 1_500, output: 300),   // 최종 누적
        ], to: "sessions/\(parts[0])/\(parts[1])/\(parts[2])/s1.jsonl")

        let (d, skipped) = UsageReader.readCodex(today: today,
                                                 root: tmp.appendingPathComponent("sessions"))
        XCTAssertEqual(skipped, 0)
        XCTAssertEqual(d.output, 300)
        // cached 는 input 에 포함된 값이라 신규 입력은 차이다.
        XCTAssertEqual(d.input, 500)
        XCTAssertEqual(d.cacheRead, 1_500)
        XCTAssertEqual(d.cacheWrite, 0)
    }

    func testSumsAcrossSessionFilesOfTheSameDay() throws {
        let parts = today.split(separator: "-")
        let dir = "sessions/\(parts[0])/\(parts[1])/\(parts[2])"
        try write([codexLine(input: 1_000, cached: 800, output: 50)], to: "\(dir)/a.jsonl")
        try write([codexLine(input: 300, cached: 100, output: 7)], to: "\(dir)/b.jsonl")

        let (d, _) = UsageReader.readCodex(today: today,
                                           root: tmp.appendingPathComponent("sessions"))
        XCTAssertEqual(d.input, 200 + 200)
        XCTAssertEqual(d.cacheRead, 800 + 100)
        XCTAssertEqual(d.output, 57)
    }

    /// cached 가 input 보다 큰 로그도 봤다. 음수 입력이 나오면 물이 줄어든다.
    func testNeverProducesNegativeInput() throws {
        let parts = today.split(separator: "-")
        try write([codexLine(input: 100, cached: 5_000, output: 1)],
                  to: "sessions/\(parts[0])/\(parts[1])/\(parts[2])/s.jsonl")

        let (d, _) = UsageReader.readCodex(today: today,
                                           root: tmp.appendingPathComponent("sessions"))
        XCTAssertEqual(d.input, 0, "입력이 음수가 됐다")
        XCTAssertEqual(d.cacheRead, 5_000)
    }

    /// 누적값이 아예 없는 세션 파일(막 시작한 세션)은 skipped 로 센다.
    func testFileWithoutTotalUsageCountsAsSkipped() throws {
        let parts = today.split(separator: "-")
        try write([#"{"type":"session_meta","payload":{}}"#],
                  to: "sessions/\(parts[0])/\(parts[1])/\(parts[2])/empty.jsonl")

        let (d, skipped) = UsageReader.readCodex(today: today,
                                                 root: tmp.appendingPathComponent("sessions"))
        XCTAssertTrue(d.isZero)
        XCTAssertEqual(skipped, 1)
    }

    func testMissingDayFolderIsZero() {
        let (d, skipped) = UsageReader.readCodex(today: today,
                                                 root: tmp.appendingPathComponent("sessions"))
        XCTAssertTrue(d.isZero)
        XCTAssertEqual(skipped, 0)
    }

    /// 실측 세션 파일이 2.2GB였다. 끝에서 거꾸로 훑는 루프가 청크 경계를 넘겨야 한다.
    /// 누적값 줄 뒤에 1MB(청크 크기)보다 큰 꼬리를 붙여 두 청크를 강제한다.
    func testReverseScanCrossesChunkBoundary() throws {
        let parts = today.split(separator: "-")
        let padding = String(repeating: "x", count: 200)
        var lines = [codexLine(input: 4_000, cached: 3_000, output: 400)]
        // 1.4MB 정도의 꼬리 — 누적값 줄은 첫 1MB 청크에 안 들어온다.
        for i in 0..<7_000 {
            lines.append(#"{"type":"noise","i":\#(i),"pad":"\#(padding)"}"#)
        }
        try write(lines, to: "sessions/\(parts[0])/\(parts[1])/\(parts[2])/big.jsonl")

        let url = tmp.appendingPathComponent("sessions/\(parts[0])/\(parts[1])/\(parts[2])/big.jsonl")
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, 1 << 20, "픽스처가 청크 하나에 다 들어가면 이 테스트는 의미가 없다")

        let d = UsageReader.lastTotalTokenUsage(url)
        XCTAssertEqual(d?.output, 400, "청크 경계를 넘어가며 누적값을 못 찾았다")
        XCTAssertEqual(d?.input, 1_000)
        XCTAssertEqual(d?.cacheRead, 3_000)
    }

    // MARK: 날짜 창

    /// 로컬 하루는 UTC 에서 날짜가 걸쳐 있다. 앞 10자만 비교하면 반나절이 사라진다.
    func testUtcWindowSpansExactlyOneLocalDay() throws {
        let w = try XCTUnwrap(UsageReader.utcWindow(forLocalDay: "2026-09-09"))
        XCTAssertLessThan(w.start, w.end)
        XCTAssertEqual(w.start.count, 19)
        XCTAssertEqual(w.end.count, 19)

        let start = try XCTUnwrap(DayKey.parse("2026-09-09"))
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)

        // 경계: 시작 순간은 포함, 끝 순간은 제외.
        XCTAssertTrue(w.contains(String(f.string(from: start).prefix(19))))
        XCTAssertTrue(w.contains(String(f.string(from: start.addingTimeInterval(60)).prefix(19))))
        XCTAssertFalse(w.contains(String(f.string(from: start.addingTimeInterval(-60)).prefix(19))))
        XCTAssertFalse(w.contains(String(f.string(from: start.addingTimeInterval(86_400)).prefix(19))))
        XCTAssertTrue(w.contains(String(f.string(from: start.addingTimeInterval(86_399)).prefix(19))))
    }

    /// 소수 초가 붙어도 경계 비교가 흔들리면 안 된다.
    func testWindowIgnoresFractionalSeconds() throws {
        let w = try XCTUnwrap(UsageReader.utcWindow(forLocalDay: "2026-09-09"))
        let mid = "\(w.start).123456Z"
        XCTAssertTrue(w.contains(mid))
        XCTAssertFalse(w.contains("\(w.end).000Z"))
    }

    func testBadDayKeyIsRejected() {
        XCTAssertNil(UsageReader.utcWindow(forLocalDay: "not-a-day"))
        let (d, _) = UsageReader.readCodex(today: "2026-09", root: tmp)
        XCTAssertTrue(d.isZero)
    }

    // MARK: 합치기

    func testReadTodayMergesBothProvidersUnderTheirOwnKeys() throws {
        let parts = today.split(separator: "-")
        try write([ccLine(requestID: "r", output: 1_000, cacheRead: 50_000)],
                  to: "projects/one/a.jsonl")
        try write([codexLine(input: 2_000, cached: 1_500, output: 300)],
                  to: "sessions/\(parts[0])/\(parts[1])/\(parts[2])/s.jsonl")

        let snap = UsageReader.readToday(today,
                                         claudeRoot: tmp.appendingPathComponent("projects"),
                                         codexRoot: tmp.appendingPathComponent("sessions"))
        XCTAssertEqual(Set(snap.byProvider.keys), ["claude", "codex"])
        XCTAssertEqual(snap.byProvider["claude"]?.output, 1_000)
        XCTAssertEqual(snap.byProvider["codex"]?.output, 300)
        XCTAssertEqual(snap.total.output, 1_300)
        XCTAssertEqual(snap.skippedFiles, 0)
    }

    /// 사용량이 0인 프로바이더는 키를 만들지 않는다 —
    /// `ingest` 가 프로바이더별 기준값을 잡으므로 빈 키가 섞이면 기준이 흐려진다.
    func testZeroProviderIsOmitted() throws {
        try write([ccLine(requestID: "r", output: 5)], to: "projects/one/a.jsonl")
        let snap = UsageReader.readToday(today,
                                         claudeRoot: tmp.appendingPathComponent("projects"),
                                         codexRoot: tmp.appendingPathComponent("sessions"))
        XCTAssertEqual(Set(snap.byProvider.keys), ["claude"])
    }

    /// 파싱 결과가 그대로 물로 환산돼야 한다 — 리더와 밸런스가 같은 단위를 쓰는지 확인.
    func testParsedUsageConvertsToExpectedWater() throws {
        try write([ccLine(requestID: "r", input: 1_000, output: 100_000,
                          cacheWrite: 400_000, cacheRead: 20_000_000)],
                  to: "projects/one/a.jsonl")

        let snap = UsageReader.readToday(today,
                                         claudeRoot: tmp.appendingPathComponent("projects"),
                                         codexRoot: tmp.appendingPathComponent("nope"))
        // (100,000×5 + 1,000×1 + 400,000×1.25 + 20,000,000×0.1) ÷ 1,000 = 3,001
        XCTAssertEqual(PlantBalance.water(from: snap.total), 3_001)
    }

    // MARK: 줄 읽기

    /// 청크(64KB)보다 긴 줄이 실제로 있다. 통째로 읽으면 하루치가 수백 MB다.
    func testLineReaderHandlesLinesLongerThanChunk() throws {
        let long = String(repeating: "a", count: 200_000)
        let url = tmp.appendingPathComponent("lines.txt")
        try "first\n\(long)\nlast".write(to: url, atomically: true, encoding: .utf8)

        let reader = try XCTUnwrap(LineReader(url: url))
        XCTAssertEqual(reader.nextLine().flatMap { String(data: $0, encoding: .utf8) }, "first")
        XCTAssertEqual(reader.nextLine()?.count, 200_000)
        // 마지막 줄에 개행이 없어도 돌려줘야 한다.
        XCTAssertEqual(reader.nextLine().flatMap { String(data: $0, encoding: .utf8) }, "last")
        XCTAssertNil(reader.nextLine())
    }

    func testLineReaderReturnsNilForMissingFile() {
        XCTAssertNil(LineReader(url: tmp.appendingPathComponent("ghost.jsonl")))
    }

    /// JSON 숫자가 Int·Double·문자열로 섞여 온다.
    func testIntOfAcceptsIntAndDoubleAndRejectsGarbage() {
        XCTAssertEqual(UsageReader.intOf(42), 42)
        XCTAssertEqual(UsageReader.intOf(42.7), 42)
        XCTAssertEqual(UsageReader.intOf(NSNumber(value: 9)), 9)
        XCTAssertEqual(UsageReader.intOf("100"), 0)
        XCTAssertEqual(UsageReader.intOf(nil), 0)
    }
}
