import Foundation

/// 상점 품목. 값은 **원시 토큰** — 메뉴바에 뜨는 그 숫자로 산다.
///
/// 화분은 토큰만 써도 저절로 자란다. 상점은 그걸 **더 빠르게** 하는 곳이다.
/// 지갑에서 써도 이미 자란 건 줄지 않는다 — 성장(가중 환산 mL)과 지갑(원시 토큰)은
/// 같은 강에서 갈린 두 물길이라 서로 뺏지 않는다.
///
/// 그래서 PokeTokenBar 의 억제책(사탕을 값어치의 5배로 매기기)이 필요 없다.
/// 거기선 `쓸 수 있는 재화 = 쓴 토큰 − 쓴 재화` 라 성장 게이지와 지갑이 같은 값이었다.
/// 여기서 가속의 천장은 가격이 아니라 **수입**이 정한다:
/// 물에 쓸 수 있는 몫은 **하루 상한(`dailyWaterUses`)이 막는다** — 유입의 40%, 가속 1.4배.
/// 예전엔 값이 막았는데(0.2일치 × 5개 = 하루치, 2배), 그게 유입을 100% 먹어서 지갑이 안 쌓였다.
///
/// ## 세 소모품이 모양이 다른 이유
///
/// 값만 다르고 하는 일이 같으면 제일 싼 것만 사게 된다. 그래서 다른 축에 뒀다.
///
/// | | 모양 | 언제 값을 하나 |
/// |---|---|---|
/// | 물 | 정액 · 즉시 | 언제나 같다. 지금 한 칸 더 |
/// | 거름 | 배율 · 7일 지속 | 앞으로 꾸준히 쓸 때만 |
/// | 영양제 | 비례 · 즉시 | 갓 심었을 때 크고, 거목 앞에선 작다 |
///
/// 셋의 값어치는 ±20% 안에서 비슷하다. 갈리는 건 **언제 쓰느냐**뿐이고, 그게 고민거리다.
enum ShopItem: String, Codable, Sendable, CaseIterable {
    case water            // 물 — 정액. 지금 바로 한 칸 더
    case fertilizer       // 거름 — 배율. 7일간 들어오는 물이 늘어난다
    case nutrient         // 영양제 — 비례. 남은 거리를 당긴다
    case premiumSeed      // 고급 씨앗 (희귀 이상 확정)
    case legendarySeed    // 전설 씨앗
    case shinyCharm       // 반짝 부적 (영구)
    case potSlot          // 화분 슬롯 (영구)
    /// 장식 뽑기 — 아직 없는 장식 하나가 랜덤으로 나온다. **중복이 없으니 꽝도 없다.**
    ///
    /// 보유형 다섯 개는 17일이면 다 팔리고, 그 뒤 상점엔 새로 열리는 게 없다.
    /// 장식을 열두 개로 늘려 직접 다 파는 것도 방법이지만, 그러면 비싼 순서대로
    /// 사는 목록이 되어 살 때 아무 일도 안 일어난다. 뽑기는 **누르는 순간에 결과가 있다**.
    case decorBox         // 장식 뽑기
    case bench            // 벤치 (장식)
    case feeder           // 새 모이통 (장식)
    case lantern          // 석등 (장식)

    var name: String {
        switch self {
        case .decorBox: return "장식 뽑기"
        case .water: return "물"
        case .fertilizer: return "거름"
        case .nutrient: return "영양제"
        case .premiumSeed: return "고급 씨앗"
        case .legendarySeed: return "전설 씨앗"
        case .shinyCharm: return "반짝 부적"
        case .potSlot: return "화분 슬롯"
        case .bench: return "벤치"
        case .feeder: return "새 모이통"
        case .lantern: return "석등"
        }
    }

    var category: String {
        switch self {
        case .water, .fertilizer, .nutrient: return "성장"
        case .premiumSeed, .legendarySeed: return "씨앗"
        case .shinyCharm, .potSlot: return "정원"
        case .bench, .feeder, .lantern, .decorBox: return "장식"
        }
    }

    /// 값을 **일**로 정한다. 원시 토큰 수는 파생값이다.
    ///
    /// 절대 수치로 정하면 화면에서 무너진다 — `157,500,000` 은 그냥 큰 숫자라서
    /// 하루만 참으면 되는 건지 한 달을 모아야 하는 건지 알 수가 없다.
    /// 값을 일로 정하면 "며칠치 토큰인가"가 곧 가격이고, 그건 화면에 쓸 수 있다.
    ///
    /// 하루치는 `PlantBalance.dailyRawRate` 로 **각자 측정**한다(사람마다 10배씩 다르다).
    /// 일수 자체는 고정이다 — 토큰을 많이 쓴 날 가격표가 흔들리면 아무것도 계획할 수 없다.
    var priceDays: Double {
        switch self {
        // 물은 토큰과 **1:1 등가 교환**이다: 0.2일치를 내면 하루 자동 성장의 1/5 만큼 받는다.
        // 이 값은 건드리지 않는다 — 내리면 거름(1.17배)·영양제(초반 2.24배)가 전부 물보다
        // 나빠져서 상점의 나머지가 죽는다. "물을 얼마나 살 수 있나"는 값이 아니라
        // `PlantBalance.dailyWaterUses` 상한으로 조절한다. 거기 이유를 적어뒀다.
        case .water: return 0.2
        case .bench: return 1          // 장식 최저가. 하루만 모으면 정원이 바뀐다
        case .fertilizer: return 1.5   // 7일 +25% = 1.75일치 회수 → 1.17배 (얇은 마진이 성격)
        case .feeder: return 2
        case .nutrient: return 1.5     // 남은 거리의 10%. 초반 1.87배, 사이클 절반 넘으면 0.93배
        case .lantern: return 3
        case .premiumSeed: return 4    // 희귀 이상 확정 — 한 사이클의 약 1/6
        // 벤치와 같은 하루치. 벤치 하나 값으로 **무엇이 나올지 모르는** 하나를 산다 —
        // 그 차이가 이 품목의 전부다. 아홉 개를 다 모으려면 9일치(전설 씨앗보다 비싸다).
        case .decorBox: return 1
        // 상단 셋은 20·20·13일치였다. 하루 상한을 고친 뒤에도 여기가 멀어서
        // 7일째 고급 씨앗 다음에 **8일 공백**이 남았다. 절반으로 내렸다:
        // 7일 고급 → 12일 전설 → 17일 슬롯·부적, 최대 공백 5일.
        // 더 내려도 공백은 5일에서 안 줄어든다(전설 앞이 병목) — 그래서 여기서 멈춘다.
        case .potSlot: return 10       // 두 그루째 (영구)
        case .legendarySeed: return 7
        case .shinyCharm: return 10    // 영구. 1/128 → 1/32
        }
    }

    /// 이 사람의 하루 유입으로 환산한 값(원시 토큰).
    func price(dailyRaw: Int) -> Int { Int(priceDays * Double(dailyRaw)) }

    /// 기준 하루치(측정 전)로 환산한 값 — 표·문서·테스트의 기준점.
    var price: Int { price(dailyRaw: PlantBalance.assumedDailyRaw) }

    /// 보유형(영구) — 소비되지 않고 한 번 사면 계속 효과. 재구매 불가.
    var isPassive: Bool {
        switch self {
        case .shinyCharm, .potSlot, .bench, .feeder, .lantern: return true
        default: return false
        }
    }

    /// 다음 부화에 예약되는 씨앗류 — 개수를 세지만 즉시 발동은 아니다.
    var seedGuarantee: PlantRarity? {
        switch self {
        case .premiumSeed: return .rare
        case .legendarySeed: return .legendary
        default: return nil
        }
    }

    /// 성장에 **아무 영향이 없는** 품목 — 장식 셋과 장식 뽑기.
    ///
    /// `isDecoration` 과 다르다: 장식 뽑기는 정원에 놓이는 물건이 아니라 그걸 뽑는
    /// 소모품이라 `isDecoration` 이 false 다. 그런데 "다음 목표"에서 빼야 하는 기준은
    /// **성장에 도움이 되느냐**이지 정원에 놓이느냐가 아니다. 안 갈라두면
    /// 하루치짜리 뽑기가 늘 다음 목표로 걸려서, 모아야 할 이유를 또 못 준다.
    var isCosmetic: Bool { category == "장식" }

    /// 정원에 놓이는 장식인가 — 효과는 없고 순수 꾸미기다.
    var isDecoration: Bool {
        switch self {
        case .bench, .feeder, .lantern: return true
        default: return false
        }
    }

    var fallbackEmoji: String {
        switch self {
        case .water: return "💧"
        case .fertilizer: return "💩"
        case .nutrient: return "🧪"
        case .premiumSeed: return "🌰"
        case .legendarySeed: return "✨"
        case .shinyCharm: return "🔮"
        case .potSlot: return "➕"
        case .bench: return "🪑"
        case .feeder: return "🐦"
        case .lantern: return "🏮"
        case .decorBox: return "🎁"
        }
    }

    /// 가격 오름차순 — 뷰가 단일 목록으로 그린다.
    ///
    /// 값이 같은 품목이 있으면(화분 슬롯·반짝 부적 둘 다 20일) Swift 의 정렬은 **안정적이지 않아서**
    /// 실행할 때마다 순서가 바뀔 수 있다. rawValue 를 2차 키로 둬 순서를 고정한다.
    static var sortedByPrice: [ShopItem] {
        allCases.sorted { ($0.price, $0.rawValue) < ($1.price, $1.rawValue) }
    }
}

/// 물 — **정액**. 언제 써도 같은 양이라 값이 흔들리지 않는다. 셋 중 제일 싸고 제일 자주 쓴다.
///
/// 양을 이렇게 정한 이유: `0.2일 × 5 = 하루치`. 지갑 하루치를 통째로 물에 쏟으면
/// 상한까지 부으면 하루 자동 성장의 40% 만큼 더 자란다 — 가속 1.4배.
enum Water {
    /// 그 사람 하루 성장의 1/5. 값도 하루치의 1/5 이라 **1:1 등가 교환**이고,
    /// 하루에 몇 개까지 살 수 있는지는 `PlantBalance.dailyWaterUses` 가 정한다.
    ///
    /// `rawPerML` 을 받는 이유: 상수로 환산하면 **1:1 이 깨진다.**
    /// 값은 그 사람 하루 토큰의 1/5 인데 mL 은 평균 환산비율로 만드니까,
    /// 캐시읽기가 많아 환산비율이 나쁜 사람은 자기 하루 성장의 1/5 보다 **더 많이** 받는다.
    /// 실측으로는 물 배율이 설계 예산 ×1.40 대신 ×1.57 로 나왔다.
    /// 목표(`seedCycle`)가 이미 실측 비율을 쓰므로 여기도 맞춘다.
    static func mL(dailyRaw: Int, rawPerML: Int = PlantBalance.rawPerML) -> Int {
        max(1, dailyRaw / max(1, rawPerML) / 5)
    }

    /// 기준 하루치로 환산한 값 — 표·문서·테스트의 기준점.
    static var mL: Int { mL(dailyRaw: PlantBalance.assumedDailyRaw) }
}

/// 영양제 — **비례**. 이 그루의 남은 거리를 10% 당긴다.
/// 일찍 쓸수록 남은 양이 많아 크게 먹는다. 거목 앞에서 쓰면 값도 못 건진다 — 그게 이 품목의 성격이다.
///
/// 10% 였을 때는 물보다 이득인 구간이 **사이클 26.5일 중 첫 1.5일뿐**이라 사실상 죽은 품목이었다.
/// 20% 면 손익분기가 Lv.8(14일째)로 가서 사이클의 절반이 이득 구간이 된다.
enum Nutrient {
    /// 20% 였다. 갓 심은 그루에 한 개가 자동 성장 5.6일치라 사이클을 통째로 20% 잘라먹었고,
    /// 총 배율이 2배를 넘어간 원인 중 하나였다. 10% 로 내려도 초반 회수비는 1.87배다.
    static let reducePercent = 10

    /// 물로 환산한 실효 — 이식까지 남은 거리의 10%. 목표가 그루마다 달라서 `cycle` 을 받는다.
    static func water(currentWater: Int, cycle: Int) -> Int {
        let remaining = max(0, cycle - currentWater)
        return (remaining * reducePercent) / 100
    }
}

/// 구매 결과 — 실패 이유를 값으로 돌려준다.
/// 회색 버튼만 두면 사용자가 왜 못 사는지 모른다. 부족한 잔액을 그대로 보여줘야 한다.
enum PurchaseResult: Sendable, Equatable {
    case ok
    case insufficientBalance(short: Int)
    case alreadyOwned
}

/// 사용 결과.
enum UseResult: Sendable, Equatable {
    case ok(waterGained: Int)
    case notOwned
    case noEffect(reason: String)
}
