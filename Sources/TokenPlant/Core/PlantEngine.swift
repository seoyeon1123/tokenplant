import Foundation

/// 날짜 키 — `yyyy-MM-dd`(로컬). PokeTokenBar 의 `LocalUsageReader.todayKey()` 와 같은 형식.
enum DayKey {
    static func make(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 두 날짜 키 사이의 일수. 파싱 실패 시 0.
    static func days(from a: String, to b: String, calendar: Calendar = .current) -> Int {
        guard let da = parse(a, calendar), let db = parse(b, calendar) else { return 0 }
        return calendar.dateComponents([.day], from: da, to: db).day ?? 0
    }

    static func parse(_ key: String, _ calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        return calendar.date(from: c)
    }
}

/// 화분·정원에서 일어난 일. 팝오버가 닫혀 있는 동안 쌓이고, 다음에 열 때 **한 번만** 재생된다.
/// 3일 만에 열었다고 연출을 세 번 돌리면 안 된다.
enum PlantEvent: Codable, Sendable, Equatable {
    case levelUp(stageIndex: Int)
    case fruitHarvest
    case readyToTransplant
    case transplanted(speciesID: String, isShiny: Bool)
    case thirsty
    case newSeed(speciesID: String, rarity: PlantRarity, isShiny: Bool)
    /// 장식 뽑기에서 새 장식이 나왔다. **뭐가 나왔는지**를 실어야 한다 —
    /// "장식을 받았어요"만 띄우면 정원을 열어봐야 확인이 된다.
    case decorFound(key: String)
    /// 한도 창을 다 태워 지갑에 보너스가 들어왔다. 창 이름을 실어 "왜 받았는지"를 보여준다 —
    /// 이유 없이 지갑이 늘면 사용자는 버그로 읽는다.
    case windowBurned(name: String, raw: Int)

    /// 같은 종류가 여러 번 쌓이면 마지막(가장 진행된) 것만 남긴다.
    var coalesceKey: String {
        switch self {
        case .levelUp: return "levelUp"
        case .fruitHarvest: return "fruit"
        case .readyToTransplant: return "ready"
        case .transplanted: return "transplant"
        case .thirsty: return "thirsty"
        case .newSeed: return "newSeed"
        case .decorFound: return "decor"
        case .windowBurned: return "window"
        }
    }
}

/// 영속 상태(Application Support JSON).
struct PlantSave: Codable, Sendable {
    // 토큰 — 설치 이후만 측정. 원시는 표시용, 물은 성장용.
    var installBaselineSet = false
    /// 로그가 "설치 후 이만큼 썼다"고 말한 양. **지갑에 들어온 양과 다르다** —
    /// 첫날 상한에 걸려 버린 분이 여기엔 포함된다.
    var rawSinceInstall = 0
    var waterSinceInstall = 0

    // MARK: 지갑 장부 — **둘 다 직접 센다**
    //
    // 예전엔 화면의 "번 것 − 쓴 것 = 지갑"에서 번 것을 `rawSinceInstall` 로,
    // 쓴 것을 `rawSinceInstall − rawWallet` 으로 **빼서** 만들었다. 그게 거짓말이 됐다:
    // 첫날 상한에 걸려 버린 분은 `rawSinceInstall` 에는 들어가고 지갑에는 안 들어가는데,
    // 그 차액이 영원히 "쓴 것"으로 찍힌다. 한 번도 안 산 사람에게도 지출이 보인다.
    //
    // 그래서 지갑이 **늘어난 곳과 줄어든 곳에서** 각각 센다. 그러면 뺄셈이
    // 파생값이 아니라 실제 장부가 되고, 셋이 어긋나면 그건 버그다(테스트가 본다).

    /// 지갑에 실제로 들어온 누적. `rawWallet` 이 늘어나는 모든 자리에서 같이 올린다.
    var rawEarnedTotal = 0
    /// 상점에서 실제로 쓴 누적. `buy` 에서만 올린다.
    var rawSpentTotal = 0

    // 프로바이더별 오늘 기준값. nil = 구버전 세이브가 아직 seed 안 됨 → 첫 갱신은 기준만 잡고
    // 과거 사용량을 소급 지급하지 않는다. 빈 map(이미 seed됨 + 오늘 보고 없음)과 구분해야 한다.
    var claimedTodayByProvider: [String: TokenDelta]? = nil
    var lastDate = ""

    // 화분
    var pot: PotState?
    /// 화분 슬롯을 산 경우의 두 번째 그루. 물은 나눠지지 않고 각각 따로 차오른다.
    var pot2: PotState?
    /// 다음 씨앗에 적용될 등급 보증(고급/전설 씨앗을 산 경우). 부화 때 소비된다.
    /// 영속이어야 한다 — 구매와 부화 사이에 재시작이 끼어도 산 것을 받아야 한다.
    var pendingSeedGuarantee: PlantRarity?

    // 정원
    var garden: [GardenEntry] = []

    /// 지갑 — **원시 토큰**. 메뉴바에 뜨는 숫자와 같은 값이다.
    /// 성장(가중 환산 mL)과는 별개의 물길이라, 여기서 써도 이미 자란 건 줄지 않는다.
    var rawWallet = 0
    var inventory: [String: Int] = [:]     // ShopItem.rawValue → 개수
    var passives: [String] = []            // 보유형 ShopItem.rawValue
    var decorations: [String] = []          // 정원에 놓인 장식 ShopItem.rawValue

    /// 장식마다 사용자가 옮겨둔 자리. `키 → [x, 바닥y]`(캔버스 픽셀 좌표).
    ///
    /// 없으면 기본 자리(`SceneLayout.decorSpots`)에 순서대로 놓인다. 딕셔너리로 둔 이유:
    /// 티어가 바뀌면 캔버스 크기가 달라지는데, 배열 인덱스로 두면 어느 장식의 자리인지
    /// 알 수 없어서 전부 어긋난다. 키로 두면 캔버스가 커져도 그 장식이 그 자리에 남는다.
    var decorPositions: [String: [Int]] = [:]

    /// 날짜키 → 그날 쓴 **원시 토큰**. 최근 `dailyRawWindow` 일만 남긴다.
    /// 가격이 "하루치의 몇 배"로 정의돼 있어 이 값이 상점 환산의 분모다 —
    /// 상수로 박으면 남의 속도로 환산된다(사람마다 10배씩 다르다).
    var dailyRaw: [String: Int] = [:]

    // 관리 상태
    var lastWaterDay = ""                  // 화분에 **부은** 마지막 날 (목마름 계산 기준)
    /// 물을 준 횟수를 센 날. 날이 바뀌면 `waterUsesToday` 를 0으로 되돌린다.
    var waterUseDay = ""
    var waterUsesToday = 0
    /// 날짜별 가중 환산 물(mL). `dailyRaw` 와 짝이라 나누면 **실측 환산비율**이 나온다.
    var dailyWater: [String: Int] = [:]
    /// 과거 로그를 한 번 거슬러 읽었나. 매 실행마다 몇 달치를 훑으면 켤 때마다 느려진다.
    var historyBackfilled = false
    var lastUseDay = ""                    // 토큰을 쓴 마지막 날 (스트릭 기준)
    var streakDays = 0
    var fertilizerExpiresAt: Date?

    // 연출 대기열
    var pendingEvents: [PlantEvent] = []

    // 성장 배율(50/100/200%)은 제거했다. 공짜로 2배가 되는 손잡이라 "안 고를 이유"가 없었고,
    // 주기가 실측 사용량에 맞춰 자동으로 정해지면서 원래의 보정 역할도 사라졌다.
    // 구버전 세이브의 `growthScalePercent` 키는 디코딩에서 그냥 무시된다.

    // 한도 창 보상
    /// 창 키 → 지급 여부(1 = 이미 줬음). 100% 아래로 내려가면 키를 지워 재무장한다.
    /// `resets_at` 처럼 매 조회마다 바뀌는 값은 키에 들어가면 안 된다 — 매번 새 창이 된다.
    var windowGrantTier: [String: Int] = [:]
    /// 첫 실행에 이미 100% 인 창을 지급 없이 시드했는가. 안 하면 설치 직후 소급 지급된다.
    var windowsSeeded = false

    init() {}

    /// 관대 디코딩 — 한 필드 손상이 정원·인벤토리 전체를 날리지 않게.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func g<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decode(T.self, forKey: k)) ?? def }
        installBaselineSet = g(.installBaselineSet, false)
        rawSinceInstall = max(0, g(.rawSinceInstall, 0))
        waterSinceInstall = max(0, g(.waterSinceInstall, 0))
        claimedTodayByProvider = try? c.decode([String: TokenDelta].self, forKey: .claimedTodayByProvider)
        lastDate = g(.lastDate, "")
        pot = try? c.decode(PotState.self, forKey: .pot)
        pot2 = try? c.decode(PotState.self, forKey: .pot2)
        pendingSeedGuarantee = try? c.decode(PlantRarity.self, forKey: .pendingSeedGuarantee)
        garden = g(.garden, [GardenEntry]())
        dailyRaw = g(.dailyRaw, [String: Int]())
        rawWallet = max(0, g(.rawWallet, 0))
        rawEarnedTotal = max(0, g(.rawEarnedTotal, 0))
        rawSpentTotal = max(0, g(.rawSpentTotal, 0))
        // 구버전 세이브에는 장부가 없다. 예전 파생식으로 한 번 채워준다 —
        // 0 으로 두면 이미 쓰고 있던 사람의 화면에서 이 줄이 통째로 사라진다.
        // 첫날 상한만큼 어긋난 값이지만, 다음 적립부터는 정확해진다.
        if rawEarnedTotal == 0 && (rawWallet > 0 || rawSinceInstall > 0) {
            rawEarnedTotal = max(rawWallet, rawSinceInstall)
            rawSpentTotal = max(0, rawEarnedTotal - rawWallet)
        }
        inventory = g(.inventory, [String: Int]())
        passives = g(.passives, [String]())
        decorations = g(.decorations, [String]())
        decorPositions = g(.decorPositions, [String: [Int]]())
        lastWaterDay = g(.lastWaterDay, "")
        waterUseDay = g(.waterUseDay, "")
        waterUsesToday = max(0, g(.waterUsesToday, 0))
        dailyWater = g(.dailyWater, [String: Int]())
        historyBackfilled = g(.historyBackfilled, false)
        lastUseDay = g(.lastUseDay, "")
        streakDays = max(0, g(.streakDays, 0))
        fertilizerExpiresAt = try? c.decode(Date.self, forKey: .fertilizerExpiresAt)
        pendingEvents = g(.pendingEvents, [PlantEvent]())
        windowGrantTier = g(.windowGrantTier, [String: Int]())
        windowsSeeded = g(.windowsSeeded, false)
    }

    // MARK: 파생값

    var gardenCount: Int { garden.count }
    var gardenTier: GardenTier { GardenTier.tier(forCount: gardenCount) }
    var hasShinyCharm: Bool { passives.contains(ShopItem.shinyCharm.rawValue) }
    var hasPotSlot: Bool { passives.contains(ShopItem.potSlot.rawValue) }

    func count(_ item: ShopItem) -> Int { inventory[item.rawValue] ?? 0 }

    func fertilizerActive(now: Date) -> Bool {
        guard let e = fertilizerExpiresAt else { return false }
        return e > now
    }

    func fertilizerDaysLeft(now: Date) -> Int {
        guard let e = fertilizerExpiresAt, e > now else { return 0 }
        return max(1, Calendar.current.dateComponents([.day], from: now, to: e).day ?? 1)
    }

    /// 도감 — 획득한 (종, 반짝) 조합.
    var dexKeys: Set<String> {
        Set(garden.map { "\($0.speciesID):\($0.isShiny ? "s" : "n")" })
    }
}

/// 순수 로직. 상태를 받아 상태를 돌려준다 — @MainActor 스토어는 이걸 호출만 한다.
/// 부수효과(파일 저장·알림·연출)와 분리해 테스트 가능하게 유지한다.
enum PlantEngine {

    // MARK: 물 적립

    /// 프로바이더별 오늘 누적값 스냅샷을 받아 증분만 물로 적립한다.
    ///
    /// `todayByProvider` 는 **오늘 누적**이다(증분이 아니다). 기준값과의 차이만 적립하므로
    /// 같은 값이 여러 번 들어와도 두 번 세지 않는다.
    static func ingest(_ save: inout PlantSave,
                       todayByProvider: [String: TokenDelta],
                       today: String,
                       now: Date = Date()) {
        // 순서가 중요하다. 날짜 갱신을 먼저 하면 `claimedTodayByProvider` 가 [:] 로 채워져
        // 첫 설치 분기가 영영 안 타고 상한이 적용되지 않는다. 그래서 seed 를 먼저 본다.
        guard var baseline = save.claimedTodayByProvider else {
            // 첫 설치 — 오늘치는 인정하고 `firstDayCreditCap` 으로 막는다.
            save.claimedTodayByProvider = todayByProvider
            save.lastDate = today
            save.installBaselineSet = true

            let snapshot = todayByProvider.values.reduce(TokenDelta()) { $0 + $1 }.clampedToZero
            save.rawSinceInstall += snapshot.raw
            // 첫날은 상한까지만 인정하고 넘치는 분은 버린다 —
            // 그대로 넣으면 설치 전 로그가 소급돼 첫 화면부터 거목에 지갑이 가득이다.
            // 상한은 이 그루의 목표에 비례한다 — 고정값이면 적게 쓰는 사람의 첫날이
            // 사이클을 통째로 채워버린다.
            let cycle = save.pot?.cycleWater
                ?? PlantBalance.cycleWater(dailyRaw: PlantBalance.assumedDailyRaw)
            let mL = min(PlantBalance.firstDayCredit(cycle: cycle),
                         PlantBalance.water(from: snapshot))
            let raw = min(PlantBalance.firstDayRawCap(dailyRaw: PlantBalance.assumedDailyRaw),
                          snapshot.raw)
            credit(&save, raw: raw, water: mL, today: today, now: now)
            return
        }

        // 날이 바뀌면 기준값을 비운다 — 오늘 누적이 0에서 다시 시작하기 때문이다.
        // 잔액은 건드리지 않는다. 안 부은 물이 자정에 사라지면 며칠 모아 큰 걸 사는 게 불가능해진다.
        if save.lastDate != today {
            save.lastDate = today
            baseline = [:]
        }

        var total = TokenDelta()
        var next = baseline
        for (id, snapshot) in todayByProvider {
            let prev = baseline[id] ?? TokenDelta()
            let delta = (snapshot - prev).clampedToZero
            if !delta.isZero { total = total + delta }
            // 스냅샷이 기준보다 작아도(로그 정리) 기준을 내려 다음 증분이 정상화되게 한다.
            next[id] = snapshot
        }
        save.claimedTodayByProvider = next

        save.rawSinceInstall += total.raw
        credit(&save, raw: total.raw, water: PlantBalance.water(from: total),
               today: today, now: now)
    }

    /// 토큰에서 나온 물을 **잔액**에 넣는다. 화분에는 아직 안 들어간다.
    ///
    /// 여기가 예전 설계와 갈리는 지점이다. 자동으로 부으면 앱을 열 이유가 구경뿐이고,
    /// 자동 성장과 구매가 같이 있으면 토큰이 이중 사용된다. 부는 것 자체가 지출이면 둘 다 없다.
    /// 쓴 토큰을 **두 곳에 동시에** 넣는다. 이 갈래가 이 앱의 전부다.
    ///
    /// ```
    ///                ┌─▶ 가중 환산 mL ──▶ 화분이 자동으로 자란다
    /// 쓴 토큰 ───────┤
    ///                └─▶ 원시 토큰 ────▶ 지갑. 물·거름·영양제를 산다
    /// ```
    ///
    /// 둘은 서로 뺏지 않는다. 상점에서 써도 이미 자란 건 그대로다.
    /// PokeTokenBar 는 `쓸 수 있는 재화 = 쓴 토큰 − 쓴 재화` 라 성장 게이지와 지갑이 같은 값이었고,
    /// 그래서 사탕을 값어치의 5배로 팔아야만 무한 자가성장이 막혔다.
    /// 여기선 강 하나에서 물길이 둘로 갈리는 것뿐이라 그 문제가 없고,
    /// 가속 폭도 결국 실제로 쓴 토큰에 묶여 있어서 루프가 닫히지 않는다.
    static func credit(_ save: inout PlantSave, raw: Int, water mL: Int,
                       today: String, now: Date = Date()) {
        guard raw > 0 || mL > 0 else { return }
        bumpStreak(&save, today: today)

        // 1. 지갑 — 원시 토큰 그대로. 메뉴바에 뜨는 숫자와 같은 값이라 헷갈릴 게 없다.
        save.rawWallet += raw
        save.rawEarnedTotal += raw
        // 하루 유입 기록. 가격이 "하루치의 몇 배"로 정의돼 있어 이 값이 환산의 분모다.
        save.dailyRaw[today, default: 0] += raw
        save.dailyRaw = PlantBalance.prunedDailyRaw(save.dailyRaw, today: today)
        // 물도 날짜별로 같이 쌓는다 — 원시와 짝지어 나누면 환산비율을 각자 잴 수 있다.
        if mL > 0 {
            save.dailyWater[today, default: 0] += mL
            save.dailyWater = PlantBalance.prunedDailyRaw(save.dailyWater, today: today)
        }

        // 2. 성장 — 가중 환산 mL. 쓰면 자란다, 아무것도 안 눌러도.
        applyWater(&save, mL: mL, today: today, now: now)

        // mL 이 0으로 내림될 수 있다 — 가중합을 100,000 으로 나누므로 캐시읽기 9,000토큰은 0mL 다.
        // 그러면 `applyWater` 가 바로 빠져나가 `lastWaterDay` 가 안 찍히고,
        // **매일 쓰는 사람이 7일 뒤에 "바싹 말랐어요"** 가 됐다.
        // 목마름이 재는 건 "돌봤나"이고, 여기까지 왔다는 건 토큰을 썼다는 뜻이다.
        if raw > 0 && save.lastWaterDay != today { save.lastWaterDay = today }
    }

    /// 물을 **모든 화분에** 먹인다. 자동 성장(토큰)과 아이템(물·영양제)이 같이 쓰는 길이다.
    ///
    /// 보너스(스트릭 · 거름)는 여기서 한 번만 곱한다 —
    /// 유입 경로마다 규칙이 갈리면 나중에 아무도 못 맞춘다.
    /// 화분이 둘이면 둘 다 같은 양을 받는다: 물은 나뉘지 않고 각각 차오른다.
    @discardableResult
    static func applyWater(_ save: inout PlantSave, mL: Int,
                           today: String, now: Date = Date()) -> Int {
        guard mL > 0 else { return 0 }
        let applied = PlantBalance.applied(water: mL,
                                           streakDays: save.streakDays,
                                           fertilizerActive: save.fertilizerActive(now: now))
        save.waterSinceInstall += applied
        save.lastWaterDay = today
        grow(&save, pot: \.pot, by: applied)
        if save.pot2 != nil { grow(&save, pot: \.pot2, by: applied) }
        return applied
    }

    /// 한 그루에 물을 주고 단계 상승을 판정한다.
    static func grow(_ save: inout PlantSave, pot key: WritableKeyPath<PlantSave, PotState?>, by mL: Int) {
        guard save[keyPath: key] != nil else { return }
        let wasReady = save[keyPath: key]!.isReadyToTransplant
        save[keyPath: key]!.water += mL

        var guardCount = 0
        while guardCount < PlantBalance.stageCount + 2 {
            guardCount += 1
            guard var p = save[keyPath: key] else { return }
            let target = PlantBalance.stageIndex(forWater: p.water, cycle: p.cycleWater)
            guard target > p.stageIndex else { break }
            p.stageIndex += 1
            save[keyPath: key] = p
            push(&save, .levelUp(stageIndex: p.stageIndex))

            if p.stageIndex == 8, !p.fruitHarvested {
                save[keyPath: key]!.fruitHarvested = true
                push(&save, .fruitHarvest)
            }
        }

        // 전이에서만 알린다 — 매 적립마다 밀어 넣으면 이식할 때까지 대기열에 붙어 있다.
        if let p = save[keyPath: key], p.isReadyToTransplant, !wasReady {
            push(&save, .readyToTransplant)
        }
    }

    /// 스트릭은 **토큰을 쓴 날**을 센다. 앱을 연 날이 아니다 —
    /// 열어보지 않아도 자라는 게 이 앱의 약속이라, 출석을 세면 그 약속이 깨진다.
    private static func bumpStreak(_ save: inout PlantSave, today: String) {
        guard save.lastUseDay != today else { return }
        if save.lastUseDay.isEmpty {
            save.streakDays = 1
        } else if DayKey.days(from: save.lastUseDay, to: today) == 1 {
            save.streakDays += 1
        } else {
            save.streakDays = 1
        }
        save.lastUseDay = today
    }

    // MARK: 목마름 — 외형만

    /// 마지막으로 물이 들어간 뒤 며칠 지났는지로 **색만** 마르게 한다. 누적 물은 안 깎는다.
    ///
    /// 토큰을 안 쓰면 안 자라는 것 자체가 이미 결과다. 거기에 진행도까지 뺏으면
    /// 실제로 쓴 토큰을 두 번 벌주는 셈이라 감쇠(낙엽)를 통째로 뺐다.
    /// 한 번만 자라면 색은 바로 돌아온다.
    static func thirstLevel(_ save: PlantSave, today: String) -> Double {
        guard !save.lastWaterDay.isEmpty else { return 0 }
        let idle = DayKey.days(from: save.lastWaterDay, to: today)
        if idle < PlantBalance.thirstyAfterIdleDays { return 0 }
        if idle >= PlantBalance.parchedAfterIdleDays { return 1 }
        let span = Double(PlantBalance.parchedAfterIdleDays - PlantBalance.thirstyAfterIdleDays)
        return min(1, Double(idle - PlantBalance.thirstyAfterIdleDays) / max(1, span))
    }

    /// 목이 마르기 시작하면 한 번 알린다 — 연출 대기열에 쌓아 다음에 열 때 보여준다.
    static func noteThirst(_ save: inout PlantSave, today: String) {
        guard thirstLevel(save, today: today) > 0 else { return }
        push(&save, .thirsty)
    }

    // MARK: 한도 창 소진 보상

    /// 지급 한 건. 단위는 **원시 토큰**(지갑으로 들어간다).
    struct WindowGrant: Sendable, Equatable {
        let windowKey: String
        let windowName: String
        let raw: Int
    }

    /// 순수 판정 — **엣지 트리거**다. 100% 를 새로 넘어선 순간에만 지급한다.
    ///
    /// 왜 엣지인가: 창이 100% 인 동안 30초마다 갱신되므로, 상태만 보고 주면 한 창에서
    /// 하루에 수백 번 지급된다. 그래서 지급하면 tier=1 을 찍고, 100% 아래로 내려가면
    /// (창이 리셋됨) 키를 지워 다시 무장한다.
    ///
    /// 부수효과(인벤토리·연출)와 분리해 테스트 가능하게 둔다.
    static func evaluateWindowGrants(windows: [LimitWindowInfo],
                                     grantTier: inout [String: Int]) -> [WindowGrant] {
        var grants: [WindowGrant] = []
        for w in windows {
            guard w.utilization >= 100 else {
                grantTier[w.key] = nil       // 재무장
                continue
            }
            guard (grantTier[w.key] ?? 0) < 1 else { continue }
            grantTier[w.key] = 1
            grants.append(WindowGrant(windowKey: w.key, windowName: w.name,
                                      raw: w.kind.bonusRaw))
        }
        return grants
    }

    /// 한도 창 상태를 받아 물통에 보너스를 넣는다. 넣은 총량을 돌려준다.
    ///
    /// `isReady` 가 false 면(한도를 아직 못 읽음) 시드도 지급도 하지 않는다 —
    /// 반쪽 상태로 시드하면 나중에 로드된 창이 이미 100% 인 채로 소급 지급된다.
    @discardableResult
    static func grantWindowBonus(_ save: inout PlantSave,
                                    windows: [LimitWindowInfo],
                                    isReady: Bool) -> Int {
        guard isReady else { return 0 }

        // 첫 실행: 이미 100% 인 창은 **지급 없이** tier 만 찍는다.
        // 안 그러면 설치하자마자 이번 주 내내 태운 창값을 한꺼번에 받는다.
        if !save.windowsSeeded {
            for w in windows where w.utilization >= 100 { save.windowGrantTier[w.key] = 1 }
            save.windowsSeeded = true
            return 0
        }

        let grants = evaluateWindowGrants(windows: windows, grantTier: &save.windowGrantTier)
        var total = 0
        for g in grants {
            // 창을 태운 보상은 **지갑**으로 간다. 만료되는 한도를 남는 것으로 바꾸는 게 목적이라,
            // 성장에 직접 꽂으면 "안 쓰면 사라지는 걸 썼다"는 실감이 안 난다.
            save.rawWallet += g.raw
            // 장부에도 같이 얹는다 — 지갑이 늘어난 자리면 번 것도 늘어야 한다.
            // 하루 유입 통계(`dailyRaw`)와 스트릭에는 **여전히 안 섞는다** — 그건 쓴 양이 아니다.
            save.rawEarnedTotal += g.raw
            save.rawSinceInstall += g.raw
            total += g.raw
            push(&save, .windowBurned(name: g.windowName, raw: g.raw))
        }
        return total
    }

    // MARK: 상점 — 지갑은 원시 토큰

    static func canBuy(_ item: ShopItem, _ save: PlantSave) -> PurchaseResult {
        if item.isPassive, save.passives.contains(item.rawValue) { return .alreadyOwned }
        let short = price(item, save) - save.rawWallet
        return short > 0 ? .insufficientBalance(short: short) : .ok
    }

    /// 이 세이브에서의 실제 값. 가격은 **하루치의 몇 배**로 정의돼 있어
    /// 각자 측정된 하루 유입으로 환산된다 — 사람마다 10배씩 다르기 때문이다.
    static func price(_ item: ShopItem, _ save: PlantSave) -> Int {
        item.price(dailyRaw: PlantBalance.dailyRawRate(save.dailyRaw))
    }

    @discardableResult
    static func buy(_ item: ShopItem, _ save: inout PlantSave) -> PurchaseResult {
        let check = canBuy(item, save)
        guard check == .ok else { return check }
        // 값을 먼저 지역 변수로 뺀다 — `save.rawWallet -= price(item, save)` 는
        // 같은 저장소에 쓰기와 읽기가 겹쳐 Swift 가 배타 접근 위반으로 거절한다.
        let cost = price(item, save)
        save.rawWallet -= cost
        save.rawSpentTotal += cost
        if item.isPassive {
            save.passives.append(item.rawValue)
            // 장식은 가방에 담을 이유가 없다 — 살 때 정원에 바로 놓인다.
            if item.isDecoration { save.decorations.append(item.rawValue) }
            // 화분 슬롯은 사는 즉시 두 번째 화분이 생긴다 — 씨앗은 다음 이식 때 심긴다.
            if item == .potSlot, save.pot2 == nil, let first = save.pot {
                // 목표를 안 넘기면 `PotState.init` 기본값인 `legacyCycleWater`(400,000) 가 박힌다.
                // 하루 5M 쓰는 사람에게는 첫 화분이 28일인데 둘째 화분만 557일이 되어,
                // 같은 화면에 20,118mL 와 400,000mL 가 나란히 뜬다.
                save.pot2 = PotState(speciesID: first.speciesID, water: 0, stageIndex: 0,
                                     isShiny: false, plantedAt: Date(),
                                     cycleWater: seedCycle(save))
            }
        } else {
            // 사면 가방으로 들어간다. 즉시 발동이 아니다 —
            // 영양제는 언제 쓰느냐가 값어치를 좌우해서, 살 때 터지면 고를 기회가 사라진다.
            save.inventory[item.rawValue] = save.count(item) + 1
        }
        return .ok
    }

    // MARK: 사용 — 세 가지가 **모양이 다르다**
    //
    // 값만 다르고 하는 일이 같으면 제일 싼 것만 사게 된다. 그래서 셋을 다른 축에 뒀다:
    //
    //   물     정액 · 즉시   — 지금 한 칸 더. 언제 써도 같은 값
    //   거름   배율 · 지속   — 앞으로 7일 들어올 물이 늘어난다. 꾸준할 때만 값을 한다
    //   영양제 비례 · 즉시   — 남은 거리의 10%. 갓 심었을 때 크고 거목 앞에선 작다
    //
    // 셋의 값어치는 비슷하고(±20%), 갈리는 건 **언제 쓰느냐**다. 그게 고민이 되는 지점이다.

    @discardableResult
    /// `roll` 은 장식 뽑기만 쓴다. 기본값을 두면 호출부가 안 바뀌고,
    /// 테스트는 값을 넘겨 어떤 장식이 나올지 고정할 수 있다.
    static func use(_ item: ShopItem, _ save: inout PlantSave, today: String, now: Date = Date(),
                    roll: UInt64 = UInt64.random(in: 0...UInt64.max)) -> UseResult {
        guard save.count(item) > 0 else { return .notOwned }
        guard let pot = save.pot else { return .notOwned }

        switch item {
        case .water:
            // 하루 상한. **소모 전에** 막아야 한다 — 먼저 consume 하면 상한에 걸렸을 때
            // 산 물이 그냥 사라진다.
            if save.waterUseDay != today {
                save.waterUseDay = today
                save.waterUsesToday = 0
            }
            guard save.waterUsesToday < PlantBalance.dailyWaterUses else {
                return .noEffect(reason: "오늘 물은 다 줬어요 — 내일 또 줄 수 있어요")
            }
            save.waterUsesToday += 1

            // 정액. 자동 성장과 같은 길로 들어가 보너스도 똑같이 받는다 —
            // 유입 경로마다 규칙이 갈리면 나중에 아무도 못 맞춘다.
            // 양도 **그 사람 하루치의 1/5** 이라 1:1 등가 교환이고, 총량은 하루 상한이 막는다.
            consume(item, &save)
            let mL = Water.mL(dailyRaw: PlantBalance.dailyRawRate(save.dailyRaw))
            let gained = applyWater(&save, mL: mL, today: today, now: now)
            return .ok(waterGained: gained)

        case .fertilizer:
            // **남은 기간에 이어 붙인다.** 배수는 중첩되지 않는다(+50% 가 되지 않는다) —
            // 늘어나는 건 기간뿐이라 두 개를 쓰면 두 개 값어치가 그대로 나온다.
            //
            // 예전엔 "7일이 다시 시작"이라 돌고 있는 동안 쓰면 남은 날이 날아갔고,
            // 그래서 화면이 아예 버튼을 막았다. 그 결과 **사도 바로 못 쓰는 품목**이 됐다 —
            // 산 물건을 못 쓰게 막는 건, 못 쓰게 된 이유가 뭐든 사용자 입장에선 고장이다.
            //
            // 이어 붙이기는 밸런스를 안 건드린다: 배수는 그대로 +25% 고,
            // 총 회수량은 쓴 개수에 비례한다(선형). 천장만 3주로 둔다.
            let cal = Calendar.current
            let base = max(now, save.fertilizerExpiresAt ?? now)
            let extended = cal.date(byAdding: .day, value: PlantBalance.fertilizerDays, to: base) ?? base
            let ceiling = cal.date(byAdding: .day, value: PlantBalance.fertilizerMaxDays, to: now) ?? extended
            // 천장에 이미 닿아 있으면 쓸 자리가 없다 — 소모 전에 막아야 아이템이 안 사라진다.
            guard base < ceiling else {
                return .noEffect(reason: "거름이 \(PlantBalance.fertilizerMaxDays)일치까지 차 있어요")
            }
            consume(item, &save)
            save.fertilizerExpiresAt = min(extended, ceiling)
            return .ok(waterGained: 0)

        case .nutrient:
            // 한 그루에 한 번. 그루에 기록하므로 이식하면 저절로 풀린다 —
            // 날짜로 세면 "하루 지나면 또" 가 되어 한 그루에 열 개도 들어간다.
            guard pot.nutrientUses < PlantBalance.nutrientUsesPerPlant else {
                return .noEffect(reason: "이 그루엔 이미 줬어요 — 다음 그루에 쓸 수 있어요")
            }
            // 비례. 남은 거리를 당긴다 — 초반엔 크고 후반엔 작아진다.
            let gain = Nutrient.water(currentWater: pot.water, cycle: pot.cycleWater)
            guard gain > 0 else { return .noEffect(reason: "이미 다 자랐어요") }
            consume(item, &save)
            save.pot?.nutrientUses += 1

            // **이 그루에만** 넣는다. `applyWater` 를 타면 화분 2에도 같은 양이 공짜로 들어가서
            // "한 그루에 한 번" 이 거짓이 됐고(화분 2는 자기 횟수를 영원히 안 쓴다),
            // 게다가 양이 **화분 1의** 남은 거리로 계산돼서 엉뚱한 그루 기준으로 매겨졌다.
            //
            // 물·거름과 다른 이유: 저 둘은 저장 전체에 걸리는 품목이고, 영양제는
            // 그루에 기록되는 품목이다. 기록이 그루에 있으면 효과도 그루에만 가야 한다.
            let applied = PlantBalance.applied(water: gain,
                                               streakDays: save.streakDays,
                                               fertilizerActive: save.fertilizerActive(now: now))
            save.waterSinceInstall += applied
            save.lastWaterDay = today
            grow(&save, pot: \.pot, by: applied)
            return .ok(waterGained: applied)

        case .premiumSeed, .legendarySeed:
            // 예약 칸은 하나뿐이다. 그냥 덮어쓰면 **전설 예약 위에 고급을 올려서 등급이 내려가고**
            // 산 전설이 그대로 사라진다 — 화면은 "예약됐어요" 라고만 말했다.
            // 같거나 낮은 등급은 거절한다. 소모 전에 막아야 아이템이 남는다.
            if let pending = save.pendingSeedGuarantee,
               let next = item.seedGuarantee,
               pending.sortRank >= next.sortRank {
                return .noEffect(reason: "이미 \(pending.label) 확정이 예약돼 있어요 — 이식하면 다시 쓸 수 있어요")
            }
            consume(item, &save)
            save.pendingSeedGuarantee = item.seedGuarantee
            return .ok(waterGained: 0)

        case .decorBox:
            // **아직 없는 것 중에서만** 뽑는다. 중복이 나오면 "돈 냈는데 꽝"이 생기고,
            // 그 한 번으로 뽑기가 도박이 된다 — 여기서 얻고 싶은 건 기대감뿐이다.
            let owned = Set(save.decorations)
            let pool = DecorIcons.gachaKeys.filter { !owned.contains($0) }
            guard !pool.isEmpty else {
                return .noEffect(reason: "장식을 다 모았어요 — 정원에 전부 놓여 있어요")
            }
            consume(item, &save)
            let picked = pool[Int(roll % UInt64(pool.count))]
            save.decorations.append(picked)
            push(&save, .decorFound(key: picked))
            return .ok(waterGained: 0)

        case .shinyCharm, .potSlot, .bench, .feeder, .lantern:
            return .noEffect(reason: "보유형이라 항상 적용돼요")
        }
    }

    private static func consume(_ item: ShopItem, _ save: inout PlantSave) {
        let n = save.count(item)
        if n <= 1 { save.inventory.removeValue(forKey: item.rawValue) }
        else { save.inventory[item.rawValue] = n - 1 }
    }

    // MARK: 이식 · 새 씨앗

    /// 정원으로 옮긴다. **수동**이다 — 자동으로 넘기면 거목을 못 보고 지나친다.
    /// `slot` 0 = 첫 화분, 1 = 화분 슬롯으로 늘린 두 번째.
    @discardableResult
    static func transplant(_ save: inout PlantSave, slot: Int = 0, roll: UInt64, now: Date = Date()) -> Bool {
        let key: WritableKeyPath<PlantSave, PotState?> = slot == 0 ? \.pot : \.pot2
        guard let pot = save[keyPath: key], pot.isReadyToTransplant else { return false }
        // **상한이 없다.** 예전엔 30그루에서 막았는데, 그러면 정원이 꽉 찬 순간
        // 이식이 조용히 실패하고 화분이 완주 상태로 영원히 대기한다 — 게임이 멈춘다.
        // (사이클 9일이었을 때 9개월이면 도달했다.)
        // 기록은 전부 쌓고, 씬은 `GardenTier.displayCount` 만큼만 그린다.

        save.garden.append(GardenEntry.from(pot: pot, at: now))
        push(&save, .transplanted(speciesID: pot.speciesID, isShiny: pot.isShiny))

        save[keyPath: key] = nil
        plantNewSeed(&save, slot: slot, roll: roll, now: now)
        return true
    }

    /// 새 그루의 목표(mL). **여기 하나만 고치면 모든 경로가 따라온다** —
    /// 예전엔 `plantNewSeed` 와 `buy(.potSlot)` 이 따로 계산해서 둘째 화분만 기본값을 받았다.
    ///
    /// 환산비율은 상수가 아니라 **이 사람 실측값**을 쓴다. `rawPerML = 6,957` 로 박아뒀는데
    /// 실제로는 8,193 이 찍혀서(18% 차이) 28일이어야 할 사이클이 33일이 됐다.
    /// 아직 못 재면 상수로 물러난다.
    static func seedCycle(_ save: PlantSave) -> Int {
        let ratio = PlantBalance.measuredRawPerML(raw: save.dailyRaw, water: save.dailyWater)
            ?? PlantBalance.rawPerML
        return PlantBalance.cycleWater(dailyRaw: PlantBalance.dailyRawRate(save.dailyRaw),
                                       rawPerML: ratio)
    }

    /// 새 씨앗을 심는다. 종은 등급 가중 추첨, 반짝은 별개로 굴린다.
    static func plantNewSeed(_ save: inout PlantSave, slot: Int = 0, roll: UInt64, now: Date = Date()) {
        let key: WritableKeyPath<PlantSave, PotState?> = slot == 0 ? \.pot : \.pot2
        // 보증은 첫 화분에만 소비한다 — 두 슬롯이 동시에 완주해도 산 것을 두 번 받으면 안 된다.
        let guarantee = slot == 0 ? save.pendingSeedGuarantee : nil
        if slot == 0 { save.pendingSeedGuarantee = nil }
        let species = PlantOdds.pickSpecies(roll: roll, guarantee: guarantee)
        let shiny = PlantOdds.rollsShiny(roll: roll >> 10, charmOwned: save.hasShinyCharm)
        // 이 그루의 목표를 **여기서 한 번** 정한다. 그 사람 속도로 4주.
        // 자라는 동안에는 절대 안 바뀐다 — 바뀌면 많이 쓴 날 목표도 같이 도망간다.
        let cycle = seedCycle(save)
        save[keyPath: key] = PotState(speciesID: species.id, water: 0, stageIndex: 0,
                                      isShiny: shiny, plantedAt: now, cycleWater: cycle)
        push(&save, .newSeed(speciesID: species.id, rarity: species.rarity, isShiny: shiny))
    }

    // MARK: 연출 대기열

    /// 같은 종류는 마지막 것만 남긴다.
    static func push(_ save: inout PlantSave, _ event: PlantEvent) {
        save.pendingEvents.removeAll { $0.coalesceKey == event.coalesceKey }
        save.pendingEvents.append(event)
        // 대기열이 무한정 자라지 않게 상한을 둔다.
        if save.pendingEvents.count > 8 { save.pendingEvents.removeFirst(save.pendingEvents.count - 8) }
    }

    /// 팝오버가 열릴 때 한 번 비운다.
    static func drainEvents(_ save: inout PlantSave) -> [PlantEvent] {
        let e = save.pendingEvents
        save.pendingEvents = []
        return e
    }

    // MARK: 표시 상태

    static func displayState(_ save: PlantSave, today: String, now: Date = Date()) -> PlantStateKind {
        if save.pendingEvents.contains(where: { $0.coalesceKey == "levelUp" }) { return .levelUp }
        guard let pot = save.pot else { return .seed }

        let thirst = thirstLevel(save, today: today)
        if thirst >= 1 { return .parched }
        if thirst > 0 { return .thirsty }

        // 가방에 쓸 게 있으면 그게 최우선 문구다 — 사놓고 잊어버리면 산 의미가 없다.
        if save.count(.water) > 0 || save.count(.nutrient) > 0
            || (save.count(.fertilizer) > 0 && !save.fertilizerActive(now: now)) {
            return .hasItems
        }
        if pot.stageIndex == 0 { return .seed }
        return .idle
    }
}
