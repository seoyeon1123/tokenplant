import Foundation

/// 토큰 4종 증분. 가중 환산에 원본 분해가 필요해 총합(Int)만으로는 부족하다.
/// UsageStore 의 `DailyUsage` 에서 만들어 넘긴다.
struct TokenDelta: Codable, Sendable, Equatable {
    var input: Int
    var output: Int
    var cacheWrite: Int
    var cacheRead: Int

    init(input: Int = 0, output: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
    }

    /// 앱이 메뉴바에 띄우는 원시 토큰 수 — 성장이 아니라 표시용.
    var raw: Int { input + output + cacheWrite + cacheRead }

    var isZero: Bool { raw == 0 }

    static func - (lhs: TokenDelta, rhs: TokenDelta) -> TokenDelta {
        TokenDelta(input: lhs.input - rhs.input,
                   output: lhs.output - rhs.output,
                   cacheWrite: lhs.cacheWrite - rhs.cacheWrite,
                   cacheRead: lhs.cacheRead - rhs.cacheRead)
    }

    static func + (lhs: TokenDelta, rhs: TokenDelta) -> TokenDelta {
        TokenDelta(input: lhs.input + rhs.input,
                   output: lhs.output + rhs.output,
                   cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
                   cacheRead: lhs.cacheRead + rhs.cacheRead)
    }

    /// 음수 성분 제거 — 프로바이더 카운터가 리셋되면(로그 정리·세션 삭제) 델타가 음수로 나온다.
    /// 그때 물을 깎으면 사용자가 아무 잘못도 안 했는데 화분이 되돌아간다.
    var clampedToZero: TokenDelta {
        TokenDelta(input: max(0, input), output: max(0, output),
                   cacheWrite: max(0, cacheWrite), cacheRead: max(0, cacheRead))
    }
}

/// 성장 밸런스 — 2026-08-10~09-09 실측(Claude Code + Codex, 달력일 평균 15,080 mL) 기준.
enum PlantBalance {

    // MARK: 물 환산

    /// 가중치 ×100 (정수 연산 유지용). 출력 5 · 입력 1 · 캐시생성 1.25 · 캐시읽기 0.1
    ///
    /// 원시 토큰을 그대로 쓰면 안 되는 이유: 실측에서 캐시 읽기가 원시의 **98%** 였다.
    /// 그대로 세면 성장이 곧 캐시 읽기 양이 되어, 읽기만 한 날과 코드를 쏟아낸 날이 똑같이 자란다.
    /// 가격 비중을 따라 가중치를 매기면 출력이 최소한의 발언권을 갖는다.
    static let wOutput = 500
    static let wInput = 100
    static let wCacheWrite = 125
    static let wCacheRead = 10

    /// 물 1mL = 가중 토큰 1,000개.
    static let tokensPerML = 1_000

    /// 토큰 증분 → 물(mL). 내림. 실측 원시:물 비율은 대략 7.2 : 1.
    static func water(from d: TokenDelta) -> Int {
        let c = d.clampedToZero
        // 가중합 ×100 → mL 로 내리려면 ×100 을 되돌리고 1,000 으로 나눈다 = 100,000 으로 나눈다.
        let weighted100 = c.output * wOutput
            + c.input * wInput
            + c.cacheWrite * wCacheWrite
            + c.cacheRead * wCacheRead
        return weighted100 / (tokensPerML * 100)
    }

    /// 물 → 원시 토큰 상당(표시용 참고값). 실측 비율 7.2 를 쓴다.
    static func approxRawTokens(forWater mL: Int) -> Int {
        Int((Double(mL) * Double(tokensPerML) * 7.2).rounded())
    }

    // MARK: 단계

    /// 단계 임계값을 **비율**로 둔다 (1.0 = 이식). 절대 mL 은 그루마다 다르다.
    ///
    /// 앞쪽을 촘촘히 둔 건 의도다 — 첫날 세 단계(발아·떡잎·어린잎)가 반나절 안에 지나가야
    /// 다음날 또 열어본다. 뒤로 갈수록 배씩 벌어져 마지막 한 칸(열매→거목)이 전체의 1/3이다.
    /// 거목(0.9375)과 이식(1.0) 사이의 여유도 여기 들어 있다 —
    /// 만렙에서 바로 끊으면 할 일이 없어져 그날 앱을 닫는다.
    static let stageFractions: [Double] = [
        0,        // 1 씨앗
        0.00375,  // 2 발아
        0.0125,   // 3 떡잎
        0.03,     // 4 어린잎
        0.0675,   // 5 자란 줄기
        0.13,     // 6 꽃봉오리
        0.235,    // 7 첫 꽃
        0.3925,   // 8 만개
        0.6175,   // 9 열매
        0.9375,   // 10 거목
    ]

    static var stageCount: Int { stageFractions.count }

    // MARK: 사이클 길이 — **사람마다 다르다**
    //
    // 임계값을 절대 mL 로 박아두면 밸런스가 한 사람 데이터에 묶인다.
    // 하루 105M 을 쓰는 사람에겐 27일이지만 5M 을 쓰는 사람에겐 **1년 반**이다.
    // 느린 게 아니라 안 자라는 것이고, 그 사람은 5단계도 못 보고 앱을 지운다.
    //
    // 그래서 씨앗을 심는 순간 **그 사람 속도로 목표를 한 번 고정**한다.
    // 사이클 중간에 목표가 따라 움직이면 안 된다 — 많이 쓴 날 목표도 같이 늘어나서
    // "쓰면 자란다"가 깨진다. 다음 그루부터 다시 잰다.

    /// 한 그루에 목표로 삼는 기간. 4주 — "한 달에 한 그루"가 기억하기 좋다.
    static let targetCycleDays = 28

    /// 목표 물의 바닥과 천장.
    ///
    /// 순수 비례로 두면 극단에서 무너진다 — 거의 안 쓰는 사람은 대화 한 번에 한 단계가 오르고,
    /// 종일 돌리는 사람은 도달 불가능한 목표를 받는다. 바닥에 걸리면 4주보다 길어지고
    /// 천장에 걸리면 짧아지는데, 그건 의도한 결과다(아주 적게 쓰면 그만큼 오래 걸려야 한다).
    ///
    /// 바닥이 30,000 이었을 때는 하루 5M 쓰는 사람(가볍지만 **진짜** 사용자)이 42일에 걸렸다.
    /// 바닥은 "사실상 안 쓰는 계정"만 걸러야 한다 — 하루 1.7M 아래가 거기다.
    static let minCycleWater = 7_000
    static let maxCycleWater = 2_000_000

    /// 지금 이 사람의 속도로 계산한 한 그루 목표(mL). 씨앗을 심을 때 한 번만 부른다.
    ///
    /// `rawPerML` 을 인자로 받는다 — 상수는 한 사람의 한 달치에서 나온 값이라 작업 성격이
    /// 바뀌면 어긋난다(실측 8,193 vs 상수 6,957 = 18%, 28일이 33일이 된다).
    /// 호출부는 `PlantEngine.seedCycle` 하나로 모으고 거기서 실측값을 넘긴다.
    static func cycleWater(dailyRaw: Int, rawPerML: Int = PlantBalance.rawPerML) -> Int {
        let perDay = max(1, dailyRaw / max(1, rawPerML))
        return min(maxCycleWater, max(minCycleWater, perDay * targetCycleDays))
    }

    /// 구버전 세이브(이 필드가 없던 그루)가 쓰는 값. 기존 그루의 목표를 바꾸면 안 된다.
    static let legacyCycleWater = 400_000

    /// 이 그루의 단계 임계값(누적 mL).
    static func threshold(stage idx: Int, cycle: Int) -> Int {
        guard idx >= 0 else { return 0 }
        guard idx < stageCount else { return cycle }
        return Int(stageFractions[idx] * Double(cycle))
    }

    /// 누적 물 → 단계 인덱스(0-based). 만렙에서 더 부어도 마지막 인덱스에 머문다.
    static func stageIndex(forWater mL: Int, cycle: Int) -> Int {
        var idx = 0
        for i in 0..<stageCount where mL >= threshold(stage: i, cycle: cycle) { idx = i }
        return idx
    }

    /// 다음 단계 임계값. 만렙이면 이식 임계값(= cycle), 이식까지 넘겼으면 nil.
    static func nextThreshold(afterStage idx: Int, cycle: Int) -> Int? {
        if idx + 1 < stageCount { return threshold(stage: idx + 1, cycle: cycle) }
        if idx == stageCount - 1 { return cycle }
        return nil
    }

    // MARK: 첫 설치 — 소급은 없다
    //
    // 설치 전에 쓴 토큰은 **한 톨도** 안 센다. 기준선만 잡고 0에서 시작한다.
    //
    // 예전엔 "이틀치까지" 인정했다. 0 을 보여주면 고장난 것처럼 보인다는 게 이유였는데,
    // 그 상한이 어느 **단계**에 떨어지는지를 안 봤다. 단계 문턱이 앞쪽에 몰려 있어서
    // (5단계가 사이클의 6.75%) 이틀치 = 7.14% 는 **정확히 5단계를 넘긴다.**
    // 설치 전에 그날 이틀치 이상 쓴 사람은 예외 없이 「Lv.5 자란 줄기」로 시작했고,
    // 씨앗에서 싹이 트는 구간을 통째로 못 봤다. 첫 그루가 이 앱의 전부인데.
    //
    // 상한을 *일* 로 적고 결과를 *단계* 로 읽는 바람에 양쪽 다 맞아 보였던 실수다.
    // 지금은 규칙이 하나다 — **설치 이후에 쓴 것만 센다.** 성장도 지갑도 같이.
    // 활발히 쓰는 사람이면 다음 갱신(30초)에 바로 움직이고, 아무것도 안 쓴 날은
    // 씨앗 상태 문구("토큰을 쓰면 저절로 자랍니다")가 그 자리를 맡는다.

    // MARK: 두 물길
    //
    // 쓴 토큰 하나가 두 곳으로 간다.
    //
    //   가중 환산 mL ──▶ 화분. **저절로 자란다.** 앱을 안 열어도 자란다
    //   원시 토큰   ──▶ 지갑. 물·거름·영양제를 사서 **더 빨리** 자라게 한다
    //
    // 둘은 서로 뺏지 않는다. 상점에서 써도 이미 자란 건 그대로다.
    // PokeTokenBar 는 `쓸 수 있는 재화 = 쓴 토큰 − 쓴 재화` 라 성장 게이지와 지갑이
    // 같은 값이었고, 그래서 사탕을 값어치의 5배로 팔아야만 무한 자가성장이 막혔다.
    // 여기선 강 하나에서 물길이 둘로 갈리는 것뿐이라 그 문제가 없다 —
    // 가속 폭도 결국 실제로 쓴 토큰에 묶여 있어서 루프가 닫히지 않는다.

    /// 원시 토큰 : 물(mL) 실측 비율. 1mL 를 만드는 데 원시 토큰이 이만큼 든다.
    /// (실측 하루: 원시 109,254,100 → 물 15,706mL)
    static let rawPerML = 6_957

    /// 하루에 들어오는 원시 토큰(측정 전 기본값). 2026-08~09 실측 달력일 평균.
    /// 이 값이 상점 가격의 **단위**다 — 가격은 전부 "하루치의 몇 배"로 정의돼 있다.
    static let assumedDailyRaw = 105_000_000

    /// 하루 자동 성장량(mL). 물값이 하루치의 1/5 이라 **물 1개 = 이 값의 1/5** 이고,
    /// 그래서 물은 토큰과 1:1 등가 교환이다.
    ///
    /// 여기에 곱해지는 게 `dailyWaterUses` 다. 예전엔 그게 5였고 5 × 1/5 = 1.0,
    /// 즉 상한까지 부으면 유입을 **전부** 먹었다 — 그래서 지갑이 영원히 0이었다.
    /// 지금은 2 × 1/5 = 0.4. 가속 천장은 1.4배고, 남는 0.6이 상점을 살린다.
    static var dailyWaterFromTokens: Int { assumedDailyRaw / rawPerML }

    // MARK: 하루 유입 측정
    //
    // 가격이 "하루치의 몇 배"라서, 그 하루치를 앱이 직접 재야 한다.
    // 상수로 박으면 남의 속도로 환산된다 — 사람마다 하루 유입이 10배씩 다르다.

    /// 하루 유입을 재는 창. 14일인 이유: 주 단위 리듬(주중에 몰아 쓰고 주말에 안 씀)이
    /// 두 번 들어가야 평탄해진다.
    static let dailyRawWindow = 14

    /// 표본이 이보다 짧으면 측정값을 안 믿는다.
    ///
    /// 하루치로 평균을 내면 그날이 무거웠는지 가벼웠는지에 따라 환산이 11배까지 튄다
    /// (실측 중위 7,552mL · 최대 83,717mL). 틀린 "0.2일치"는 아무 숫자도 안 쓴 것보다 나쁘다.
    static let dailyRawMinDays = 3

    /// 최근 창의 **달력일 평균**. 안 쓴 날도 0으로 세는 게 맞다 — 실제로 지갑이 차는 속도가 그거다.
    static func dailyRawRate(_ daily: [String: Int]) -> Int {
        let keys = daily.keys.sorted()
        guard let first = keys.first, let last = keys.last else { return assumedDailyRaw }
        let span = DayKey.days(from: first, to: last) + 1
        guard span >= dailyRawMinDays else { return assumedDailyRaw }
        let total = daily.values.reduce(0, +)
        return max(1, total / span)
    }

    /// **오늘을 뺀** 평균. "오늘 평소 대비 몇 %"를 말하려면 기준에 오늘이 있으면 안 된다.
    ///
    /// `dailyRawRate` 는 오늘을 포함한다(가격 환산에는 그게 맞다 — 지금 이 순간 하루치가 얼마인가).
    /// 그런데 비교 기준으로 쓰면 아침엔 오늘 몫이 거의 0인데 분모는 오늘을 이미 하루로 세서
    /// 평균이 내려가고, 결국 **오늘이 끌어내린 평균과 오늘을 견주게** 된다.
    static func baselineRawRate(_ daily: [String: Int], today: String) -> Int? {
        let past = daily.filter { $0.key != today }
        let keys = past.keys.sorted()
        guard let first = keys.first, let last = keys.last else { return nil }
        let span = DayKey.days(from: first, to: last) + 1
        guard span >= dailyRawMinDays else { return nil }
        return max(1, past.values.reduce(0, +) / span)
    }

    /// 실측 환산비율 — 원시 토큰 몇 개가 1mL 인가.
    ///
    /// `rawPerML` 상수는 한 사람의 한 달치에서 나온 값이라 작업 성격이 바뀌면 어긋난다
    /// (실제로 6,957 로 박아뒀는데 화면엔 8,193 이 찍혔다 — 18% 차이).
    /// 사이클 목표가 이 값으로 계산되므로, 28일이어야 할 게 33일이 된다.
    /// 둘 다 쌓아두고 나눠서 **각자 재는 게** 맞다.
    static func measuredRawPerML(raw: [String: Int], water: [String: Int]) -> Int? {
        let keys = Set(raw.keys).intersection(water.keys)
        guard keys.count >= dailyRawMinDays else { return nil }
        let r = keys.reduce(0) { $0 + (raw[$1] ?? 0) }
        let w = keys.reduce(0) { $0 + (water[$1] ?? 0) }
        guard w > 0, r > 0 else { return nil }
        return max(1, r / w)
    }

    /// 창 밖으로 나간 날을 버린다. 세이브에 1년치가 쌓이면 읽고 쓰는 비용이 계속 는다.
    ///
    /// **`today` 를 무조건 믿으면 안 된다.** 이 정리는 `today` 를 기준으로 도는데,
    /// 시계가 앞으로 튀면(RTC 오류, 수동 변경) 기존 키가 전부 창 밖으로 밀려서
    /// **한 번의 적립으로 측정 기록 전체가 사라진다.** 그러면 하루 유입이 기본값으로
    /// 돌아가고, 가격·사이클 목표·"며칠치"가 모두 남의 값으로 환산된다.
    /// `historyBackfilled` 가 켜져 있으니 다시 채워지지도 않는다.
    ///
    /// 그래서 가장 새 기록보다 창 두 배 이상 앞선 `today` 는 안 믿고 정리를 건너뛴다.
    /// 시계가 정상으로 돌아오면 다음 적립에서 평소대로 정리된다.
    static func prunedDailyRaw(_ daily: [String: Int], today: String) -> [String: Int] {
        if let newest = daily.keys.max(),
           DayKey.days(from: newest, to: today) > dailyRawWindow * 2 {
            return daily
        }
        return daily.filter { DayKey.days(from: $0.key, to: today) < dailyRawWindow }
    }

    /// 원시 토큰 → 며칠치. 표시 전용이라 Double 로 돌려준다.
    static func days(forRaw raw: Int, rate: Int) -> Double {
        Double(raw) / Double(max(1, rate))
    }

    // MARK: 보너스

    // MARK: 보너스 총량 — **합쳐서 얼마가 되는지가 기준이다**
    //
    // 하나씩 정할 때는 다 합리적이었는데, 곱해놓고 보니 28일 사이클이 **9일**이었다:
    //
    //     자동 1.00 + 물 0.40 = 1.40
    //     × (스트릭 50% + 거름 25%) = 2.45
    //     + 영양제(남은 거리의 20%)  → 28일 목표가 9.1일
    //
    // 3.06배. 환산비율 18% 어긋남보다 훨씬 큰 오차였고, 가격이 "며칠치" 단위라
    // 상점 속도도 같이 어긋나 있었다. 그래서 **총 배율을 2배로 묶는다** —
    // 아무것도 안 하면 28일, 다 하면 14일. 예산은 이렇게 나눴다:
    //
    //     물(유료·상한 2개)      ×1.40   ← 돈을 내는 손잡이라 제일 크게
    //     스트릭 10% + 거름 25%  ×1.35
    //     영양제(그루당 1회)      ×1.11
    //     ─────────────────────────────
    //     합계                   ×2.10  → 13.3일
    //
    // 손잡이가 여섯 개(물 상한·물값·스트릭·거름%·거름값·영양제)라 손으로 맞추면 다른 게
    // 깨진다. 실제로 처음엔 거름까지 같이 내렸다가 회수비가 1.40배로 튀어서
    // "마진이 얇아야 고민이 된다"는 조건을 깼다. 제약을 다 적어놓고 조합을 훑으니
    // **스트릭과 영양제 둘만** 고치면 되는 답이 나왔다. 거름은 건드리지 않는다.
    //
    // 같이 지킨 제약: 거름 회수비 1.0~1.2배 · 영양제 손익분기가 사이클의 40~60% ·
    // 영양제 초반 1.5배 이상 · 총 격차 1.85~2.15배.

    /// 연속 사용일 보너스 — `+min(N, 10)%`. 10일에 천장.
    ///
    /// 예전엔 `min(N×2, 50)` 이라 25일이면 +50% 였다. 총 배율이 3배로 부푼 주범이다.
    /// 스트릭은 **공짜로 자동 적립되는** 보너스인데, 돈을 내는 물(+40%)보다 커지면
    /// 상점에 갈 이유가 없다. 하루 +1%, 천장 +10% 로 내렸다.
    static func streakBonusPercent(days: Int) -> Int { min(max(0, days), 10) }

    /// 거름 지속 보너스 — **여기는 그대로다.** 25% / 7일 / 1.5일치면 회수비가 1.17배로,
    /// 물보다 조금 낫지만 압도하지는 않는다. 그 얇은 마진이 이 품목의 성격이다.
    static let fertilizerBonusPercent = 25
    static let fertilizerDays = 7

    /// 거름이 남을 수 있는 최대 일수. 이어 붙이기의 천장이다.
    ///
    /// 왜 천장이 필요한가: 안 두면 지갑이 남는 사람이 1년치를 쌓아놓고 잊는다.
    /// 3주면 사이클(14~28일) 하나를 덮으므로 "지금 필요한 만큼"의 상한으로 충분하다.
    static let fertilizerMaxDays = 21

    /// 보너스를 먹인 실제 적립 물. 배수가 아니라 **가산**으로 합친다 —
    /// 곱으로 두면 스트릭 25일 + 거름이 1.5×1.25 = 1.875배가 되어 상점 상한 검증이 깨진다.
    static func applied(water mL: Int, streakDays: Int, fertilizerActive: Bool) -> Int {
        let bonus = streakBonusPercent(days: streakDays) + (fertilizerActive ? fertilizerBonusPercent : 0)
        return mL + (mL * bonus) / 100
    }

    // MARK: 목마름 — **외형만** 바뀐다
    //
    // 누적 물을 깎지 않는다. 잔액 모델에서는 물을 안 주면 안 자라는 것 자체가 이미 결과인데,
    // 거기에 진행도까지 뺏으면 실제로 쓴 토큰을 두 번 벌주는 셈이다.
    // 잔액은 그동안에도 계속 쌓이므로, 며칠 만에 열어도 잃은 건 없고 부을 게 많다.
    //
    // 대신 색은 마른다 — 돌봐야 한다는 느낌은 남기고, 한 번 부으면 바로 돌아온다.

    /// 마지막으로 물을 준 뒤 이 일수부터 색이 마르기 시작한다.
    // MARK: 하루에 줄 수 있는 양
    //
    // 지갑은 계속 이월된다. 그래서 상한이 없으면 며칠 안 쓰고 모았다가 하루에 다 쏟을 수 있고,
    // 실제로 30일치를 모으면 **하루 만에** 한 사이클이 끝났다(물 98개). 4주짜리 사이클이
    // 하루로 무너지면 남은 설계가 전부 의미를 잃는다.
    //
    // "최대 2배"는 **하루 수입 기준 평균**이었지, 하루에 쓸 수 있는 양의 상한이 아니었다.
    // 그 구분을 안 해둔 게 구멍이었다.
    //
    // 상한은 **횟수**로 센다. mL 로 세면 화면에 쓸 수가 없다 —
    // "오늘 12,074mL 남음"보다 "오늘 1/2"이 읽힌다.
    //
    // **5에서 2로 내렸다 — 이게 상점을 죽이고 있던 한 줄이다.**
    //
    // 5개 × 0.2일치 = 정확히 하루 유입이다. 물 버튼은 항상 눈에 보이고 항상 살 수 있고
    // 즉시 보상이 있어서, 사람은 당연히 상한까지 붓는다. 그러면 유입의 **100%** 가
    // 물로 나가고 지갑이 영원히 0이다 — 일주일 넘게 써도 물밖에 못 산다.
    //
    // 값을 내리는 게 아니라 상한을 내려야 한다. 물은 토큰과 1:1 등가 교환이라 값을
    // 내리면 거름·영양제가 전부 물보다 나빠진다. 그래서 규칙을 이렇게 읽는다:
    // **하루 유입의 40% 까지만 가속에 쓸 수 있다.** 나머지 60% 는 지갑에 남는다.
    //
    // 대가: 최대 가속 2.0배 → 1.4배, 완주 13일 → 17일.
    // 얻는 것: 상점 전 품목이 20일 안에 열린다(전에는 영원히 안 열렸다).
    static let dailyWaterUses = 2

    /// 영양제는 **한 그루에 한 번**. 횟수로는 못 막는 품목이라 따로 둔다.
    ///
    /// 비례 품목이라 갓 심었을 때 한 개가 자동 성장 **5.6일치**다(값은 2.5일치).
    /// 물처럼 횟수로만 세면 영양제만 연달아 써서 나흘 만에 끝난다(7배).
    /// 한 그루에 한 번으로 두면 "언제 쓰느냐"가 비로소 진짜 고민이 된다 —
    /// 그게 원래 이 품목의 성격이다.
    static let nutrientUsesPerPlant = 1

    static let thirstyAfterIdleDays = 3
    /// 완전히 마른 색이 되는 일수. 여기가 바닥이고 더 나빠지지 않는다.
    static let parchedAfterIdleDays = 7

    // MARK: 한도 창 소진 보상 — **지갑으로** 들어간다
    //
    // 5시간 창과 주간 창은 **안 쓰면 사라진다.** 누적 토큰만 보는 설계는 그 만료를 모른다.
    // 그래서 창을 다 태운 것 자체를 지갑에 얹는다 — 많이 쓴 것과 한도까지 밀어붙인 것은
    // 다른 수고다. 지급은 **엣지 트리거**: 100% 를 새로 넘는 순간 1회, 리셋되면 다시 무장한다.
    //
    // 성장이 아니라 지갑에 넣는 이유: 만료되는 자원을 **남는 것**으로 바꾸는 게 목적이라,
    // 성장에 바로 꽂으면 "안 쓰면 사라지는 걸 건졌다"는 실감이 안 난다.

    /// 세션급(≈5시간) 창 100% — 하루 유입의 약 10%.
    static let windowBonusSession = 10_000_000
    /// 주간 창 100% — 세션의 5배. 주간을 다 태우는 건 드물고 그만큼 무겁다.
    static let windowBonusWeekly = 50_000_000

    /// 사이클 추정에 쓰는 가정치 — **창을 100%까지 태우는 횟수**다. 활동일 수가 아니다.
    ///
    /// 처음엔 "실측 활동일 비율 26/59" 로 적어놨는데 그 계산이 틀렸다.
    /// 달력일 평균 15,080 ÷ 활동일 평균 17,655 = 85% 라 26.5일 중 **23일**이 활동일이다.
    /// 다만 활동일이라고 5시간 창을 끝까지 태우는 건 아니라서, 그 23일을 그대로 쓰면
    /// 보상을 크게 부풀리게 된다. 태우는 빈도는 아직 실측이 없어 11로 둔다 —
    /// 이 값은 아래 sanity check 에만 쓰이고 실제 지급은 창 상태가 결정하므로 게임엔 영향이 없다.
    static let assumedSessionWindowsPerCycle = 11
    static let assumedWeeklyWindowsPerCycle = 3

    /// 한 사이클에 창 보상으로 들어오는 원시 토큰.
    /// 사이클 수입(26.5일 × 하루치)의 10% 안쪽이어야 한다 —
    /// 넘으면 토큰을 거의 안 써도 창만 태워서 상점을 굴릴 수 있게 된다.
    static var estimatedWindowBonusPerCycle: Int {
        assumedSessionWindowsPerCycle * windowBonusSession
            + assumedWeeklyWindowsPerCycle * windowBonusWeekly
    }
}
