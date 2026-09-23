import Foundation
import Darwin
import Security
import LocalAuthentication

// 한도 창(5시간 · 주간) 사용률을 읽는다.
//
// 이게 왜 필요한가: 누적 토큰만 보면 **만료를 모른다.** 5시간 창과 주간 창은 안 쓰면 그냥 사라진다.
// 토큰을 얼마나 썼는지와 한도까지 밀어붙였는지는 다른 수고라, 후자에 따로 값을 매긴다.
// 그 보상을 주는 신호가 이 파일이 읽는 "한도 창을 다 태웠다"다.
//
// 이 파일은 PokeTokenBar(MIT, Copyright (c) 2026 chattymin)의
// `OAuthLimitsProvider.swift` · `CodexRateLimitsProvider.swift` · `ProcessRunner.swift` 를
// 필요한 부분만 옮겨 슬림화한 것이다. 원본은 11개 프로바이더·플랜 표시·계정 라벨·알림까지 다루지만
// 여기서는 **사용률 숫자 하나**만 쓰므로 그 대부분이 필요 없다.
// 포크에 합칠 때는 이 파일을 버리고 원본 프로바이더를 그대로 쓴다.

/// 한도 창 하나. 보너스 지급의 단위다.
struct LimitWindowInfo: Sendable, Equatable, Identifiable {
    /// 안정 식별자. `resets_at` 처럼 매 조회마다 바뀌는 값은 넣지 않는다 —
    /// 키가 흔들리면 같은 창을 매번 새 창으로 보고 보너스를 계속 지급한다.
    let key: String
    let name: String
    let kind: WindowKind
    /// 0~100. 100 이상이면 그 창을 다 태웠다.
    let utilization: Double

    var id: String { key }

    enum WindowKind: String, Sendable, Codable {
        case session   // ≈5시간
        case weekly

        /// 이 창을 다 태웠을 때 지갑에 얹어주는 **원시 토큰**.
        /// 근거: 창을 태우는 건 "많이 썼다"가 아니라 "한도까지 밀어붙였다"는 별개의 수고다.
        /// 그리고 그 창은 안 쓰면 사라진다 — 사라지는 걸 남는 걸로 바꾸는 자리다.
        var bonusRaw: Int {
            switch self {
            case .session: return PlantBalance.windowBonusSession
            case .weekly: return PlantBalance.windowBonusWeekly
            }
        }
    }
}

/// 한도 조회 결과. 실패는 값으로 돌려준다 — 한도를 못 읽는 건 흔한 정상 상태다
/// (재로그인 필요, codex 미설치, 네트워크 없음). 그때도 성장은 그대로 굴러가야 한다.
struct LimitsSnapshot: Sendable {
    var windows: [LimitWindowInfo] = []
    /// 최소 한 프로바이더라도 읽혔는가. 첫 실행 시드 게이트에 쓴다 —
    /// 못 읽은 상태로 시드하면 이미 100%인 창을 나중에 소급 지급한다.
    var isReady = false
    var note: String?
    /// 429 를 받았는가. 받았으면 호출부가 **쉬어야 한다** — 같은 주기로 계속 때리면
    /// 제한이 안 풀린다. 이 플래그가 없을 때 30초마다 두들겨서 하루 2,880번을 보냈다.
    var rateLimited = false

    /// 표시용 — 사용률이 가장 높은 창.
    var highest: LimitWindowInfo? { windows.max { $0.utilization < $1.utilization } }
}

enum LimitsReader {

    /// 두 프로바이더를 모아 읽는다. Keychain·프로세스·네트워크를 타므로 메인 액터 밖에서 호출한다.
    static func read() async -> LimitsSnapshot {
        var snap = LimitsSnapshot()
        var notes: [String] = []

        do {
            let status = try await readClaude()
            snap.isReady = true
            snap.windows.append(contentsOf: status.grantableWindows)
        } catch {
            if case LimitsError.rateLimited = error { snap.rateLimited = true }
            notes.append(claudeNote(for: error))
        }

        do {
            let codex = try await readCodex()
            if let codex {
                snap.isReady = true
                snap.windows.append(contentsOf: codex)
            }
        } catch {
            notes.append("Codex 한도를 못 읽었어요")
        }

        snap.note = notes.isEmpty ? nil : notes.joined(separator: " · ")
        return snap
    }

    private static func claudeNote(for error: Error) -> String {
        guard let e = error as? LimitsError else { return "Claude 한도를 못 읽었어요" }
        switch e {
        case .credentialMissing, .credentialFormat:
            return "Claude Code 로그인이 필요해요"
        case .keychainInteractionNotAllowed:
            return "키체인 접근 권한이 필요해요"
        case .keychainUnavailable:
            return "키체인을 못 읽었어요"
        case .httpStatus(let code):
            return "Claude 한도 조회 실패 (\(code))"
        case .rateLimited:
            return "Claude 한도 조회가 제한됐어요"
        }
    }

    enum LimitsError: Error, Equatable {
        case credentialMissing
        case credentialFormat
        case keychainUnavailable(OSStatus)
        case keychainInteractionNotAllowed
        case httpStatus(Int)
        case rateLimited
    }

    // MARK: Claude — Keychain OAuth 토큰 → usage endpoint

    /// 비공식 endpoint 다. 실패해도 물 성장에는 영향이 없어야 한다(호출부가 값으로 받는다).
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    struct ClaudeLimits: Decodable, Sendable {
        var fiveHour: Window?
        var sevenDay: Window?
        /// 신형 응답. 레거시 `five_hour`/`seven_day` 가 **null 로 오고 이것만 채워지는 형태**가 관측된다
        /// (PokeTokenBar 픽스처 `testLimitStatusLegacyEmptyFallsBackToAllEntries`).
        /// 이걸 안 읽으면 그 응답에서는 창이 하나도 안 잡혀 보너스가 영영 안 나온다.
        var limits: [Entry]?

        struct Window: Decodable, Sendable {
            var utilization: Double?
            private enum CodingKeys: String, CodingKey { case utilization }
        }

        struct Entry: Decodable, Sendable {
            var kind: String?
            var percent: Double?
            var isActive: Bool?
            private enum CodingKeys: String, CodingKey {
                case kind, percent
                case isActive = "is_active"
            }
        }

        private enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case limits
        }

        /// 지급 대상 창 목록. 레거시 필드를 먼저 보고, 없으면 `limits[]` 에서 같은 두 창을 찾는다.
        ///
        /// `weekly_scoped`(모델별 주간)는 **제외한다** — 헤드라인 주간 창의 하위 창이라
        /// 같이 세면 한 번의 소진으로 두 번 지급된다.
        var grantableWindows: [LimitWindowInfo] {
            var out: [LimitWindowInfo] = []
            if let u = fiveHour?.utilization {
                out.append(.init(key: "claude.fiveHour", name: "Claude 5시간",
                                 kind: .session, utilization: u))
            } else if let e = limits?.first(where: { $0.kind == "session" }), let u = e.percent {
                out.append(.init(key: "claude.fiveHour", name: "Claude 5시간",
                                 kind: .session, utilization: u))
            }
            if let u = sevenDay?.utilization {
                out.append(.init(key: "claude.sevenDay", name: "Claude 주간",
                                 kind: .weekly, utilization: u))
            } else if let e = limits?.first(where: { $0.kind == "weekly_all" }), let u = e.percent {
                out.append(.init(key: "claude.sevenDay", name: "Claude 주간",
                                 kind: .weekly, utilization: u))
            }
            return out
        }
    }

    static func readClaude() async throws -> ClaudeLimits {
        let token = try keychainAccessToken()
        var request = URLRequest(url: usageURL, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw http.statusCode == 429 ? LimitsError.rateLimited
                                         : LimitsError.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode(ClaudeLimits.self, from: data)
    }

    /// Claude Code 가 Keychain 에 넣어둔 자격증명에서 access token 을 꺼낸다.
    ///
    /// 항목이 여러 개일 수 있다(MCP 서버 OAuth 전용 항목 + 계정 항목). `claudeAiOauth` 가
    /// 들어 있는 것만 계정 토큰이므로 계정을 열거해 하나씩 본다.
    /// `kSecMatchLimitAll` 과 `kSecReturnData` 는 같이 쓸 수 없어(errSecParam) 속성만 먼저 받는다.
    static func keychainAccessToken(allowPrompt: Bool = false) throws -> String {
        let service = "Claude Code-credentials"

        var attrQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        if !allowPrompt { applyNoUI(to: &attrQuery) }

        var attrItem: CFTypeRef?
        let attrStatus = SecItemCopyMatching(attrQuery as CFDictionary, &attrItem)
        let accounts = accountNames(from: attrItem)

        // 계정 속성을 못 얻으면 스코프 없는 단건 읽기로 폴백한다 — 항목이 하나뿐인 흔한 경우는 이걸로 된다.
        let candidates: [String?] = accounts.isEmpty ? [nil] : accounts.map { $0 }
        var lastStatus = attrStatus
        var sawItem = false

        for account in candidates {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            if let account { query[kSecAttrAccount as String] = account }
            if !allowPrompt { applyNoUI(to: &query) }

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecInteractionNotAllowed { throw LimitsError.keychainInteractionNotAllowed }
            lastStatus = status
            guard status == errSecSuccess, let data = item as? Data else { continue }
            sawItem = true
            if let token = accessToken(fromCredential: data) { return token }
        }

        if !sawItem, lastStatus != errSecSuccess {
            throw lastStatus == errSecItemNotFound ? LimitsError.credentialMissing
                                                  : LimitsError.keychainUnavailable(lastStatus)
        }
        throw LimitsError.credentialFormat
    }

    /// `claudeAiOauth.accessToken` 만 꺼낸다.
    ///
    /// `json["claudeAiOauth"] == nil` 로 검사하면 안 된다 — 로그아웃 상태는 명시적 JSON `null` 로
    /// 저장되고 그건 `NSNull` 로 디코드돼 `!= nil` 이 참이 된다. 딕셔너리 캐스팅으로 판단한다.
    static func accessToken(fromCredential data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        return token
    }

    static func accountNames(from item: Any?) -> [String] {
        let rows: [[String: Any]]
        if let array = item as? [[String: Any]] { rows = array }
        else if let one = item as? [String: Any] { rows = [one] }
        else { return [] }
        var seen = Set<String>()
        return rows.compactMap { $0[kSecAttrAccount as String] as? String }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// 프롬프트 없이 읽는다. 메뉴바 앱이 30초마다 키체인 다이얼로그를 띄우면 쓸 수가 없다.
    ///
    /// `LAContext.interactionNotAllowed` 이 현행 방식이지만, 오래된 ACL 상태의 항목은
    /// 구 `kSecUseAuthenticationUI` 정책이 함께 없으면 여전히 프롬프트를 띄운다(PokeTokenBar 실측).
    /// 그래서 둘 다 넣는다. 다만 `kSecUseAuthenticationUIFail` 상수를 직접 쓰면
    /// macOS 11 deprecation 경고가 매 빌드에 뜨므로 런타임에 심볼로 찾아 쓴다.
    private static func applyNoUI(to query: inout [String: Any]) {
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        query[kSecUseAuthenticationUI as String] = uiFailPolicy as CFString
    }

    /// 테스트가 쿼리를 들여다볼 수 있게 — 키체인을 실제로 건드리지 않고 정책이 붙었는지만 본다.
    static func noUIQueryForTesting() -> [String: Any] {
        var q: [String: Any] = [:]
        applyNoUI(to: &q)
        return q
    }

    /// 구 UI-fail 정책 문자열. Security.framework 에서 심볼로 읽고, 못 읽으면 알려진 값으로 떨어진다.
    private static let uiFailPolicy: String = {
        let path = "/System/Library/Frameworks/Security.framework/Security"
        guard let handle = dlopen(path, RTLD_NOW) else { return "u_AuthUIF" }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "kSecUseAuthenticationUIFail") else { return "u_AuthUIF" }
        let pointer = symbol.assumingMemoryBound(to: CFString?.self)
        return (pointer.pointee as String?) ?? "u_AuthUIF"
    }()

    // MARK: Codex — CLI app-server JSON-RPC

    struct CodexLimits: Decodable, Sendable {
        var rateLimits: Snapshot
        var rateLimitsByLimitId: [String: Snapshot]?

        struct Snapshot: Decodable, Sendable {
            var limitId: String?
            var limitName: String?
            var primary: Window?
            var secondary: Window?

            var displayName: String {
                let raw = limitName ?? limitId ?? "codex"
                let spaced = raw.replacingOccurrences(of: "_", with: " ")
                return spaced.prefix(1).uppercased() + spaced.dropFirst()
            }
        }

        struct Window: Decodable, Sendable {
            var usedPercent: Int
            var windowDurationMins: Int?
        }

        /// top-level 은 "codex" bucket 우선이라 나머지 bucket 은 byLimitId 에만 있다.
        /// 사전 순서는 비결정적이므로 정렬해 합친다 — 안 하면 창 키 순서가 실행마다 바뀐다.
        var snapshots: [Snapshot] {
            var out = [rateLimits]
            guard let byID = rateLimitsByLimitId else { return out }
            let primaryKey = rateLimits.limitId ?? "codex"
            for (id, snap) in byID.sorted(by: { $0.key < $1.key }) {
                if id == primaryKey { continue }
                if let sid = snap.limitId, sid == rateLimits.limitId { continue }
                out.append(snap)
            }
            return out
        }
    }

    /// ≤24시간(1440분)은 세션급, 초과는 주간급. 미상은 세션으로 본다(보수적 — 지급이 적은 쪽).
    static func windowKind(minutes: Int?) -> LimitWindowInfo.WindowKind {
        if let m = minutes, m > 1440 { return .weekly }
        return .session
    }

    static func readCodex() async throws -> [LimitWindowInfo]? {
        guard let binary = codexBinary() else { return nil }
        let data = try await runJSONRPC(binary: binary,
                                        arguments: ["app-server", "--stdio"],
                                        lines: codexRequestLines(),
                                        responseID: 1)
        let status = try JSONDecoder().decode(CodexLimits.self, from: data)

        var out: [LimitWindowInfo] = []
        for snap in status.snapshots {
            let bucket = snap.limitId ?? snap.limitName ?? "codex"
            if let p = snap.primary {
                out.append(.init(key: "codex.\(bucket).primary",
                                 name: "\(snap.displayName) \(windowLabel(p.windowDurationMins))",
                                 kind: windowKind(minutes: p.windowDurationMins),
                                 utilization: Double(p.usedPercent)))
            }
            if let s = snap.secondary {
                out.append(.init(key: "codex.\(bucket).secondary",
                                 name: "\(snap.displayName) \(windowLabel(s.windowDurationMins))",
                                 kind: windowKind(minutes: s.windowDurationMins),
                                 utilization: Double(s.usedPercent)))
            }
        }
        return out
    }

    static func windowLabel(_ minutes: Int?) -> String {
        switch minutes {
        case 300: return "5시간"
        case 10_080: return "주간"
        case let m? where m >= 60 && m % 60 == 0: return "\(m / 60)시간"
        case let m?: return "\(m)분"
        case nil: return "한도"
        }
    }

    /// 모델 턴을 시작하지 않는다 — account snapshot 만 요청한다.
    static func codexRequestLines() -> [String] {
        let messages: [[String: Any]] = [
            ["method": "initialize", "id": 0,
             "params": ["clientInfo": ["name": "token_mac", "title": "TokenPlant", "version": "0.1.0"],
                        "capabilities": ["experimentalApi": true]]],
            ["method": "initialized", "params": [:]],
            ["method": "account/rateLimits/read", "id": 1, "params": [:]],
        ]
        return messages.compactMap {
            guard let d = try? JSONSerialization.data(withJSONObject: $0) else { return nil }
            return String(decoding: d, as: UTF8.self)
        }
    }

    /// GUI 앱의 최소 PATH 로는 버전 매니저 shim 을 못 찾는다. 흔한 설치 위치를 직접 훑는다.
    static func codexBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/.codex/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            // ChatGPT.app 이 codex CLI 를 품고 있다. 별도 설치가 없는 사용자에게는 이게 유일한 경로라
            // 목록에 두되, 전용 설치가 이기도록 맨 뒤에 둔다.
            "/Applications/ChatGPT.app/Contents/Resources/codex",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    enum RunnerError: Error {
        case timeout
        case noResponse
        case rpc(String)
    }

    /// stdin 으로 JSON-RPC 를 밀어넣고 지정 id 의 result 를 기다린다.
    ///
    /// stdout 을 파이프가 아니라 **파일**로 받는다: 파이프 버퍼가 차면 자식이 블록되는데
    /// 이 앱은 그걸 풀어줄 리더 루프를 따로 돌리지 않는다.
    static func runJSONRPC(binary: String, arguments: [String],
                           lines: [String], responseID: Int,
                           timeout: TimeInterval = 20) async throws -> Data {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenplant-\(UUID().uuidString).jsonl")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: out) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.qualityOfService = .utility
        let handle = try FileHandle(forWritingTo: out)
        defer { try? handle.close() }
        let stdin = Pipe()
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        process.standardInput = stdin

        defer { if process.isRunning { process.terminate() } }
        try process.run()

        // 자식이 stdin 을 읽기 전에 죽으면 broken pipe 다. non-throwing write 는 SIGPIPE 로
        // 앱 전체를 죽이므로 throwing API + try? 로 EPIPE 를 삼킨다.
        let payload = lines.joined(separator: "\n") + "\n"
        try? stdin.fileHandleForWriting.write(contentsOf: Data(payload.utf8))
        stdin.fileHandleForWriting.closeFile()

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let r = try result(in: (try? Data(contentsOf: out)) ?? Data(), responseID: responseID) {
                return r
            }
            if !process.isRunning { break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        // 종료 직전 flush 가 마지막 읽기보다 늦게 도착할 수 있어 한 번 더 읽는다.
        if let r = try result(in: (try? Data(contentsOf: out)) ?? Data(), responseID: responseID) {
            return r
        }
        throw process.isRunning ? RunnerError.timeout : RunnerError.noResponse
    }

    static func result(in raw: Data, responseID: Int) throws -> Data? {
        guard let text = String(data: raw, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = obj["id"] as? NSNumber, id.intValue == responseID
            else { continue }
            if let error = obj["error"] as? [String: Any] {
                throw RunnerError.rpc(error["message"] as? String ?? "\(error)")
            }
            guard let result = obj["result"], JSONSerialization.isValidJSONObject(result) else { continue }
            return try JSONSerialization.data(withJSONObject: result)
        }
        return nil
    }
}
