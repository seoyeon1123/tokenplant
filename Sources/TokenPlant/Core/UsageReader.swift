import Foundation

// 로컬 로그에서 오늘 토큰을 읽는다. 별도 CLI·로그인·네트워크가 없다.
//
// 포크에 합칠 때는 이 파일을 버리고 PokeTokenBar 의 `LocalUsageReader`(11개 도구, 1,654줄)를 쓴다.
// 지금은 Claude Code + Codex 두 개만 — 실측에서 이 둘이 사용량의 전부였다.

/// 큰 파일을 한 줄씩 읽는다. 하루치 세션도 수백 MB가 되므로 통째로 String 에 담으면 안 된다.
final class LineReader {
    private let handle: FileHandle
    private var buffer = Data()
    private var reachedEOF = false
    private let chunkSize = 1 << 16
    private let newline = UInt8(ascii: "\n")

    init?(url: URL) {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        handle = h
    }

    deinit { try? handle.close() }

    func nextLine() -> Data? {
        while true {
            if let i = buffer.firstIndex(of: newline) {
                let line = Data(buffer[buffer.startIndex..<i])
                buffer = Data(buffer[buffer.index(after: i)...])
                return line
            }
            if reachedEOF {
                if buffer.isEmpty { return nil }
                let rest = buffer
                buffer = Data()
                return rest
            }
            if let chunk = (try? handle.read(upToCount: chunkSize)) ?? nil, !chunk.isEmpty {
                buffer.append(chunk)
            } else {
                reachedEOF = true
            }
        }
    }
}

/// 오늘 사용량을 프로바이더별로 모아 돌려준다.
struct UsageSnapshot: Sendable {
    var byProvider: [String: TokenDelta] = [:]
    /// 읽다 실패한 파일 수 — 0이 아니면 상태 문구에 표시할 수 있다.
    var skippedFiles = 0
    /// 읽기 자체가 불가능한 이유(로그 폴더 없음 등). 있으면 화면에 그대로 띄운다.
    var note: String?

    var total: TokenDelta { byProvider.values.reduce(TokenDelta()) { $0 + $1 } }
}

enum UsageReader {

    /// 로그 뿌리. 테스트가 픽스처 폴더를 꽂을 수 있게 파라미터로 뺐다 —
    /// 홈 경로를 하드코딩하면 파싱을 실제 로그 없이 검증할 방법이 없다.
    static var defaultClaudeRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    static var defaultCodexRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    /// 두 프로바이더를 모아 읽는다. IO 라 백그라운드에서 호출한다.
    static func readToday(_ today: String = DayKey.make(Date()),
                          claudeRoot: URL? = nil,
                          codexRoot: URL? = nil) -> UsageSnapshot {
        var snap = UsageSnapshot()
        // 로그 뿌리가 **둘 다 없으면** 그걸 말해줘야 한다.
        // 예전엔 `jsonlFiles` 가 nil 을 돌려주고 `skippedFiles` 는 0 이라, 화면은
        // "오늘 아직 쓴 토큰이 없어요" 만 띄우고 영원히 아무 일도 안 일어났다.
        // 경로가 다른 사람·권한이 막힌 사람은 앱이 고장난 건지 자기가 안 쓴 건지 알 수 없었다.
        let fm = FileManager.default
        let cExists = fm.fileExists(atPath: (claudeRoot ?? defaultClaudeRoot).path)
        let xExists = fm.fileExists(atPath: (codexRoot ?? defaultCodexRoot).path)
        if !cExists && !xExists {
            snap.note = "로그 폴더를 못 찾았어요 (~/.claude/projects · ~/.codex/sessions)"
            return snap
        }
        // 30초마다 부르는 경로라 **이어 읽는다.** 실측 하루 74MB 를 매번 처음부터 파싱하면
        // 릴리스 빌드로도 1.9초 — 30초마다 코어 하나의 6% 를 계속 먹고, 하루가 갈수록 는다.
        let (claude, s1) = ClaudeTailReader.shared.read(today: today, root: claudeRoot ?? defaultClaudeRoot)
        if !claude.isZero { snap.byProvider["claude"] = claude }
        let (codex, s2) = readCodex(today: today, root: codexRoot)
        if !codex.isZero { snap.byProvider["codex"] = codex }
        snap.skippedFiles = s1 + s2
        return snap
    }

    /// 최근 N일치를 **날짜별로** 한 번에 읽는다. 설치할 때 딱 한 번 쓴다.
    ///
    /// 왜 필요한가: `dailyRaw` 가 설치 시점부터 빈 상태로 시작해서, 로그에 몇 달치가 있는데도
    /// "최근 14일 평균"이 사실은 "설치 후 며칠 평균"이었다. 그동안은 표본이 모자라
    /// 가격표가 **남의 기본값**으로 환산됐다.
    ///
    /// **적립은 하지 않는다.** 여기서 읽은 건 오직 *재기* 위한 것이고, 지갑과 성장은
    /// 여전히 첫날 상한을 지나서 들어온다. 안 그러면 설치하자마자 2주치가 쏟아진다.
    static func readRecent(days: Int,
                           today: String = DayKey.make(Date()),
                           claudeRoot: URL? = nil,
                           codexRoot: URL? = nil) -> [String: TokenDelta] {
        readRecentByProvider(days: days, today: today, claudeRoot: claudeRoot, codexRoot: codexRoot)
            .mapValues { $0.values.reduce(TokenDelta()) { $0 + $1 } }
            .filter { !$0.value.isZero }
    }

    /// 앱이 꺼져 있던 날들을 **프로바이더별로** 읽는다(`PlantEngine.catchUp` 용).
    ///
    /// 백필과 다른 점은 Codex 다. 백필은 "하루가 얼마인가"를 재는 거라 세션을 시작일에 몰아도
    /// 되지만, 여기서 읽은 건 **실제로 적립된다.** 그래서 그날 폴더에 있고 **그날 끝난**
    /// 세션만 센다 — 나중에 이어 쓴 세션의 누적값에는 다른 날 몫이 섞여 있어 과다 적립된다.
    /// 모자라게 세는 쪽을 고른다.
    static func readDays(_ days: [String],
                         claudeRoot: URL? = nil,
                         codexRoot: URL? = nil) -> [String: [String: TokenDelta]] {
        guard let newest = days.max(), let oldest = days.min() else { return [:] }
        let span = DayKey.days(from: oldest, to: newest) + 1
        return readRecentByProvider(days: span, today: newest, claudeRoot: claudeRoot,
                                    codexRoot: codexRoot, codexEndedThatDayOnly: true)
            .filter { days.contains($0.key) }
    }

    static func readRecentByProvider(days: Int,
                                     today: String,
                                     claudeRoot: URL? = nil,
                                     codexRoot: URL? = nil,
                                     codexEndedThatDayOnly: Bool = false) -> [String: [String: TokenDelta]] {
        var wanted: [String] = []
        guard let todayDate = DayKey.parse(today) else { return [:] }
        for back in 0..<max(1, days) {
            guard let d = DayKey.gregorian.date(byAdding: .day, value: -back, to: todayDate) else { continue }
            wanted.append(DayKey.make(d))
        }
        let wantedSet = Set(wanted)
        var out: [String: [String: TokenDelta]] = [:]

        // ── Claude Code: 파일을 한 번만 훑고 줄마다 날짜를 보고 통에 담는다.
        // 날짜별로 14번 훑으면 같은 파일을 14번 파싱한다.
        let croot = claudeRoot ?? defaultClaudeRoot
        if FileManager.default.fileExists(atPath: croot.path) {
            var windows: [String: DayWindow] = [:]
            for day in wanted { windows[day] = utcWindow(forLocalDay: day) }

            let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
            let oldest = wanted.min() ?? today
            if let e = FileManager.default.enumerator(at: croot, includingPropertiesForKeys: keys,
                                                     options: [.skipsHiddenFiles]) {
                var seen = Set<String>()
                for case let url as URL in e {
                    guard url.pathExtension == "jsonl" else { continue }
                    let values = try? url.resourceValues(forKeys: Set(keys))
                    guard values?.isRegularFile == true else { continue }
                    // 창보다 오래된 파일엔 창 안의 줄이 있을 수 없다.
                    if let m = values?.contentModificationDate, DayKey.make(m) < oldest { continue }
                    guard let reader = LineReader(url: url) else { continue }

                    while let line = reader.nextLine() {
                        guard line.count > 2,
                              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                              let ts = obj["timestamp"] as? String
                        else { continue }
                        // 어느 날의 줄인지 찾는다. 창은 14개뿐이라 선형 탐색으로 충분하다.
                        var day: String?
                        // `windows` 의 값은 옵셔널이 아니다 — `windows[day] = nil` 은 값을 넣는 게
                        // 아니라 키를 지우는 것이라, 만들 때 옵셔널을 대입해도 담기는 건 non-optional 이다.
                        for (k, w) in windows where w.contains(ts) { day = k; break }
                        guard let day else { continue }

                        // 중복은 **날짜를 가리지 않고** 걸러야 한다 —
                        // 같은 메시지가 여러 세션 파일에 퍼져 있다.
                        let dedupe = (obj["requestId"] as? String)
                            ?? ((obj["message"] as? [String: Any])?["id"] as? String)
                            ?? (obj["uuid"] as? String)
                        if let dedupe {
                            if seen.contains(dedupe) { continue }
                            seen.insert(dedupe)
                        }
                        guard let usage = findUsage(obj) else { continue }
                        out[day, default: [:]]["claude"] = (out[day]?["claude"] ?? TokenDelta()) + usage
                    }
                }
            }
        }

        // ── Codex: 경로에 날짜가 있어 그 날 폴더만 보면 된다.
        let xroot = codexRoot ?? defaultCodexRoot
        for day in wanted {
            let parts = day.split(separator: "-")
            guard parts.count == 3 else { continue }
            let dir = xroot.appendingPathComponent("\(parts[0])/\(parts[1])/\(parts[2])", isDirectory: true)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where name.hasSuffix(".jsonl") {
                let url = dir.appendingPathComponent(name)
                if codexEndedThatDayOnly {
                    guard let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                            .contentModificationDate, DayKey.make(m) == day else { continue }
                }
                guard let tu = lastTotalTokenUsage(url) else { continue }
                out[day, default: [:]]["codex"] = (out[day]?["codex"] ?? TokenDelta()) + tu
            }
        }

        return out.filter { wantedSet.contains($0.key) }
            .mapValues { $0.filter { !$0.value.isZero } }
            .filter { !$0.value.isEmpty }
    }

    // MARK: Claude Code

    /// `~/.claude/projects/**/*.jsonl` — 메시지마다 `message.usage`.
    ///
    /// 같은 메시지가 여러 세션 파일에 중복으로 나타난다(실측: 8,019건 중 10,179건이 중복).
    /// `requestId` → `message.id` → `uuid` 순으로 걸러야 물이 두 배로 들어가지 않는다.
    static func readClaudeCode(today: String, root: URL? = nil) -> (TokenDelta, Int) {
        let root = root ?? defaultClaudeRoot
        guard let window = utcWindow(forLocalDay: today),
              let files = jsonlFiles(under: root, modifiedOn: today) else { return (TokenDelta(), 0) }

        var total = TokenDelta()
        var seen = Set<String>()
        var skipped = 0

        for file in files {
            guard let reader = LineReader(url: file) else { skipped += 1; continue }
            while let line = reader.nextLine() {
                if let usage = claudeUsage(line: line, window: window, seen: &seen) {
                    total = total + usage
                }
            }
        }
        return (total, skipped)
    }

    /// 한 줄 → 오늘 몫 사용량. 중복이면 nil. 전체 읽기와 이어 읽기가 **같은 판정**을 쓴다.
    static func claudeUsage(line: Data, window: DayWindow, seen: inout Set<String>) -> TokenDelta? {
        guard line.count > 2,
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        else { return nil }

        // 오늘 것만. 타임스탬프가 없으면 건너뛴다(파일 mtime 만으로는 못 믿는다).
        guard let ts = obj["timestamp"] as? String, window.contains(ts) else { return nil }

        let key = (obj["requestId"] as? String)
            ?? ((obj["message"] as? [String: Any])?["id"] as? String)
            ?? (obj["uuid"] as? String)
        if let key {
            if seen.contains(key) { return nil }
            seen.insert(key)
        }
        return findUsage(obj)
    }

    /// 중첩 어디에 있든 usage 를 찾는다. 스키마가 버전마다 조금씩 움직인다.
    static func findUsage(_ obj: Any) -> TokenDelta? {
        if let d = obj as? [String: Any] {
            if d["input_tokens"] != nil || d["output_tokens"] != nil {
                return TokenDelta(input: intOf(d["input_tokens"]),
                                  output: intOf(d["output_tokens"]),
                                  cacheWrite: intOf(d["cache_creation_input_tokens"]),
                                  cacheRead: intOf(d["cache_read_input_tokens"]))
            }
            for v in d.values { if let found = findUsage(v) { return found } }
        } else if let a = obj as? [Any] {
            for v in a { if let found = findUsage(v) { return found } }
        }
        return nil
    }

    // MARK: Codex

    /// `~/.codex/sessions/YYYY/MM/DD/*.jsonl` — 경로에 날짜가 있어 오늘 폴더만 보면 된다.
    ///
    /// 턴마다 `payload.info.total_token_usage`(누적)가 실리므로 **파일 끝에서 거꾸로** 읽어
    /// 마지막 누적값만 집는다. 실측에서 세션 파일이 2.2GB였다 — 전체 파싱은 선택지가 아니다.
    /// `cached_input_tokens` 는 `input_tokens` 에 포함된 값이라 신규 입력은 둘의 차다.
    static func readCodex(today: String, root: URL? = nil) -> (TokenDelta, Int) {
        let parts = today.split(separator: "-")
        guard parts.count == 3 else { return (TokenDelta(), 0) }
        let dir = (root ?? defaultCodexRoot)
            .appendingPathComponent("\(parts[0])/\(parts[1])/\(parts[2])", isDirectory: true)

        // 오늘 폴더가 없어도 **빠져나가지 않는다** — 오늘 새 세션이 없을 뿐, 어제 시작한 세션을
        // 오늘 이어 쓰고 있을 수 있다(자정 직후가 늘 그렇다).
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []

        var total = TokenDelta()
        var skipped = 0
        for name in names where name.hasSuffix(".jsonl") {
            let url = dir.appendingPathComponent(name)
            guard let tu = lastTotalTokenUsage(url) else {
                // 막 시작해서 아직 `token_count` 가 없는 세션은 **못 읽은 게 아니다.**
                // 그걸 셌더니 Codex 만 쓰는 사람에게 세션을 열 때마다 "로그 1개를 읽지 못했어요"가 떴다.
                if !FileManager.default.isReadableFile(atPath: url.path) { skipped += 1 }
                continue
            }
            total = total + tu
        }
        total = total + carriedOverCodex(today: today, root: root ?? defaultCodexRoot)
        return (total, skipped)
    }

    /// 지난 폴더에 있는데 **오늘도 이어 쓴** 세션의 오늘 몫.
    ///
    /// Codex 는 세션을 **시작한 날** 폴더에 파일을 두고 끝까지 거기에 이어 쓴다(`resume` 도 같다).
    /// 오늘 폴더만 보면 자정을 넘긴 세션, 며칠 전 세션을 다시 연 경우의 오늘 사용량이 통째로 빠졌다.
    ///
    /// 파일의 누적값은 세션 전체라, 오늘 몫 = 마지막 누적 − **오늘 0시 직전** 누적이다.
    /// 0시 직전 값을 확정할 수 없으면(타임스탬프 없는 옛 형식, 너무 멀리 있음) 그 파일은 **안 센다** —
    /// 모르는 걸 전부 오늘로 치면 며칠치가 한꺼번에 들어온다.
    static func carriedOverCodex(today: String, root: URL, lookbackDays: Int = 30) -> TokenDelta {
        guard let window = utcWindow(forLocalDay: today) else { return TokenDelta() }
        var total = TokenDelta()
        for back in 1...lookbackDays {
            guard let day = DayKey.shifted(today, by: -back) else { continue }
            let parts = day.split(separator: "-")
            let dir = root.appendingPathComponent("\(parts[0])/\(parts[1])/\(parts[2])", isDirectory: true)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where name.hasSuffix(".jsonl") {
                let url = dir.appendingPathComponent(name)
                // 오늘 안 건드린 파일엔 오늘 몫이 있을 수 없다.
                guard let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate, DayKey.make(m) == today,
                      let last = lastTotalTokenUsage(url),
                      let base = CodexMidnight.shared.baseline(url, today: today, before: window.start)
                else { continue }
                // 누적이 0시 직전보다 **작으면** 세션 카운터가 다시 시작된 것이다(같은 파일에 이어 쓴
                // resume 에서 실측: 240,988,725 → 180,698). 빼면 음수라 0이 돼서, 그날 그 세션 몫이
                // 통째로 빠졌다. 그땐 리셋 뒤 누적(`last`)을 오늘 몫으로 친다 — 리셋 전 오늘 몫은
                // 알 수 없어 덜 세지만, 0보다는 훨씬 가깝고 넘치게 셀 일은 없다.
                let d = last - base
                let reset = d.input < 0 || d.output < 0 || d.cacheRead < 0 || d.cacheWrite < 0
                total = total + (reset ? last : d)
            }
        }
        return total
    }

    /// `before`(UTC ISO) 보다 **앞선** 마지막 누적값. 거꾸로 훑는다.
    ///
    /// - 찾으면 그 값, 파일 처음까지 가도 앞선 값이 없으면 0(그 세션은 오늘 처음 썼다).
    /// - 타임스탬프 없는 누적 줄을 만나거나 `limit` 을 넘기면 nil — 확정할 수 없다.
    static func totalTokenUsage(_ url: URL, before: String, limit: Int = 256 << 20) -> TokenDelta? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let needle = Data("total_token_usage".utf8)
        let newline = UInt8(ascii: "\n")
        var pos = Int(size)
        var carry = Data()          // 청크 앞머리의 잘린 줄 — 다음(더 앞) 청크와 이어 붙인다
        var scanned = 0
        while pos > 0 {
            guard scanned < limit else { return nil }
            let n = min(1 << 20, pos)
            pos -= n
            scanned += n
            guard (try? handle.seek(toOffset: UInt64(pos))) != nil,
                  let chunk = (try? handle.read(upToCount: n)) ?? nil else { return nil }
            var data = chunk
            data.append(carry)
            // 파일 맨 앞이 아니면 첫 줄은 잘렸을 수 있다 — 떼어 두고 다음에 붙인다.
            var body = data[data.startIndex...]
            if pos > 0 {
                // 줄바꿈이 하나도 없으면 통째로 한 줄의 일부다 — 더 앞을 읽어야 한다.
                guard let nl = data.firstIndex(of: newline) else { carry = data; continue }
                carry = Data(data[data.startIndex..<nl])
                body = data[data.index(after: nl)...]
            } else {
                carry = Data()
            }
            for line in body.split(separator: newline).reversed() where line.range(of: needle) != nil {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      let payload = obj["payload"] as? [String: Any],
                      let info = payload["info"] as? [String: Any],
                      let tu = info["total_token_usage"] as? [String: Any] else { continue }
                guard let ts = obj["timestamp"] as? String else { return nil }
                guard String(ts.prefix(19)) < before else { continue }
                let input = intOf(tu["input_tokens"])
                let cached = intOf(tu["cached_input_tokens"])
                return TokenDelta(input: max(0, input - cached), output: intOf(tu["output_tokens"]),
                                  cacheWrite: 0, cacheRead: cached)
            }
        }
        return TokenDelta()
    }

    /// 파일 끝에서 16MB 까지 거꾸로 훑어 마지막 `total_token_usage` 를 찾는다.
    static func lastTotalTokenUsage(_ url: URL) -> TokenDelta? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > 0 else { return nil }

        let needle = Data("total_token_usage".utf8)
        var pos = Int(size)
        var buffer = Data()
        let step = 1 << 20
        let limit = 16 << 20

        while pos > 0, buffer.count < limit {
            let readSize = min(step, pos)
            pos -= readSize
            guard (try? handle.seek(toOffset: UInt64(pos))) != nil,
                  let chunk = (try? handle.read(upToCount: readSize)) ?? nil else { return nil }
            buffer = chunk + buffer

            guard buffer.range(of: needle) != nil else { continue }
            // 뒤에서부터 첫 매칭 줄을 쓴다 — 그게 가장 최신 누적값이다.
            for line in buffer.split(separator: UInt8(ascii: "\n")).reversed() {
                guard line.range(of: needle) != nil,
                      let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      let payload = obj["payload"] as? [String: Any],
                      let info = payload["info"] as? [String: Any],
                      let tu = info["total_token_usage"] as? [String: Any]
                else { continue }

                let input = intOf(tu["input_tokens"])
                let cached = intOf(tu["cached_input_tokens"])
                return TokenDelta(input: max(0, input - cached),
                                  output: intOf(tu["output_tokens"]),
                                  cacheWrite: 0,
                                  cacheRead: cached)
            }
        }
        return nil
    }

    // MARK: 파일 훑기

    /// 오늘 수정된 `.jsonl` 만 고른다. 며칠 전 파일을 매번 파싱하면 갱신이 몇 초씩 걸린다.
    static func jsonlFiles(under root: URL, modifiedOn today: String) -> [URL]? {
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                     options: [.skipsHiddenFiles]) else { return nil }
        var out: [URL] = []
        for case let url as URL in e {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            // mtime 이 오늘이 아니면 오늘 줄이 있을 수 없다.
            if let m = values?.contentModificationDate, DayKey.make(m) != today { continue }
            out.append(url)
        }
        return out
    }

    /// 로컬 하루를 UTC ISO 문자열 구간으로 바꿔 둔다.
    ///
    /// 줄마다 `ISO8601DateFormatter` 로 파싱하면 하루치 수만 줄에서 느리고, 전역 포매터는
    /// Swift 6 에서 concurrency-safe 하지 않다(DateFormatter 는 Sendable 이 아니다).
    /// UTC ISO 문자열은 사전순 = 시간순이라 문자열 비교로 끝난다.
    /// 서울(UTC+9)에서 로컬 9월 9일은 UTC 9월 8일 15:00 ~ 9월 9일 15:00 이므로
    /// 앞 10자만 비교하면 틀린다 — 구간으로 잡아야 한다.
    struct DayWindow: Sendable {
        let start: String   // "2026-09-08T15:00:00"
        let end: String     // "2026-09-09T15:00:00"

        func contains(_ iso: String) -> Bool {
            let k = String(iso.prefix(19))   // 소수 초를 잘라 경계 비교를 안정화한다
            return k >= start && k < end
        }
    }

    static func utcWindow(forLocalDay day: String) -> DayWindow? {
        guard let start = DayKey.parse(day),
              let end = DayKey.gregorian.date(byAdding: .day, value: 1, to: start) else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return DayWindow(start: String(f.string(from: start).prefix(19)),
                         end: String(f.string(from: end).prefix(19)))
    }

    static func intOf(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let n = any as? NSNumber { return n.intValue }
        return 0
    }
}


/// 오늘 Claude Code 로그를 **이어서** 읽는다. 파일마다 어디까지 읽었는지 기억하고
/// 그 뒤에 붙은 줄만 파싱한다. 결과는 `readClaudeCode` 의 전체 읽기와 같다.
///
/// 처음부터 다시 읽는 경우: 날이 바뀜 · 뿌리가 바뀜 · 파일이 줄었거나 다른 파일로 바뀜(inode).
/// 그때 누계를 버리지 않고 이어 붙이면 이미 센 줄을 또 센다.
///
/// 끝의 반쪽 줄은 남겨 둔다 — Claude Code 가 쓰는 중인 줄이다. 다음 번에 줄바꿈이 붙으면 읽는다.
/// 다만 줄바꿈 없이 끝났어도 **완전한 JSON** 이면 바로 센다(전체 읽기가 그렇게 한다).
///
/// 락으로 한 번에 하나만 돈다. 감시견이 갱신을 겹치게 풀어줘도 누계가 꼬이지 않는다.
final class ClaudeTailReader: @unchecked Sendable {
    static let shared = ClaudeTailReader()

    private struct FileMark {
        var inode: UInt64
        var offset: UInt64
    }

    private let lock = NSLock()
    private var day = ""
    private var root = ""
    private var marks: [String: FileMark] = [:]
    private var seen = Set<String>()
    private var total = TokenDelta()

    private func reset(day: String, root: String) {
        self.day = day
        self.root = root
        marks = [:]
        seen = []
        total = TokenDelta()
    }

    func read(today: String, root url: URL) -> (TokenDelta, Int) {
        lock.lock(); defer { lock.unlock() }
        guard let window = UsageReader.utcWindow(forLocalDay: today),
              let files = UsageReader.jsonlFiles(under: url, modifiedOn: today) else {
            reset(day: "", root: "")
            return (TokenDelta(), 0)
        }
        if day != today || root != url.path { reset(day: today, root: url.path) }

        // 크기와 inode 를 먼저 다 본다. 하나라도 줄었거나 바뀌었으면 처음부터 —
        // 그 파일 몫만 빼는 건 불가능하다(중복 판정이 파일을 넘나든다).
        var stats: [String: (inode: UInt64, size: UInt64)] = [:]
        for f in files {
            guard let a = try? FileManager.default.attributesOfItem(atPath: f.path),
                  let size = (a[.size] as? NSNumber)?.uint64Value,
                  let inode = (a[.systemFileNumber] as? NSNumber)?.uint64Value else { continue }
            stats[f.path] = (inode, size)
        }
        let broken = marks.contains { path, m in
            guard let st = stats[path] else { return false }   // 사라진 파일은 이미 센 걸로 둔다
            return st.inode != m.inode || st.size < m.offset
        }
        if broken { reset(day: today, root: url.path) }

        var skipped = 0
        for f in files {
            guard let st = stats[f.path] else { skipped += 1; continue }
            let start = marks[f.path]?.offset ?? 0
            guard st.size > start else { continue }
            guard let h = try? FileHandle(forReadingFrom: f) else { skipped += 1; continue }
            defer { try? h.close() }
            guard (try? h.seek(toOffset: start)) != nil else { skipped += 1; continue }
            let consumed = consume(h, from: start, to: st.size, window: window)
            marks[f.path] = FileMark(inode: st.inode, offset: consumed)
        }
        return (total, skipped)
    }

    /// `start` 부터 읽어 완전한 줄만 센다. 어디까지 소비했는지 돌려준다.
    private func consume(_ h: FileHandle, from start: UInt64, to end: UInt64,
                         window: UsageReader.DayWindow) -> UInt64 {
        let newline = UInt8(ascii: "\n")
        var pos = start
        var carry = Data()
        while pos < end {
            let n = Int(min(UInt64(1 << 20), end - pos))
            guard let chunk = try? h.read(upToCount: n), !chunk.isEmpty else { break }
            pos += UInt64(chunk.count)
            carry.append(chunk)
            guard let last = carry.lastIndex(of: newline) else { continue }
            for line in carry[carry.startIndex..<last].split(separator: newline) {
                count(Data(line), window: window)
            }
            carry = Data(carry[carry.index(after: last)...])
        }
        // 끝에 남은 반쪽. 완전한 JSON 이면 센다 — 쓰는 중인 줄은 파싱이 안 되니 남는다.
        if !carry.isEmpty, (try? JSONSerialization.jsonObject(with: carry)) != nil {
            count(carry, window: window)
            carry = Data()
        }
        return pos - UInt64(carry.count)
    }

    private func count(_ line: Data, window: UsageReader.DayWindow) {
        if let usage = UsageReader.claudeUsage(line: line, window: window, seen: &seen) {
            total = total + usage
        }
    }
}

/// 지난 세션 파일의 "오늘 0시 직전 누적값" 캐시. 파일은 뒤로만 자라므로 하루에 한 번 재면 된다 —
/// 30초마다 거꾸로 수백 MB 를 훑을 이유가 없다.
final class CodexMidnight: @unchecked Sendable {
    static let shared = CodexMidnight()
    private let lock = NSLock()
    private var day = ""
    /// nil(확정 못 함)도 담는다 — 안 담으면 그 파일을 30초마다 256MB 씩 다시 훑는다.
    private var cache: [String: TokenDelta?] = [:]

    func baseline(_ url: URL, today: String, before: String) -> TokenDelta? {
        lock.lock(); defer { lock.unlock() }
        if day != today { day = today; cache = [:] }
        if let hit = cache[url.path] { return hit }
        let v = UsageReader.totalTokenUsage(url, before: before)
        cache[url.path] = .some(v)
        return v
    }
}
