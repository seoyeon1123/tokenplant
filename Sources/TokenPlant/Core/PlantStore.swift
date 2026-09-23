import Foundation
import Observation

/// @MainActor 껍데기. 상태 보관·파일 저장·연출 트리거만 하고, 판정은 전부 `PlantEngine` 이 한다.
/// PokeTokenBar 의 `CompanionStore` 자리를 대체하되 1,246줄이 아니라 이 정도로 끝나는 이유가 그것이다.
@MainActor
@Observable
final class PlantStore {
    private(set) var save = PlantSave()

    /// 지금 재생해야 하는 연출. 뷰가 소비하면 nil 로 돌린다.
    private(set) var celebration: PlantEvent?
    /// 같은 연출이 연달아 와도 뷰가 알아채도록 증가시키는 카운터.
    private(set) var celebrationSeq = 0

    /// 방금 쓴 아이템 — 거름과 분갈이 흙이 각각 다른 연출을 타야 한다.
    /// 단계 상승 연출(`celebration`)과 별개 신호다: 분갈이 흙으로 단계가 오르면 둘 다 재생된다.
    private(set) var itemEffect: ShopItem?
    private(set) var itemEffectSeq = 0

    /// 오늘 잔액에 들어온 물 / 오늘 원시 토큰 — 표시용.
    private(set) var todayWater = 0
    private(set) var todayRaw = 0

    /// 마지막으로 읽은 한도 창 상태. 홈에서 "다 채우면 +N mL" 을 보여주고, 100% 를 새로 넘으면
    /// 물통에 보너스가 들어간다. 못 읽어도 적립은 그대로 굴러간다 — 여기가 비어도 앱은 정상이다.
    private(set) var limits = LimitsSnapshot()
    /// 방금 한도 창으로 받은 원시 토큰 — 홈에 한 줄 띄운다.
    ///
    /// **언제 받았는지**를 같이 들고 있어야 한다. 값만 두면 메뉴바 앱이 며칠씩 켜져 있는 동안
    /// 첫 지급 문구가 영원히 안 사라지고, 그것도 "오늘" 받은 게 아닌 걸 오늘처럼 보여준다.
    private(set) var lastWindowBonus = 0
    private(set) var lastWindowBonusDay = ""

    /// 오늘 받은 창 보너스만 홈에 띄운다.
    var todayWindowBonus: Int { lastWindowBonusDay == today ? lastWindowBonus : 0 }
    /// 방금 아이템으로 들어간 물(mL) — 연출과 피드백 문구가 본다.
    private(set) var lastWaterGained = 0

    private let url: URL
    private var clock: () -> Date

    init(url: URL = PlantStore.defaultURL(), clock: @escaping () -> Date = Date.init) {
        self.url = url
        self.clock = clock
        load()
    }

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("TokenPlant", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    // MARK: 저장 · 로드

    private func load() {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(PlantSave.self, from: data) {
            save = decoded
        }
        // 첫 실행이면 씨앗을 심는다. 화분이 비어 있으면 게이지도 상태 문구도 그릴 게 없다.
        if save.pot == nil {
            PlantEngine.plantNewSeed(&save, roll: UInt64.random(in: 0..<1_000_000), now: clock())
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(save) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: 사용량 유입 (포크에서는 UsageStore 가 호출한다)

    /// 프로바이더별 **오늘 누적** 스냅샷. 증분 계산은 엔진이 한다.
    ///
    /// 여기 한 번 들어오면 화분이 자란다. 사용자가 누를 건 아무것도 없다 —
    /// 그게 이 앱의 약속이고, 상점은 그 위에 얹는 가속일 뿐이다.
    func update(todayUsageByProvider: [String: TokenDelta], todayDate: String) {
        let walletBefore = save.rawWallet
        let rawBefore = save.rawEarnedTotal

        PlantEngine.noteThirst(&save, today: todayDate)
        PlantEngine.ingest(&save, todayByProvider: todayUsageByProvider, today: todayDate, now: clock())

        // 오늘 표시값은 스냅샷 합으로 직접 계산한다 — 누적에서 빼면 날 넘어갈 때 틀어진다.
        let snapshot = todayUsageByProvider.values.reduce(TokenDelta()) { $0 + $1 }
        todayRaw = snapshot.raw
        todayWater = PlantBalance.water(from: snapshot)

        if save.rawWallet != walletBefore || save.rawEarnedTotal != rawBefore {
            persist()
        }
        // 목표 재조정은 **갱신마다** 다시 시도한다.
        //
        // 백필 안에서 한 번만 돌렸을 때 구멍이 있었다: 설치 시점에 로그가 아예 없는 사람
        // (막 Claude Code 를 깐 사람, 로그 경로가 다른 사람, 권한 실패)은 백필이 빈손으로
        // 돌아와 `dailyRaw` 가 비어 있고, 그러면 재조정이 no-op 이면서 `historyBackfilled` 만
        // 켜진다. 3일 뒤 실제 유입이 측정돼도 다시 잡을 기회가 없어서,
        // 하루 5M 쓰는 사람이 **11배 큰 목표(280일)** 에 영원히 갇혔다.
        //
        // 아래 가드가 안전을 맡는다: 측정이 됐고(3일), 아직 1단계도 안 넘은 그루만.
        refitUntouchedCycles()

        // **여기서 대기열을 비우지 않는다.**
        //
        // 비웠더니 앱의 핵심 약속이 깨졌다: 30초 티커가 팝오버가 닫힌 채로 돌면서
        // 단계 상승·이식 가능·새 씨앗 이벤트를 전부 뽑아 버리고, 사용자가 나중에 열면
        // `PotView.onAppear` 가 `celebrationSeq` 를 그대로 기준값으로 잡아 `onChange` 가
        // 안 터진다. 결과적으로 **연출은 팝오버가 열려 있는 순간에 티커가 돌 때만** 보였다.
        // "안 보고 있어도 자란다"가 이 앱의 전부인데, 그 성장의 결과를 못 보게 돼 있었다.
        //
        // 대기열은 세이브에 그대로 쌓이고(같은 종류는 합쳐지므로 무한정 안 큰다),
        // 팝오버가 열릴 때 `PotView.onAppear` 가 비운다.
    }

    /// 한도 창 상태를 받아 물통에 보너스를 넣는다.
    ///
    /// 사용량 유입과 분리한 이유: 한도 조회는 Keychain·프로세스·네트워크를 타서 실패가 흔하다.
    /// 물 성장이 그 실패에 묶이면 안 된다 — 한도를 못 읽는 날에도 화분은 자라야 한다.
    func applyLimits(_ snapshot: LimitsSnapshot) {
        limits = snapshot
        let gained = PlantEngine.grantWindowBonus(&save,
                                                  windows: snapshot.windows,
                                                  isReady: snapshot.isReady)
        if gained > 0 {
            lastWindowBonus = gained
            lastWindowBonusDay = today
            persist()
            pickCelebration()
        }
    }

    /// 설치 직후 한 번 — 과거 로그로 `dailyRaw`/`dailyWater` 만 채운다.
    ///
    /// **지갑과 성장은 건드리지 않는다.** 여기 들어온 건 오직 "이 사람 하루가 얼마인가"를
    /// 재기 위한 것이다. 적립까지 하면 설치하자마자 2주치가 쏟아져서 첫 화면이 거목이 된다.
    func backfillHistory(_ byDay: [String: TokenDelta]) {
        guard needsBackfill else { return }
        for (day, delta) in byDay {
            // 오늘은 건너뛴다. `readRecent` 가 오늘을 포함해서 돌려주는데 `ingest` 도 오늘을
            // 적립하므로, 넣으면 같은 날이 두 번 세어져 **하루 유입이 7% 부풀고**
            // 그 값이 14일 동안 모든 가격과 다음 사이클 목표에 들어간다.
            guard day != today else { continue }
            let clamped = delta.clampedToZero
            save.dailyRaw[day, default: 0] += clamped.raw
            let mL = PlantBalance.water(from: clamped)
            if mL > 0 { save.dailyWater[day, default: 0] += mL }
        }
        save.dailyRaw = PlantBalance.prunedDailyRaw(save.dailyRaw, today: today)
        save.dailyWater = PlantBalance.prunedDailyRaw(save.dailyWater, today: today)
        save.historyBackfilled = true
        refitUntouchedCycles()
        persist()
    }

    /// 초반 그루의 목표를 이 사람 속도로 다시 잡는다.
    /// **갱신마다 시도하되, 그루당 한 번만 · 줄이는 방향만.**
    ///
    /// 첫 그루는 `load()` 안에서 심긴다 — 그때 `dailyRaw` 가 비어 있어서 목표가
    /// `assumedDailyRaw`(하루 105M) 기준 422,576mL 로 박힌다. 하루 5M 쓰는 사람에게 **588일**,
    /// 그것도 첫날 상한으로 3~5단계까지 올라간 뒤 1년 반 동안 안 움직이는 상태다.
    /// 첫 그루가 리텐션을 결정하는데 그게 남의 값으로 정해져 있었다.
    ///
    /// 조건을 두 번 고쳤다:
    ///
    ///  - 처음엔 백필 안에서만 불렀다. 그런데 설치 시점에 로그가 아예 없는 사람은
    ///    백필이 빈손으로 돌아와 재조정이 no-op 이면서 `historyBackfilled` 만 켜져,
    ///    3일 뒤 실제 유입이 측정돼도 **다시 잡을 기회가 없었다.** → 갱신마다 시도한다.
    ///  - `stageIndex == 0` 만 봤다. 첫날 상한이 바로 3~5단계까지 밀어올려서
    ///    이 조건에 **한 번도** 걸리지 않았다. → 단계가 아니라 **줄이는 방향인지**로 판단한다.
    ///  - 그러자 이번엔 **쉬면 이득**이 됐다. 며칠 안 쓰면 14일 평균이 내려가 목표가 줄고,
    ///    "줄이는 방향만"이라 그대로 적용돼 진행도가 앞으로 뛴다. 실측으로 20일차에
    ///    안 쉰 사람 73.0% vs 사흘 쉰 사람 82.1%. → **그루당 한 번**으로 막는다.
    ///
    /// 실측: 로그 없이 설치한 하루 5M 사용자가 2일째에 422,576 → 36,848mL 로 잡히고
    /// "이식까지 567일" → "45일" 로 바뀐다. 그 전에는 첫 그루가 영영 완주하지 못했다.
    func refitUntouchedCycles() {
        // 측정이 되기 전에는 손대지 않는다. 안 그러면 기본값 ↔ 측정값 사이에서 목표가 흔들린다.
        guard dailyRateIsMeasured else { return }
        let fitted = PlantEngine.seedCycle(save)

        for key in [\PlantSave.pot, \PlantSave.pot2] {
            guard var p = save[keyPath: key] else { continue }

            // **그루당 한 번.** 매번 맞췄더니 며칠 쉰 사람의 목표가 같이 줄어서
            // 진행도가 앞으로 뛰었다(20일차에 안 쉰 73.0% vs 사흘 쉰 82.1%).
            // 스트릭이 빠짐을 벌주는데 여기서 보상하면 두 규칙이 반대로 간다.
            guard !p.cycleFitted else { continue }
            // **줄이는 방향만.** 늘리면 게이지가 뒤로 가고 "쓰면 자란다"가 깨진다.
            // 줄이는 건 반대로 진행도가 앞으로 뛰는 것이라 사용자가 손해 볼 게 없다.
            guard fitted < p.cycleWater else { continue }
            // 사이클 1/3 을 넘긴 그루는 그냥 둔다 — 그쯤이면 그 목표로 계획을 세웠다.
            guard p.water < p.cycleWater / 3 else { continue }

            p.cycleWater = fitted
            p.cycleFitted = true
            // 단계 임계값이 목표의 **비율**이라 목표가 줄면 단계가 올라간다.
            // `grow` 는 물이 들어올 때만 도니까 여기서 직접 맞춘다 —
            // 안 하면 게이지는 꽉 찼는데 스프라이트만 씨앗인 상태가 남는다.
            p.stageIndex = PlantBalance.stageIndex(forWater: p.water, cycle: fitted)
            save[keyPath: key] = p
        }
    }

    /// 아직 과거를 안 읽었나. 한 번만 읽고 표시해 둔다 —
    /// 매 실행마다 몇 달치를 훑으면 켤 때마다 느려진다.
    var needsBackfill: Bool { !save.historyBackfilled }

    // MARK: 행동

    /// 홈에서 이름을 붙인다 — 명패에 그대로 뜬다.
    func rename(_ name: String, slot: Int = 0) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? nil : trimmed
        if slot == 0 { save.pot?.nickname = value } else { save.pot2?.nickname = value }
        persist()
    }

    @discardableResult
    func buy(_ item: ShopItem) -> PurchaseResult {
        let r = PlantEngine.buy(item, &save)
        if r == .ok { persist() }
        return r
    }

    /// 방금 뽑기에서 나온 장식 키. 뽑기 결과는 mL 로 말할 수 없어서 따로 둔다 —
    /// `.ok(waterGained: 0)` 만 돌려주면 화면에 "장식 뽑기 사용"밖에 쓸 게 없고,
    /// 뭐가 나왔는지는 정원을 열어봐야 알게 된다. 그러면 누른 보람이 사라진다.
    private(set) var lastDecorFound: String?

    @discardableResult
    func use(_ item: ShopItem) -> UseResult {
        lastDecorFound = nil
        let before = Set(save.decorations)
        let r = PlantEngine.use(item, &save, today: today, now: clock())
        if case .ok(let gained) = r {
            if item == .decorBox {
                lastDecorFound = save.decorations.first { !before.contains($0) }
            }
            lastWaterGained = gained
            persist()
            itemEffect = item
            itemEffectSeq += 1
            pickCelebration()
        }
        return r
    }

    @discardableResult
    func transplant(slot: Int = 0) -> Bool {
        let ok = PlantEngine.transplant(&save, slot: slot,
                                        roll: UInt64.random(in: 0..<1_000_000), now: clock())
        if ok { persist(); pickCelebration() }
        return ok
    }

    // MARK: 연출

    /// 팝오버가 열릴 때 한 번 비운다.
    /// 3일 만에 열었다고 연출을 세 번 재생하면 안 되므로 대기열은 한 번에 비우고
    /// 가장 중요한 것 하나만 보여준다.
    func pickCelebration() {
        let events = PlantEngine.drainEvents(&save)
        guard !events.isEmpty else { return }
        // 순서의 근거: **한 번의 비움에 여러 이벤트가 같이 들어온다.**
        // 이식하면 `transplant` + `newSeed` 가 같이 쌓이고, 8단계에 닿으면 `levelUp` + `fruit` 가
        // 같이 쌓인다. 하나만 재생되므로 **더 드문 쪽**이 이겨야 한다.
        //
        //   `newSeed` > `transplant` — 28일을 기다린 보람은 "뭐가 나왔나"다. 이식 자체는 내가 누른 것.
        //   `fruit` > `levelUp`      — 열매는 그루당 한 번, 단계 상승은 아홉 번.
        //
        // 이 순서가 아니었을 때 `newSeed` 와 `fruit` 는 **한 번도 재생되지 않았다**(구조적으로).
        // 한도 창 보상은 성장보다 뒤 — 같은 갱신에서 단계가 올랐으면 그게 주인공이다.
        //
        // `thirsty` 는 **일부러 빠져 있다.** 목마름은 사건이 아니라 상태다(색이 이미 말해준다).
        // 여기 있었을 때는 `noteThirst` 가 30초마다 이벤트를 밀어넣고 → 여기서 뽑히고 →
        // `persist()` 가 돌아서, 물을 안 준 사람이 **하루 2,880번** 세이브를 다시 썼다.
        // `decor` 는 반대 이유로 넣었다 — 없으면 뽑기 이벤트가 뽑히지도 못하고 버려졌다.
        // `streakGift` 는 `decor` 보다 앞이다. 선물을 받은 날 마침 뽑기를 돌렸으면 둘이 같이
        // 쌓이는데, 장식이 이기면 **선물이 왔다는 사실 자체가 안 보인다**(창고에 조용히 들어간다).
        let priority = ["fruit", "newSeed", "transplant", "levelUp",
                        "streakGift", "decor", "ready", "window"]
        let chosen = priority.compactMap { key in events.first { $0.coalesceKey == key } }.first
        guard let chosen else { return }
        celebration = chosen
        celebrationSeq += 1
        persist()
    }

    // 뷰가 이벤트를 "소비"하는 함수는 두지 않는다. 화분이 두 개면 먼저 그려진 쪽이
    // 먹어버려 다른 쪽만 조용히 자란다. `celebrationSeq` 가 재생을 한 번만 통과시키고,
    // `celebration` 은 다음 이벤트가 올 때 덮어써진다.

    // MARK: 파생값

    var today: String { DayKey.make(clock()) }

    // MARK: 지갑 표시값

    /// 지갑에 있는 **원시 토큰**. 상점은 여기서 나간다. 성장은 안 건드린다.
    var wallet: Int { save.rawWallet }

    /// 지갑이 하루치의 몇 배인지 — 게이지 하나로 "얼마나 모았나"를 보여준다.
    /// 사이클(400,000mL) 대비로 재면 단위가 섞여 아무 뜻이 없으므로 하루치를 기준으로 쓴다.
    var walletShareOfDay: Double {
        min(1, Double(save.rawWallet) / Double(dailyRate))
    }

    /// 사용률이 가장 높은 한도 창 — 홈 한 줄에 쓴다.
    var topWindow: LimitWindowInfo? { limits.highest }

    /// 화면에 보여줄 화분 개수. 슬롯을 사면 2 — 엔진은 이미 둘 다 키운다.
    var slotCount: Int { save.hasPotSlot ? 2 : 1 }

    /// 슬롯별 화분. 0 = 첫 화분, 1 = 화분 슬롯으로 늘린 두 번째.
    func pot(_ slot: Int) -> PotState? { slot == 0 ? save.pot : save.pot2 }

    func species(_ slot: Int) -> PlantSpecies { pot(slot)?.species ?? PlantSpecies.catalog[0] }

    var pot: PotState? { save.pot }
    var species: PlantSpecies { species(0) }

    /// 시듦은 "며칠 물을 안 줬나" 라 저장 전체에 하나뿐이다 — 슬롯별로 갈리지 않는다.
    /// 목마름 0~1 — 색만 마른다. 누적 물은 안 깎인다.
    var wilt: Double { PlantEngine.thirstLevel(save, today: today) }

    var displayState: PlantStateKind {
        PlantEngine.displayState(save, today: today, now: clock())
    }

    func stageName(_ slot: Int) -> String {
        guard let p = pot(slot) else { return "씨앗" }
        return PotSprites.stages[min(p.stageIndex, PotSprites.stages.count - 1)].name
    }

    var stageName: String { stageName(0) }

    /// 현재 단계 구간 안에서의 진행률 0~1.
    func stageProgress(_ slot: Int) -> Double {
        guard let p = pot(slot) else { return 0 }
        let lo = p.threshold(stage: min(p.stageIndex, PlantBalance.stageCount - 1))
        guard let hi = p.nextThreshold, hi > lo else { return 1 }
        return min(1, max(0, Double(p.water - lo) / Double(hi - lo)))
    }

    var stageProgress: Double { stageProgress(0) }

    /// 다음 단계(또는 이식)까지 남은 물.
    func waterToNext(_ slot: Int) -> Int? {
        guard let p = pot(slot), let hi = p.nextThreshold else { return nil }
        return max(0, hi - p.water)
    }

    var waterToNext: Int? { waterToNext(0) }

    // MARK: 오늘이 평소보다 어땠나

    /// 비교 기준이 되는 "평소" — **오늘을 뺀** 최근 평균. 표본이 모자라면 nil.
    var baselineRate: Int? { PlantBalance.baselineRawRate(save.dailyRaw, today: today) }

    /// 오늘 ÷ 평소. 기준이 없으면 nil — 그때는 화면에 퍼센트를 아예 안 쓴다.
    /// 틀린 82% 는 아무 숫자도 안 쓴 것보다 나쁘다.
    var todayVsBaseline: Double? {
        guard let base = baselineRate, base > 0 else { return nil }
        return Double(todayRaw) / Double(base)
    }

    /// 기준을 재기까지 며칠이 쌓였나 — "재는 중 · 2일째" 에 쓴다.
    var baselineDaysCollected: Int {
        let past = save.dailyRaw.keys.filter { $0 != today }.sorted()
        guard let first = past.first, let last = past.last else { return 0 }
        return DayKey.days(from: first, to: last) + 1
    }

    /// 하루에 실제로 화분에 들어간 mL(보너스 전). **상수 환산이 아니라 기록에서 읽는다.**
    ///
    /// `dailyRaw / rawPerML` 로 계산하던 걸 대체한다. 상수는 한 사람의 한 달치라
    /// 작업 성격이 바뀌면 크게 어긋난다 — 캐시읽기 비중이 높은 사람은 실측 3,796 인데
    /// 상수가 6,957 이어서 **하루 유입이 절반으로 보였다.**
    var measuredDailyWater: Int? {
        let past = save.dailyWater.filter { $0.key != today }
        let keys = past.keys.sorted()
        guard let first = keys.first, let last = keys.last else { return nil }
        let span = DayKey.days(from: first, to: last) + 1
        guard span >= PlantBalance.dailyRawMinDays else { return nil }
        return max(1, past.values.reduce(0, +) / span)
    }

    /// 실측 환산비율(원시/mL). 못 재면 상수로 물러난다.
    var measuredRawPerML: Int {
        PlantBalance.measuredRawPerML(raw: save.dailyRaw, water: save.dailyWater)
            ?? PlantBalance.rawPerML
    }

    /// 장식을 옮긴다. 좌표는 **캔버스 픽셀** 기준이고, 화면 밖으로 못 나가게 잘라둔다.
    ///
    /// 세로는 지평선 아래로만 — 하늘에 벤치가 떠 있으면 꾸민 게 아니라 고장으로 보인다.
    func moveDecor(_ key: String, x: Int, y: Int, in layout: SceneLayout) {
        guard save.decorations.contains(key) else { return }
        let maxX = max(0, layout.width - DecorIcons.size)
        let minY = min(layout.height, layout.horizon + 3)
        save.decorPositions[key] = [min(max(0, x), maxX), min(max(minY, y), layout.height)]
        persist()
    }

    /// 자리를 기본값으로 되돌린다. 끌다가 겹쳐놓고 못 찾을 때 빠져나갈 길.
    func resetDecorPositions() {
        guard !save.decorPositions.isEmpty else { return }
        save.decorPositions = [:]
        persist()
    }

    /// 거름이 며칠 남았나. 0이면 안 돌고 있다.
    var fertilizerDaysLeft: Int { save.fertilizerDaysLeft(now: clock()) }

    /// 정원 그루 수 표기. 만렙(30그루)까지는 `N / 30`, 넘어가면 `N그루 · 최근 30 표시` 다.
    ///
    /// 넘어간 뒤에도 `N / 30` 으로 두면 `42 / 30` 이 찍혀서 버그로 읽힌다.
    /// 그리고 오래된 그루가 화면에서 사라지는 건 **화면 자리 문제**라고 적어줘야 한다 —
    /// 안 적으면 정원이 그루를 잡아먹는 것처럼 보인다.
    /// 화면에 **몇 그루가 그려지는지**는 티어의 자리 수다 — 만렙(30)이 아니다.
    /// `displayCount`(30) 와 견주고 있었더니, 자리가 1개인 베란다에서 2그루째부터
    /// 이미 한 그루가 안 보이는데 머리말은 "2 / 30 그루" 라고 했다.
    var gardenCountText: String {
        let n = save.gardenCount
        let drawn = SceneLayout.byKey(save.gardenTier.key).slotCount
        guard n > drawn else { return "\(n) / \(GardenTier.maxCount) 그루" }
        return "\(n)그루 · 여기엔 최근 \(drawn) 표시"
    }

    /// 설치 후 번 것 · 쓴 것 — 지갑이 왜 이 숫자인지 화면에서 풀어주는 데 쓴다.
    ///
    /// 둘 다 **직접 센 장부**다. 예전엔 `rawSinceInstall` 에서 빼서 만들었는데,
    /// 첫날 상한에 걸려 버린 분이 영원히 "쓴 것"으로 찍혀서 한 번도 안 산 사람에게도
    /// 지출이 보였다. 이제 지갑이 늘어난 자리와 줄어든 자리에서 각각 센다.
    var earnedTotal: Int { save.rawEarnedTotal }
    var spentTotal: Int { save.rawSpentTotal }

    /// 장부가 지갑과 맞는가. 화면이 이 뺄셈을 그대로 보여주므로 어긋나면 버그다.
    var ledgerBalances: Bool { save.rawEarnedTotal - save.rawSpentTotal == save.rawWallet }

    // MARK: 오늘 남은 횟수

    /// 오늘 물을 몇 번 더 줄 수 있나. 날이 바뀌면 저절로 되돌아간다.
    ///
    /// 화면에 **반드시** 보여야 한다. 상한에 걸렸는데 버튼만 회색이면
    /// 사용자는 "고장났나"로 읽는다 — 남은 횟수를 숫자로 보여주면 규칙이 그냥 이해된다.
    var waterUsesLeftToday: Int {
        let usedToday = save.waterUseDay == DayKey.make(clock()) ? save.waterUsesToday : 0
        return max(0, PlantBalance.dailyWaterUses - usedToday)
    }

    /// 이 그루에 영양제를 더 줄 수 있나. 이식하면 저절로 풀린다.
    func nutrientAvailable(_ slot: Int = 0) -> Bool {
        guard let p = pot(slot) else { return false }
        return p.nutrientUses < PlantBalance.nutrientUsesPerPlant
    }

    // MARK: 며칠치인가 — 상점의 모든 큰 숫자가 여기를 지난다

    /// 최근 14일 달력일 평균 유입(원시 토큰/일). 표본이 3일 미만이면 실측 기본값.
    var dailyRate: Int { PlantBalance.dailyRawRate(save.dailyRaw) }

    /// 다음 연속 사용 선물까지 남은 일수. 다 받았으면 nil.
    var daysToNextGift: Int? { PlantBalance.daysToNextGift(streak: save.streakDays) }

    /// 창고에 든 무료 뽑기권 수. 상점이 "값을 낼지 말지"를 여기서 판단한다.
    var freeDraws: Int { save.count(.decorBox) }

    /// 물 한 개가 실제로 넣는 기본 mL — **엔진과 같은 환산비율**을 쓴다.
    ///
    /// 화면이 상수로 환산한 숫자를 보여주고 엔진은 실측으로 부으면 둘이 어긋난다.
    /// 예전에 같은 실수를 한 적이 있다(창고 문구가 보너스를 먹인 뒤 값을 찍었다).
    /// 한 곳에서 계산해 UI 가 갖다 쓰게 둔다.
    var waterML: Int {
        let ratio = PlantBalance.measuredRawPerML(raw: save.dailyRaw, water: save.dailyWater)
            ?? PlantBalance.rawPerML
        return Water.mL(dailyRaw: dailyRate, rawPerML: ratio)
    }

    /// 측정된 값인가, 아직 기본값을 쓰는 중인가. 화면에서 "예상"과 "실측"을 구분해 쓴다 —
    /// 남의 평균으로 계산한 값을 자기 값인 척 보여주면 그게 제일 나쁘다.
    var dailyRateIsMeasured: Bool {
        let keys = save.dailyRaw.keys.sorted()
        guard let f = keys.first, let l = keys.last else { return false }
        return DayKey.days(from: f, to: l) + 1 >= PlantBalance.dailyRawMinDays
    }

    /// 이 사람의 하루 유입으로 환산한 값.
    func price(_ item: ShopItem) -> Int { PlantEngine.price(item, save) }

    /// 원시 토큰 → 며칠치.
    func days(forRaw raw: Int) -> Double {
        PlantBalance.days(forRaw: raw, rate: dailyRate)
    }

    /// 지금 지갑으로 살 수 있는 **가장 비싼** 품목. 없으면 nil.
    /// 지금 지갑으로 살 수 있는 **가장 비싼** 품목. 없으면 nil.
    ///
    /// `isCosmetic` 을 빼는 건 `nextGoal` 뿐이었는데, 그래서 장식을 다 모은 사람의 홈에
    /// "지금 장식 뽑기 살 수 있어요" 가 계속 떴다 — 같은 순간 상점의 그 줄은
    /// "다 모았어요" 로 버튼도 없었다. 두 화면이 정반대를 말했다.
    var affordableNow: ShopItem? {
        ShopItem.sortedByPrice.last { item in
            guard PlantEngine.canBuy(item, save) == .ok else { return false }
            if item == .decorBox { return !DecorIcons.gachaKeys.allSatisfy(save.decorations.contains) }
            return true
        }
    }

    /// 아직 못 사는 품목 중 **가장 싼** 것과 남은 양. 목표가 없으면 모을 이유도 없다.
    ///
    /// 장식은 건너뛴다. 값이 싸서(벤치 1일) 늘 제일 먼저 걸리는데, 성장에 아무 도움이 안 되는
    /// 걸 목표로 걸어주면 "저걸 모아봐야 뭐하나"가 된다. 정원 꾸미기는 상점에서 직접 고르는 거지
    /// 홈이 권할 일이 아니다.
    var nextGoal: (item: ShopItem, short: Int)? {
        for item in ShopItem.sortedByPrice where !item.isCosmetic {
            if case .insufficientBalance(let short) = PlantEngine.canBuy(item, save) {
                return (item, short)
            }
        }
        return nil
    }

    /// "1.3일치" / "12시간치" — 하루 미만은 시간으로 쓴다. 0.1일은 아무 느낌도 없다.
    func dayText(_ raw: Int) -> String {
        let d = days(forRaw: raw)
        if d < 1 {
            let hours = Int((d * 24).rounded())
            return hours <= 0 ? "곧" : "\(hours)시간치"
        }
        if d < 10 { return String(format: "%.1f일치", d) }
        return "\(Int(d.rounded()))일치"
    }

    /// 이식까지 남은 물과 예상 일수 — **아무것도 안 사고 그냥 뒀을 때**.
    ///
    /// 아이템을 쓰면 이보다 빨라진다(상한까지 부으면 1.4배). 낙관적인 쪽을 기본으로 보여주면
    /// 안 산 사람은 매번 약속이 밀리는 걸 보게 되므로, 바닥값을 쓴다.
    func daysToTransplant(_ slot: Int) -> Int? {
        guard let p = pot(slot) else { return nil }
        let remaining = max(0, p.cycleWater - p.water)
        guard remaining > 0 else { return 0 }
        // 두 군데가 틀려 있었다.
        //
        //  1. 분모를 `dailyRate / rawPerML` 상수 환산으로 구했다. 목표(`seedCycle`)는
        //     실측 비율로 만드는데 여기만 상수를 써서, 캐시읽기가 많은 사람은
        //     **"이식까지 약 51일"** 이라고 떴다(실제 16일). 제일 동기가 되는 숫자가 3배 거짓말.
        //  2. 보너스를 아예 안 셌다. 물·스트릭·거름이 다 붙으면 실제로 2배 빠르다.
        let measured = measuredDailyWater ?? max(1, dailyRate / PlantBalance.rawPerML)
        let perDay = PlantBalance.applied(water: measured,
                                          streakDays: save.streakDays,
                                          fertilizerActive: save.fertilizerActive(now: clock()))
        return Int((Double(remaining) / Double(max(1, perDay))).rounded(.up))
    }

    var daysToTransplant: Int? { daysToTransplant(0) }

    var statusLine: String {
        switch displayState {
        case .seed:     return "막 심었어요. 토큰을 쓰면 저절로 자랍니다."
        case .idle:     return "잘 자라고 있어요."
        case .hasItems: return "창고에 쓸 게 있어요. 주면 더 빨리 자랍니다."
        case .thirsty:  return "목말라요. 토큰을 쓴 지 며칠 됐어요."
        case .parched:  return "바싹 말랐어요. 한 번 자라면 색이 돌아옵니다."
        case .levelUp:  return "자랐어요!"
        }
    }

    // MARK: 프리뷰 전용 — 가짜 물

    /// 지갑만 채운다 — 상점을 실제 토큰 없이 눌러보기 위한 주입구.
    /// 포크에서는 쓰지 않는다(UsageStore 가 `update` 로 넣는다).
    func creditWalletForPreview(_ raw: Int) {
        save.rawWallet += raw
        save.rawEarnedTotal += raw
        persist()
    }

    /// 화분만 키운다 — 성장 연출·단계 교차를 실제 토큰 없이 확인할 때.
    func injectWaterForPreview(_ mL: Int) {
        PlantEngine.applyWater(&save, mL: mL, today: today, now: clock())
        persist()
        pickCelebration()
    }

    func resetForPreview() {
        save = PlantSave()
        PlantEngine.plantNewSeed(&save, roll: UInt64.random(in: 0..<1_000_000), now: clock())
        _ = PlantEngine.drainEvents(&save)
        celebration = nil
        todayWater = 0
        todayRaw = 0
        lastWindowBonus = 0
        lastWindowBonusDay = ""
        lastWaterGained = 0
        limits = LimitsSnapshot()
        persist()
    }
}
