import Foundation

/// 표시 상태 — 사용량/방치로 결정(스프라이트 모션·상태 문구).
/// PokeTokenBar 의 `CompanionStateKind` 자리를 그대로 대체한다.
enum PlantStateKind: String, Sendable {
    /// `hasItems` = 창고에 쓸 게 있다. 화분은 토큰만으로도 자라지만,
    /// 사놓고 잊어버린 물·영양제가 있으면 화면이 그걸 말해줘야 한다.
    case seed, idle, hasItems, thirsty, parched, levelUp
}

/// 종 등급.
enum PlantRarity: String, Codable, Sendable, CaseIterable {
    case common, uncommon, rare, legendary

    var sortRank: Int {
        switch self {
        case .common: return 0
        case .uncommon: return 1
        case .rare: return 2
        case .legendary: return 3
        }
    }

    /// 화면에 쓰는 이름. 예전엔 `ShopView` 안의 private 헬퍼로만 있어서
    /// 엔진이 등급을 문구에 쓰려면 같은 표를 또 만들어야 했다.
    var label: String {
        switch self {
        case .common: return "흔함"
        case .uncommon: return "보통"
        case .rare: return "희귀"
        case .legendary: return "전설"
        }
    }

    /// 출현 가중치(합 1000). 흔함 620 · 보통 250 · 희귀 100 · 전설 30.
    var weight: Int {
        switch self {
        case .common: return 620
        case .uncommon: return 250
        case .rare: return 100
        case .legendary: return 30
        }
    }

    /// 정원에서 차지하는 칸 수. 희귀 이상은 두 칸을 먹고 뒤에 그림자가 붙는다.
    var gardenSlots: Int { sortRank >= 2 ? 2 : 1 }
}

/// 정원용 실루엣 종류. 종을 늘릴 때 그림을 새로 그리지 않기 위해
/// **실루엣 3종 × 팔레트 N종** 으로 조합한다. 실루엣 하나로 30그루를 놓으면 초록 벽이 된다.
enum PlantShape: String, Codable, Sendable, CaseIterable {
    case round, tall, low
}

/// 종 정의 — 실루엣 + 잎 팔레트. 전부 로컬이라 네트워크가 필요 없다.
/// (PokeTokenBar 는 스프라이트·종 정보를 PokéAPI 에서 받아야 해서 오프라인이면 부화가 막힌다.)
struct PlantSpecies: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var name: String
    var rarity: PlantRarity
    var shape: PlantShape
    /// 잎 팔레트 — 화분 단계와 정원 스프라이트가 공유한다.
    var leaf: String
    var leafLight: String
    var leafShade: String
    /// 꽃잎 색. nil = 기본값 사용.
    var petal: String?
    /// 꽃·열매 모티프. 화분 스프라이트에서 이 종을 알아보게 하는 유일한 형태 차이다.
    var motif: BloomMotif

    static let catalog: [PlantSpecies] = [
        // 흔함
        .init(id: "dandelion", name: "민들레", rarity: .common, shape: .low,
              leaf: "#7fc46b", leafLight: "#a9dd93", leafShade: "#54924a", petal: "#f5c542", motif: .daisy),
        .init(id: "tomato", name: "방울토마토", rarity: .common, shape: .round,
              leaf: "#5ec489", leafLight: "#93e0ac", leafShade: "#399263", petal: "#f2e8a0", motif: .berry),
        .init(id: "lettuce", name: "상추", rarity: .common, shape: .low,
              leaf: "#8fd06a", leafLight: "#b8e598", leafShade: "#5f9c46", petal: nil, motif: .ruffle),
        .init(id: "sunflower", name: "해바라기", rarity: .common, shape: .tall,
              leaf: "#5ab377", leafLight: "#8ad39c", leafShade: "#357f52", petal: "#f5c542", motif: .sun),
        .init(id: "morningglory", name: "나팔꽃", rarity: .common, shape: .round,
              leaf: "#6cbf95", leafLight: "#9bdcb6", leafShade: "#428b68", petal: "#8f7fd6", motif: .trumpet),
        // 보통
        .init(id: "rose", name: "장미", rarity: .uncommon, shape: .round,
              leaf: "#3f9c6d", leafLight: "#72c496", leafShade: "#2a6f4c", petal: "#d8546d", motif: .rosette),
        .init(id: "tulip", name: "튤립", rarity: .uncommon, shape: .tall,
              leaf: "#63bd85", leafLight: "#95d8ab", leafShade: "#3f8a5e", petal: "#e5674f", motif: .cup),
        .init(id: "lavender", name: "라벤더", rarity: .uncommon, shape: .tall,
              leaf: "#7fb894", leafLight: "#a9d4b8", leafShade: "#578870", petal: "#9b7fd4", motif: .spike),
        .init(id: "monstera", name: "몬스테라", rarity: .uncommon, shape: .low,
              leaf: "#358f5f", leafLight: "#68b98a", leafShade: "#226642", petal: nil, motif: .split),
        // 희귀
        .init(id: "bamboo", name: "대나무", rarity: .rare, shape: .tall,
              leaf: "#8fc46b", leafLight: "#b8dd96", leafShade: "#62924a", petal: nil, motif: .node),
        .init(id: "maple", name: "단풍", rarity: .rare, shape: .round,
              leaf: "#e0783f", leafLight: "#f0a565", leafShade: "#b0522a", petal: "#e0503f", motif: .star),
        .init(id: "cherry", name: "벚나무", rarity: .rare, shape: .round,
              leaf: "#f2a8c0", leafLight: "#ffd0de", leafShade: "#d47f9c", petal: "#f7c3d5", motif: .cluster),
        .init(id: "cactus", name: "꽃선인장", rarity: .rare, shape: .low,
              leaf: "#6fae72", leafLight: "#9ccb9e", leafShade: "#4a7f4d", petal: "#f2748c", motif: .needle),
        // 전설
        .init(id: "worldtree", name: "세계수", rarity: .legendary, shape: .tall,
              leaf: "#4fbfa0", leafLight: "#8fe0c9", leafShade: "#2d8570", petal: "#bfe8ff", motif: .bell),
        .init(id: "rainbow", name: "무지개꽃", rarity: .legendary, shape: .round,
              leaf: "#7fd0b0", leafLight: "#b5ecd6", leafShade: "#4f9c82", petal: "#ff8fb8", motif: .aurora),
    ]

    static func byID(_ id: String) -> PlantSpecies? { catalog.first { $0.id == id } }

    static func all(_ rarity: PlantRarity) -> [PlantSpecies] { catalog.filter { $0.rarity == rarity } }

    /// 행운 변종 — 잎만 금색으로 갈아끼운다. 스프라이트는 그대로다.
    /// 종마다 행운 그림을 따로 그리면 15종 × 11장이 두 배가 된다.
    static func shinyPalette(of s: PlantSpecies) -> PlantSpecies {
        var out = s
        out.leaf = "#f0cf5c"
        out.leafLight = "#ffe89a"
        out.leafShade = "#c2a02f"
        return out
    }

    /// 도감 칸 키 — (종, 행운) 조합이 각각 한 칸이다.
    static func dexKey(_ id: String, shiny: Bool) -> String { "\(id):\(shiny ? "s" : "n")" }
}

/// 개체 롤 확률.
enum PlantOdds {
    /// 행운 변종 분모 — 1/128. 등급과 별개로 굴린다.
    static let shinyDenominator: UInt64 = 128
    /// 행운 부적 보유 시 — 1/32.
    ///
    /// 1/64 였을 때는 20일치를 내고 정원 30그루 동안 행운이 0.23 → 0.47마리였다.
    /// 한 마리도 확실하지 않은 데 사이클의 3/4을 거는 셈이라 아무도 안 산다.
    /// 1/32 면 0.94마리 — "정원 하나에 행운 하나" 가 되어 값이 이유를 갖는다.
    static let shinyDenominatorWithCharm: UInt64 = 32

    static func rollsShiny(roll: UInt64, charmOwned: Bool) -> Bool {
        let d = charmOwned ? shinyDenominatorWithCharm : shinyDenominator
        return roll % d == 0
    }

    /// 등급 가중 추첨. `roll` 은 0..<1000.
    /// `guarantee` 가 있으면 그 등급 **이상** 만 후보로 둔다(고급/전설 씨앗).
    static func pickSpecies(roll: UInt64, guarantee: PlantRarity?) -> PlantSpecies {
        let pool: [PlantSpecies]
        if let g = guarantee {
            pool = PlantSpecies.catalog.filter { $0.rarity.sortRank >= g.sortRank }
        } else {
            pool = PlantSpecies.catalog
        }
        let candidates = pool.isEmpty ? PlantSpecies.catalog : pool
        let totalWeight = candidates.reduce(0) { $0 + $1.rarity.weight }
        var cursor = Int(roll % UInt64(max(1, totalWeight)))
        for s in candidates {
            cursor -= s.rarity.weight
            if cursor < 0 { return s }
        }
        return candidates[candidates.count - 1]
    }
}

/// 현재 키우는 화분 한 그루.
struct PotState: Codable, Sendable, Equatable {
    var speciesID: String
    var water: Int              // 누적 물(mL)
    var stageIndex: Int         // 0-based, PlantBalance.stageFractions 기준
    var isShiny: Bool
    var plantedAt: Date
    var nickname: String?
    /// 이 그루의 이식 목표(mL). **심을 때 그 사람 속도로 정해지고 끝까지 안 바뀐다.**
    /// 사이클 중간에 따라 움직이면 많이 쓴 날 목표도 같이 늘어나 "쓰면 자란다"가 깨진다.
    var cycleWater: Int
    /// 열매 연출을 이미 봤는지. 8단계에 한 번만 재생한다 —
    /// 매 갱신마다 다시 터지면 축하가 아니라 소음이 된다.
    var fruitHarvested: Bool
    /// 이 그루에 영양제를 몇 번 줬는지. **그루에** 기록해야 이식할 때 저절로 풀린다.
    var nutrientUses: Int

    /// 목표를 이 사람 속도로 이미 한 번 맞췄나.
    ///
    /// **재조정은 그루당 한 번뿐이어야 한다.** 매번 다시 맞췄더니 규칙 하나가 뒤집혔다:
    /// 며칠 쉬면 14일 평균이 내려가 목표가 줄고, 재조정은 "줄이는 방향만"이라 그대로 적용돼서
    /// **진행도가 앞으로 점프**했다. 실측으로 20일차에 안 쉰 사람 73.0%, 사흘 쉰 사람 82.1% —
    /// 스트릭은 빠짐을 벌주는데 여기서는 빠짐이 이득이었다.
    ///
    /// 재조정의 목적은 "남의 기본값(105M/일)에서 내 값으로 **한 번 오는 것**"이지
    /// 내 사용량 변동을 계속 따라다니는 게 아니다.
    var cycleFitted: Bool

    init(speciesID: String, water: Int = 0, stageIndex: Int = 0, isShiny: Bool = false,
         plantedAt: Date = Date(), nickname: String? = nil, fruitHarvested: Bool = false,
         cycleWater: Int = PlantBalance.legacyCycleWater, nutrientUses: Int = 0,
         cycleFitted: Bool = false) {
        self.cycleFitted = cycleFitted
        self.speciesID = speciesID
        self.water = water
        self.stageIndex = stageIndex
        self.isShiny = isShiny
        self.plantedAt = plantedAt
        self.nickname = nickname
        self.fruitHarvested = fruitHarvested
        self.nutrientUses = max(0, nutrientUses)
        self.cycleWater = max(PlantBalance.minCycleWater, cycleWater)
    }

    var species: PlantSpecies {
        PlantSpecies.byID(speciesID) ?? PlantSpecies.catalog[0]
    }

    /// 이식 가능 여부 — 거목 + 여유분까지 채웠는가.
    var isReadyToTransplant: Bool {
        stageIndex >= PlantBalance.stageCount - 1 && water >= cycleWater
    }

    /// 이 그루의 단계 임계값.
    func threshold(stage idx: Int) -> Int {
        PlantBalance.threshold(stage: idx, cycle: cycleWater)
    }

    /// 다음 단계까지 남은 물. 이식까지 넘겼으면 nil.
    var nextThreshold: Int? {
        PlantBalance.nextThreshold(afterStage: stageIndex, cycle: cycleWater)
    }

    /// 손상된 저장값 흡수 — 인덱스가 범위를 벗어나면 렌더마다 크래시한다.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speciesID = try c.decode(String.self, forKey: .speciesID)
        water = max(0, (try? c.decode(Int.self, forKey: .water)) ?? 0)
        let saved = (try? c.decode(Int.self, forKey: .stageIndex)) ?? 0
        stageIndex = min(max(0, saved), PlantBalance.stageCount - 1)
        isShiny = (try? c.decode(Bool.self, forKey: .isShiny)) ?? false
        plantedAt = (try? c.decode(Date.self, forKey: .plantedAt)) ?? Date()
        nickname = try? c.decode(String.self, forKey: .nickname)
        fruitHarvested = (try? c.decode(Bool.self, forKey: .fruitHarvested)) ?? false
        // 이 필드가 없던 그루는 0 으로 시작한다 — 키우던 그루에서 영양제를 한 번 더
        // 쓸 수 있게 되는 건 손해가 아니라 이득이라 그대로 둔다.
        nutrientUses = max(0, (try? c.decode(Int.self, forKey: .nutrientUses)) ?? 0)
        // 이 필드가 없던 시절의 그루는 예전 목표를 그대로 쓴다 —
        // 키우던 그루의 목표를 업데이트가 바꿔버리면 안 된다.
        let savedCycle = (try? c.decode(Int.self, forKey: .cycleWater)) ?? PlantBalance.legacyCycleWater
        cycleWater = max(PlantBalance.minCycleWater, savedCycle)
        // 이 필드가 없던 그루는 **아직 재조정을 안 받은 것**으로 친다. 재조정은 어차피
        // 물이 목표의 1/3 아래일 때만 걸리므로, 한창 키우던 그루의 목표가 바뀌지는 않는다.
        cycleFitted = (try? c.decode(Bool.self, forKey: .cycleFitted)) ?? false
    }
}

/// 정원에 이식된 그루 — 명패에 뜨는 정보가 전부 여기 들어 있다.
struct GardenEntry: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var speciesID: String
    var isShiny: Bool
    var nickname: String?
    var plantedAt: Date
    var transplantedAt: Date
    /// 부은 총 물. 이식 시점의 누적값.
    var totalWater: Int

    init(id: String = UUID().uuidString, speciesID: String, isShiny: Bool = false,
         nickname: String? = nil, plantedAt: Date, transplantedAt: Date = Date(), totalWater: Int) {
        self.id = id
        self.speciesID = speciesID
        self.isShiny = isShiny
        self.nickname = nickname
        self.plantedAt = plantedAt
        self.transplantedAt = transplantedAt
        self.totalWater = totalWater
    }

    var species: PlantSpecies { PlantSpecies.byID(speciesID) ?? PlantSpecies.catalog[0] }

    /// 씨앗에서 이식까지 걸린 일수.
    var daysToGrow: Int {
        max(1, Calendar.current.dateComponents([.day], from: plantedAt, to: transplantedAt).day ?? 1)
    }

    static func from(pot: PotState, at date: Date = Date()) -> GardenEntry {
        GardenEntry(speciesID: pot.speciesID, isShiny: pot.isShiny, nickname: pot.nickname,
                    plantedAt: pot.plantedAt, transplantedAt: date, totalWater: pot.water)
    }
}

/// 정원 티어 — 완성한 그루 수로 오른다.
struct GardenTier: Sendable, Equatable {
    var key: String
    var name: String
    var need: Int
    var canvas: (w: Int, h: Int)
    var unlock: String

    static let all: [GardenTier] = [
        .init(key: "sill",   name: "창가",      need: 0,  canvas: (72, 40),   unlock: "화분만"),
        .init(key: "balc",   name: "베란다",    need: 1,  canvas: (88, 44),   unlock: "첫 이식"),
        .init(key: "bed",    name: "작은 화단", need: 3,  canvas: (104, 48),  unlock: "정원 창"),
        // "명패" 라고 적어뒀는데 명패는 잠겨 있지 않다 — 정원 창이 열리는 3그루부터 바로 눌린다.
        // 뒷마당에서 실제로 새로 생기는 건 울타리와 길이다.
        .init(key: "yard",   name: "뒷마당",    need: 6,  canvas: (136, 56),  unlock: "울타리·길"),
        .init(key: "green",  name: "온실",      need: 10, canvas: (168, 64),  unlock: "계절·밤낮"),
        .init(key: "arbor",  name: "수목원",    need: 18, canvas: (224, 88),  unlock: "연못·PNG 내보내기"),
        .init(key: "forest", name: "비밀의 숲", need: 30, canvas: (272, 104), unlock: "정원 만렙"),
    ]

    static func tier(forCount n: Int) -> GardenTier {
        var found = all[0]
        for t in all where n >= t.need { found = t }
        return found
    }

    static func next(afterCount n: Int) -> GardenTier? {
        all.first { $0.need > n }
    }

    /// 마지막 티어에 도달하는 그루 수. **상한이 아니라 만렙 기준이다** —
    /// 이식은 여기서 멈추지 않고, 정원은 계속 늘어난다.
    static var maxCount: Int { all[all.count - 1].need }

    /// 씬에 한 번에 그리는 그루 수. 캔버스가 고정 도트라 자리가 유한하다.
    /// 넘어가면 **최근 그루**를 그리고, 오래된 건 도감과 기록에 남는다 —
    /// 자리가 없다고 이식을 막는 건 순서가 거꾸로다.
    static var displayCount: Int { maxCount }

    static func == (lhs: GardenTier, rhs: GardenTier) -> Bool { lhs.key == rhs.key }
}
