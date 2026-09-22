import XCTest
import Security
@testable import TokenPlant

// MARK: 한도 창 파싱
//
// 앱을 띄워서 눈으로 볼 수 없는 부분이다(Keychain·비공식 endpoint·외부 프로세스).
// 그래서 **실제 응답 모양**을 픽스처로 박아 디코딩을 고정한다.
//
// 픽스처 출처:
//   · Claude — PokeTokenBar 의 `/api/oauth/usage` 실측 픽스처(레거시형 + 신형 limits[])
//   · Codex  — PokeTokenBar 의 app-server RPC 픽스처 + 이서연님 Mac 실측 bucket 이름
//
// 특히 중요한 함정: Codex 는 **두 곳에서 서로 다른 표기**로 온다.
//   세션 로그(jsonl) → snake_case: {"limit_id":…,"primary":{"used_percent":0,"window_minutes":300}}
//   app-server RPC  → camelCase : {"limitId":…,"primary":{"usedPercent":0,"windowDurationMins":300}}
// 우리는 RPC 를 쓰므로 camelCase 가 맞다. 로그 쪽 표기로 착각해 CodingKeys 를 붙이면
// 모든 창이 조용히 사라지고 보너스가 영영 안 나온다.

final class LimitsReaderTests: XCTestCase {

    // MARK: Claude — 레거시형

    func testDecodesLegacyFiveHourAndSevenDay() throws {
        let json = """
        {"five_hour":{"utilization":23.0,"resets_at":"2026-06-10T11:10:00.034464+00:00"},
        "seven_day":{"utilization":16.0,"resets_at":"2026-06-14T03:00:01.034496+00:00"},
        "seven_day_opus":null,
        "seven_day_sonnet":{"utilization":0.0,"resets_at":"2026-06-14T03:00:01.034508+00:00"}}
        """
        let limits = try JSONDecoder().decode(LimitsReader.ClaudeLimits.self, from: Data(json.utf8))
        XCTAssertEqual(limits.fiveHour?.utilization, 23)
        XCTAssertEqual(limits.sevenDay?.utilization, 16)

        let windows = limits.grantableWindows
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].key, "claude.fiveHour")
        XCTAssertEqual(windows[0].kind, .session)
        XCTAssertEqual(windows[1].key, "claude.sevenDay")
        XCTAssertEqual(windows[1].kind, .weekly)
    }

    /// 신형 응답은 레거시 필드를 **null 로 보내고** `limits[]` 만 채운다.
    /// 이걸 안 읽으면 창이 하나도 안 잡혀 보너스가 영영 안 나온다.
    func testFallsBackToLimitsArrayWhenLegacyFieldsAreNull() throws {
        let json = """
        {"five_hour":null,"seven_day":null,
        "limits":[
        {"kind":"session","group":"session","percent":88,"severity":"warning","resets_at":null,"scope":null,"is_active":true},
        {"kind":"weekly_all","group":"weekly","percent":41,"severity":"normal","resets_at":null,"scope":null,"is_active":true},
        {"kind":"weekly_scoped","group":"weekly","percent":100,"severity":"critical","resets_at":null,
         "scope":{"model":{"display_name":"Opus"}},"is_active":true}]}
        """
        let limits = try JSONDecoder().decode(LimitsReader.ClaudeLimits.self, from: Data(json.utf8))
        let windows = limits.grantableWindows

        XCTAssertEqual(windows.count, 2, "신형 응답에서 창을 못 뽑았다")
        XCTAssertEqual(windows.first { $0.kind == .session }?.utilization, 88)
        XCTAssertEqual(windows.first { $0.kind == .weekly }?.utilization, 41)
    }

    /// `weekly_scoped`(모델별 주간)는 헤드라인 주간 창의 하위 창이다.
    /// 같이 세면 한 번의 소진으로 두 번 지급된다 — 100% 인 scoped 가 있어도 창은 두 개여야 한다.
    func testScopedWeeklyIsNotGrantedSeparately() throws {
        let json = """
        {"five_hour":{"utilization":10.0},"seven_day":{"utilization":20.0},
        "limits":[{"kind":"weekly_scoped","percent":100,"is_active":true},
                  {"kind":"weekly_scoped","percent":100,"is_active":true}]}
        """
        let limits = try JSONDecoder().decode(LimitsReader.ClaudeLimits.self, from: Data(json.utf8))
        XCTAssertEqual(limits.grantableWindows.count, 2)
        XCTAssertEqual(limits.grantableWindows.filter { $0.kind == .weekly }.count, 1)
    }

    /// 키가 통째로 없어도 죽지 않아야 한다 — endpoint 가 비공식이라 스키마가 움직인다.
    func testEmptyResponseYieldsNoWindowsInsteadOfThrowing() throws {
        let limits = try JSONDecoder().decode(LimitsReader.ClaudeLimits.self, from: Data("{}".utf8))
        XCTAssertTrue(limits.grantableWindows.isEmpty)
    }

    /// 창 키는 안정 식별자여야 한다. `resets_at` 이 섞이면 매 조회가 새 창이 되어 계속 지급된다.
    func testWindowKeysDoNotDependOnResetTime() throws {
        func keys(_ reset: String) throws -> [String] {
            let json = """
            {"five_hour":{"utilization":50.0,"resets_at":\(reset)},
             "seven_day":{"utilization":50.0,"resets_at":\(reset)}}
            """
            return try JSONDecoder().decode(LimitsReader.ClaudeLimits.self, from: Data(json.utf8))
                .grantableWindows.map(\.key)
        }
        XCTAssertEqual(try keys("\"2026-06-10T11:10:00Z\""), try keys("\"2026-06-11T04:00:00Z\""))
        XCTAssertEqual(try keys("null"), ["claude.fiveHour", "claude.sevenDay"])
    }

    // MARK: Codex — app-server RPC

    /// 이서연님 Mac 의 실제 bucket 이름을 그대로 쓴다(세션 로그에서 관측).
    /// 표기만 RPC 형태(camelCase)로 옮겼다 — 그게 우리가 읽는 경로다.
    private let codexJSON = """
    {"rateLimits":{"limitId":"codex_bengalfox","limitName":"GPT-5.3-Codex-Spark",
    "primary":{"usedPercent":86,"windowDurationMins":300,"resetsAt":1788957496},
    "secondary":{"usedPercent":58,"windowDurationMins":10080,"resetsAt":1789544296}},
    "rateLimitsByLimitId":{"codex_bengalfox":{"limitId":"codex_bengalfox","limitName":"GPT-5.3-Codex-Spark",
    "primary":{"usedPercent":86,"windowDurationMins":300,"resetsAt":1788957496},
    "secondary":{"usedPercent":58,"windowDurationMins":10080,"resetsAt":1789544296}},
    "codex_other":{"limitId":"codex_other","limitName":null,
    "primary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1788957496}}}}
    """

    func testDecodesCodexRpcPayloadInCamelCase() throws {
        let status = try JSONDecoder().decode(LimitsReader.CodexLimits.self, from: Data(codexJSON.utf8))
        XCTAssertEqual(status.rateLimits.limitId, "codex_bengalfox")
        XCTAssertEqual(status.rateLimits.limitName, "GPT-5.3-Codex-Spark")
        XCTAssertEqual(status.rateLimits.primary?.usedPercent, 86)
        XCTAssertEqual(status.rateLimits.primary?.windowDurationMins, 300)
        XCTAssertEqual(status.rateLimits.secondary?.windowDurationMins, 10_080)
    }

    /// top-level 과 byLimitId 의 같은 bucket 은 한 번만 세야 한다 — 두 번 세면 지급이 두 배다.
    func testSnapshotsDeduplicateTheTopLevelBucket() throws {
        let status = try JSONDecoder().decode(LimitsReader.CodexLimits.self, from: Data(codexJSON.utf8))
        let ids = status.snapshots.map { $0.limitId ?? "?" }
        XCTAssertEqual(ids, ["codex_bengalfox", "codex_other"], "bucket 이 중복으로 잡혔다")
    }

    /// 5시간(300분)은 세션, 주간(10,080분)은 주간. 경계와 미상까지 고정한다.
    func testWindowKindMapsByDuration() {
        XCTAssertEqual(LimitsReader.windowKind(minutes: 300), .session)
        XCTAssertEqual(LimitsReader.windowKind(minutes: 1_440), .session)
        XCTAssertEqual(LimitsReader.windowKind(minutes: 1_441), .weekly)
        XCTAssertEqual(LimitsReader.windowKind(minutes: 10_080), .weekly)
        // 미상은 세션으로 — 지급이 적은 쪽이 안전하다.
        XCTAssertEqual(LimitsReader.windowKind(minutes: nil), .session)
    }

    func testWindowLabelIsReadable() {
        XCTAssertEqual(LimitsReader.windowLabel(300), "5시간")
        XCTAssertEqual(LimitsReader.windowLabel(10_080), "주간")
        XCTAssertEqual(LimitsReader.windowLabel(120), "2시간")
        XCTAssertEqual(LimitsReader.windowLabel(45), "45분")
        XCTAssertEqual(LimitsReader.windowLabel(nil), "한도")
    }

    /// limitName 이 null 이면 limitId 로 떨어지고, 밑줄은 공백으로 풀어 읽히게 한다.
    func testBucketDisplayNameFallsBackToId() throws {
        let status = try JSONDecoder().decode(LimitsReader.CodexLimits.self, from: Data(codexJSON.utf8))
        XCTAssertEqual(status.rateLimits.displayName, "GPT-5.3-Codex-Spark")
        let other = status.snapshots.first { $0.limitId == "codex_other" }
        XCTAssertEqual(other?.displayName, "Codex other")
    }

    /// 모델 턴을 시작하면 안 된다 — account snapshot 만 요청해야 한다.
    func testCodexRequestOnlyAsksForRateLimits() throws {
        let lines = LimitsReader.codexRequestLines()
        XCTAssertEqual(lines.count, 3)

        let methods = try lines.map { line -> String in
            let obj = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            return try XCTUnwrap(obj["method"] as? String)
        }
        XCTAssertEqual(methods, ["initialize", "initialized", "account/rateLimits/read"])
        XCTAssertFalse(lines.joined().contains("sendUserMessage"), "모델 턴을 요청하고 있다")

        // 응답 id 는 1 — `result(in:responseID:)` 가 이 값으로 찾는다.
        let last = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(lines[2].utf8)) as? [String: Any])
        XCTAssertEqual(last["id"] as? Int, 1)
    }

    // MARK: JSON-RPC 응답 골라내기

    func testPicksResultForTheRequestedIdOnly() throws {
        let stream = """
        {"id":0,"result":{"capabilities":{}}}
        {"method":"notify","params":{}}
        {"id":1,"result":{"rateLimits":{"limitId":"codex"}}}
        """
        let data = try XCTUnwrap(LimitsReader.result(in: Data(stream.utf8), responseID: 1))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(obj["rateLimits"])

        XCTAssertNil(try LimitsReader.result(in: Data(stream.utf8), responseID: 7),
                     "없는 id 에 응답을 만들어냈다")
    }

    /// 응답이 아직 안 왔을 때(스트림이 일부만 쓰였을 때) nil 이어야 폴링이 계속된다.
    func testPartialStreamReturnsNilInsteadOfThrowing() throws {
        XCTAssertNil(try LimitsReader.result(in: Data("{\"id\":1,\"resu".utf8), responseID: 1))
        XCTAssertNil(try LimitsReader.result(in: Data(), responseID: 1))
    }

    func testRpcErrorIsThrownNotSwallowed() {
        let stream = #"{"id":1,"error":{"code":-32601,"message":"method not found"}}"#
        XCTAssertThrowsError(try LimitsReader.result(in: Data(stream.utf8), responseID: 1)) { error in
            guard case LimitsReader.RunnerError.rpc(let message) = error else {
                return XCTFail("RPC 오류가 다른 타입으로 왔다: \(error)")
            }
            XCTAssertEqual(message, "method not found")
        }
    }

    // MARK: Keychain 자격증명 파싱

    func testExtractsAccessTokenFromCredential() {
        let json = """
        {"claudeAiOauth":{"accessToken":"sk-ant-oat01-XXXX","expiresAt":1788957496000,
        "subscriptionType":"max","rateLimitTier":"default_claude_max_20x"}}
        """
        XCTAssertEqual(LimitsReader.accessToken(fromCredential: Data(json.utf8)),
                       "sk-ant-oat01-XXXX")
    }

    /// 로그아웃 상태는 명시적 JSON `null` 로 저장된다. `!= nil` 로 검사하면 `NSNull` 때문에
    /// "값 있음"으로 오판한다 — 딕셔너리 캐스팅으로 판단해야 nil 이 나온다.
    func testNullOauthIsTreatedAsMissingNotPresent() {
        XCTAssertNil(LimitsReader.accessToken(fromCredential: Data(#"{"claudeAiOauth":null}"#.utf8)))
    }

    /// MCP 서버 OAuth 만 담긴 항목도 있다(Claude Code 2.1.x). 계정 토큰이 아니므로 nil.
    func testMcpOnlyCredentialYieldsNoToken() {
        let json = #"{"mcpOAuth":{"server":{"accessToken":"not-the-account-token"}}}"#
        XCTAssertNil(LimitsReader.accessToken(fromCredential: Data(json.utf8)))
    }

    func testMalformedCredentialYieldsNoToken() {
        XCTAssertNil(LimitsReader.accessToken(fromCredential: Data("깨진 JSON {{".utf8)))
        XCTAssertNil(LimitsReader.accessToken(fromCredential: Data()))
        // 빈 문자열 토큰도 토큰이 아니다.
        XCTAssertNil(LimitsReader.accessToken(
            fromCredential: Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)))
    }

    /// 키체인 항목이 여러 개면 계정 이름으로 하나씩 봐야 한다 — 순서를 유지하고 중복은 지운다.
    func testAccountNamesArePreservedAndDeduplicated() {
        let rows: [[String: Any]] = [
            [kSecAttrAccount as String: "alice"],
            [kSecAttrAccount as String: "unknown"],
            [kSecAttrAccount as String: "alice"],
            [kSecAttrAccount as String: ""],
            ["other": "x"],
        ]
        XCTAssertEqual(LimitsReader.accountNames(from: rows), ["alice", "unknown"])
        XCTAssertEqual(LimitsReader.accountNames(from: nil), [])
        XCTAssertEqual(LimitsReader.accountNames(from: [kSecAttrAccount as String: "solo"]), ["solo"])
    }

    // MARK: 스냅샷 표시값

    func testHighestPicksTheMostBurnedWindow() {
        let snap = LimitsSnapshot(windows: [
            .init(key: "a", name: "a", kind: .session, utilization: 30),
            .init(key: "b", name: "b", kind: .weekly, utilization: 91),
            .init(key: "c", name: "c", kind: .session, utilization: 12),
        ], isReady: true)
        XCTAssertEqual(snap.highest?.key, "b")
        XCTAssertNil(LimitsSnapshot().highest)
    }

    /// 아무것도 못 읽으면 `isReady` 가 false 여야 한다 — 그래야 시드가 미뤄지고 소급 지급이 없다.
    func testEmptySnapshotIsNotReady() {
        XCTAssertFalse(LimitsSnapshot().isReady)
        XCTAssertTrue(LimitsSnapshot().windows.isEmpty)
    }

    /// 창 종류와 보너스 금액이 밸런스 상수와 연결돼 있어야 한다 — 두 곳에 숫자를 따로 두면 어긋난다.
    func testWindowKindBonusComesFromBalance() {
        XCTAssertEqual(LimitWindowInfo.WindowKind.session.bonusRaw,
                       PlantBalance.windowBonusSession)
        XCTAssertEqual(LimitWindowInfo.WindowKind.weekly.bonusRaw,
                       PlantBalance.windowBonusWeekly)
    }

    /// 프롬프트 없는 조회 쿼리에 두 정책이 다 들어가야 한다 —
    /// 현행 `LAContext.interactionNotAllowed` 만으로는 오래된 ACL 항목이 여전히 다이얼로그를 띄운다.
    /// 메뉴바 앱이 30초마다 키체인 창을 띄우면 아무도 못 쓴다.
    func testNoUIQueryCarriesBothPolicies() throws {
        let query = LimitsReader.noUIQueryForTesting()
        XCTAssertNotNil(query[kSecUseAuthenticationContext as String],
                        "LAContext 가 안 들어갔다")
        let policy = try XCTUnwrap(query[kSecUseAuthenticationUI as String] as? String)
        // 값을 리터럴로 못박는다. `kSecUseAuthenticationUIFail` 을 여기서 참조하면
        // 그 자체가 deprecation 경고를 만들어(본체에서 없앤 이유가 바로 그것) 매 테스트마다 뜬다.
        // 값이 바뀌면 심볼 조회가 다른 문자열을 돌려주므로 이 단정이 깨진다 — 신호는 같다.
        XCTAssertEqual(policy, "u_AuthUIF", "정책 문자열이 바뀌었다 — 프롬프트가 뜰 수 있다")
    }

    /// codex 바이너리를 못 찾으면 nil — 예외가 아니다. Codex 를 안 쓰는 사람의 정상 상태다.
    func testCodexBinaryLookupIsOptionalNotFatal() {
        // 실제 존재 여부는 환경에 따라 다르므로 크래시하지 않는 것만 본다.
        _ = LimitsReader.codexBinary()
    }
}
