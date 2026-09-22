import Foundation

// 스프라이트 데이터. 전부 로컬이라 네트워크가 필요 없다 —
// PokeTokenBar 는 PokéAPI 에서 스프라이트와 종 정보를 받아야 해서 오프라인이면 부화가 막힌다.
//
// 손으로 그리는 건 **실루엣뿐**이고 아웃라인과 음영은 `decorate()` 가 만든다.
// 종을 늘릴 때 실루엣 하나만 추가하면 되는 이유가 이것이다.

/// 픽셀 문자 → 색. 잎/줄기/꽃은 종 팔레트가 덮어쓴다.
enum PlantPalette {
    static let base: [Character: String] = [

        "K": "#2b2016",
        "G": "#5ec489",
        "L": "#93e0ac",
        "d": "#399263",
        "g": "#3d8b5f",
        "F": "#f47f96",
        "f": "#d8546d",
        "Y": "#f5c542",
        "R": "#e0503f",
        "r": "#b93a2c",
        "O": "#b08355",
        "T": "#7a5436",
        "t": "#5c3d26",
        "D": "#5b4232",
        "q": "#e5926b",
        "P": "#c9724f",
        "p": "#a35434",
        "W": "#ffffff",
        "y": "#c2a94f",
    ]

    /// 시든 잎 — 초록 계열만 마른 노랑으로 갈아끼운다.
    static let wilted: [Character: String] = [
        "G": "#c9b45c", "L": "#ddcd82", "d": "#9a8639",
        "g": "#8f7c33", "F": "#c9a08f", "f": "#a8806f", "Y": "#c9b45c",
    ]

    /// 자동 음영 매핑 — 아래가 비어 있으면 그림자색으로 바꾼다.
    static let shade: [Character: Character] = [
        "G": "d", "L": "G", "F": "f", "R": "r", "T": "t", "g": "d",
    ]
}

/// 24×24 화분 스프라이트 — 10단계. 실루엣(17줄) + 공용 화분(7줄).
enum PotSprites {
    static let size = 24
    static let plantRows = 17

    /// 모든 단계가 공유하는 화분. 아웃라인이 이미 들어 있다.
    static let pot: [String] = [

        "....KKDDDDDDDDDDDDKK....",
        "....KqqqqqqqqqqqqqqK....",
        "....KPPPPPPPPPPPPPpK....",
        ".....KPPPPPPPPPPPPpK....",
        ".....KPPPPPPPPPPPPpK....",
        "......KPPPPPPPPPPpK.....",
        ".......KKKKKKKKKK.......",
    ]

    struct Stage: Sendable {
        let level: Int
        let name: String
        let silhouette: [String]
    }

    static let stages: [Stage] = [

        .init(level: 1, name: "씨앗", silhouette: [
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "..........OOO...........",
            ".........OOOOO..........",
        ]),
        .init(level: 2, name: "발아", silhouette: [
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "..........LGG...........",
            "..........GGG...........",
            "...........g............",
            "...........g............",
            "..........OgO...........",
        ]),
        .init(level: 3, name: "떡잎", silhouette: [
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........LG.....GL.......",
            ".......GGGG...GGGG......",
            "........GGG...GGG.......",
            ".........GG.GG..........",
            "..........GgG...........",
            "...........g............",
            "...........g............",
            "...........g............",
            "...........g............",
        ]),
        .init(level: 4, name: "어린잎", silhouette: [
            "........................",
            "........................",
            "........................",
            "........................",
            "........................",
            "........LG.....GL.......",
            ".......GGGG...GGGG......",
            "........GGG...GGG.......",
            ".........GG.GG..........",
            "..........GgG...........",
            "......LG...g...GL.......",
            ".....GGGG..g..GGGG......",
            "......GGG..g..GGG.......",
            ".......GG..g..GG........",
            "........GG.g.GG.........",
            "...........g............",
            "...........g............",
        ]),
        .init(level: 5, name: "자란 줄기", silhouette: [
            "........................",
            "........................",
            "..........LGG...........",
            ".........GGGG...........",
            "..........GgG...........",
            "........LG.g...GL.......",
            ".......GGGG.g.GGGG......",
            "........GGG.g.GGG.......",
            ".........GG.g.GG........",
            "...........g............",
            ".....LG....g....GL......",
            "....GGGG...g...GGGG.....",
            ".....GGG...g...GGG......",
            "......GG...g...GG.......",
            ".......GG..g..GG........",
            "........GG.g.GG.........",
            "...........g............",
        ]),
        .init(level: 6, name: "꽃봉오리", silhouette: [
            "........................",
            "...........F............",
            "..........FFF...........",
            "..........FFF...........",
            "..........GgG...........",
            "........LG.g...GL.......",
            ".......GGGG.g.GGGG......",
            "........GGG.g.GGG.......",
            ".........GG.g.GG........",
            "...........g............",
            ".....LG....g....GL......",
            "....GGGG...g...GGGG.....",
            ".....GGG...g...GGG......",
            "......GG...g...GG.......",
            ".......GG..g..GG........",
            "........GG.g.GG.........",
            "...........g............",
        ]),
        .init(level: 7, name: "첫 꽃", silhouette: [
            "........................",
            ".........FFFFF..........",
            "........FFFFFFF.........",
            "........FFYYYFF.........",
            "........FFYYYFF.........",
            ".........FFFFF..........",
            "..........LgL...........",
            "........LG.g...GL.......",
            ".......GGGG.g.GGGG......",
            "........GGG.g.GGG.......",
            ".........GG.g.GG........",
            ".....LG....g....GL......",
            "....GGGG...g...GGGG.....",
            ".....GGG...g...GGG......",
            "......GG...g...GG.......",
            ".......GG..g..GG........",
            "...........g............",
        ]),
        .init(level: 8, name: "만개", silhouette: [
            "........................",
            "..FFF....FFFFF....FFF...",
            ".FFYFF..FFFFFFF..FFYFF..",
            "..FFF...FFYYYFF...FFF...",
            "...g....FFYYYFF....g....",
            "...g.....FFFFF.....g....",
            "...g......LgL......g....",
            "....g....LGgGL....g.....",
            ".....gGGGGGgGGGGGg......",
            ".......GG..g..GG........",
            ".....LG....g....GL......",
            "....GGGG...g...GGGG.....",
            ".....GGG...g...GGG......",
            "......GG...g...GG.......",
            ".......GG..g..GG........",
            "........GG.g.GG.........",
            "...........g............",
        ]),
        .init(level: 9, name: "열매", silhouette: [
            "........................",
            "..FFF....FFFFF....FFF...",
            ".FFYFF..FFFFFFF..FFYFF..",
            "..FFF...FFYYYFF...FFF...",
            "...g.....FFFFF.....g....",
            "...g......LgL......g....",
            "..RRR....LGgGL....RRR...",
            "..RRR...GGGGGGG...RRR...",
            "...gGGGG...g...GGGGg....",
            ".....GGG..RRR..GGG......",
            ".....LG...RRR...GL......",
            "....GGGG...g...GGGG.....",
            ".....GGG...g...GGG......",
            "......GG...g...GG.......",
            ".......GG..g..GG........",
            "........GG.g.GG.........",
            "...........g............",
        ]),
        .init(level: 10, name: "거목", silhouette: [
            "........................",
            ".......GGGGGGGGGG.......",
            ".....GGGLLGGGGGGGGG.....",
            "....GGGGGGGGGGGRRGGG....",
            "...GGGGGGGGGGGGGRGGGG...",
            "...GGGLLGGGGGGGGGGGGG...",
            "...GGGGGGGGRRGGGGLLGG...",
            "....GGGGGGGGRGGGGGGG....",
            ".....GGGGGGTTGGGGGG.....",
            ".......GGGGTTGGGG.......",
            ".........GGTTGG.........",
            "...........TT...........",
            "...........TT...........",
            "...........TT...........",
            "..........TTTT..........",
            ".........TTTTTT.........",
            "........TTTTTTTT........",
        ]),
    ]

    /// 꽃으로 세는 문자. 잎만 남길 때 이것들을 지운다.
    static let bloomChars: Set<Character> = ["F", "Y", "R", "r", "W", "f", "p"]

    /// 원본 실루엣에서 꽃을 떼고 **잎만** 남긴다.
    ///
    /// 꽃 자리를 투명하게 비우면 안 된다 — 꽃은 잎 덩이 **위에** 얹혀 있어서,
    /// 비워 두면 모티프가 원본보다 작을 때 구멍이 남는다. 잎으로 덮어 두면
    /// 어떤 크기의 스탬프를 찍어도 자연스럽다.
    static func foliage(_ rows: [String]) -> [String] {
        rows.map { row in
            String(row.map { bloomChars.contains($0) ? "G" : $0 })
        }
    }

    /// 스탬프를 (row, col) **중심**에 찍는다. 격자를 벗어나는 부분은 잘라낸다.
    static func stamp(_ grid: inout [[Character]], _ art: [String], row: Int, col: Int) {
        let h = art.count
        let w = art.first?.count ?? 0
        let top = row - h / 2
        let left = col - w / 2
        for (y, line) in art.enumerated() {
            for (x, ch) in line.enumerated() where ch != "." {
                let gy = top + y
                let gx = left + x
                guard gy >= 0, gy < grid.count, gx >= 0, gx < grid[gy].count else { continue }
                // `_` 는 구멍 — 밑의 잎을 지운다. 나머지는 그대로 칠한다.
                grid[gy][gx] = (ch == "_") ? "." : ch
            }
        }
    }

    /// 단계 + 모티프 → 아웃라인·음영까지 입힌 24×24 문자 그리드.
    ///
    /// 종마다 실루엣 10장을 그리면 150장이다. 잎은 공용으로 두고 **꽃만 갈아끼운다** —
    /// 사람이 알아보는 건 결국 꽃이고, 잎 덩이는 종이 달라도 비슷하게 생겼다.
    static func grid(stageIndex idx: Int, motif: BloomMotif) -> [[Character]] {
        let i = min(max(0, idx), stages.count - 1)
        var plant = foliage(stages[i].silhouette).map { Array($0) }
        let art = motif.art
        for anchor in BloomLayout.anchors[i] {
            let stampArt: [String]
            switch anchor.size {
            case .bud:   stampArt = BloomBud.art
            case .small: stampArt = art.small
            case .big:   stampArt = art.big
            case .fruit: stampArt = art.fruit
            }
            stamp(&plant, stampArt, row: anchor.row, col: anchor.col)
        }
        return PlantSpriteBuilder.decorate(plant.map { String($0) }, appending: pot)
    }
}

/// 16×16 정원 스프라이트 — 화분 없이 흙무덤에 심긴 모습.
///
/// 화분 스프라이트는 정원에 쓸 수 없다: 24×24 안에 화분이 들어 있어 땅에 심으면 화분째 묻히고,
/// 24px 은 정원에 열 그루만 놓아도 화면을 넘긴다. 그래서 종마다 스프라이트가 11장이다
/// (화분 10단계 + 지면 심기 1장).
///
/// 실루엣은 세 종류만 둔다. 하나로 30그루를 놓으면 초록 벽처럼 보인다.
enum GardenSprites {
    static let size = 16

    static let shapes: [PlantShape: [String]] = [

        .round: [
            "....GGGGGGGG....",
            "..GGGGGGGGGGGG..",
            ".GGGGLLGGGGGGGG.",
            ".GGGGGGGGGGGGGG.",
            "..GGGGGGGGGGGG..",
            "...GGGGGGGGGG...",
            ".....GGGTGGG....",
            ".......TT.......",
            ".......TT.......",
            ".......TT.......",
            ".......TT.......",
            "......TTTT......",
            "......TTTT......",
            ".....TTTTTT.....",
            "...DDDDDDDDDD...",
            "..DDDDDDDDDDDD..",
        ],
        .tall: [
            ".......GG.......",
            "......GGGG......",
            ".....GGLLGG.....",
            "....GGGGGGGG....",
            "...GGGGGGGGGG...",
            "...GGGGGGGGGG...",
            "....GGGGGGGG....",
            ".....GGGGGG.....",
            "......GGGG......",
            ".......TT.......",
            ".......TT.......",
            ".......TT.......",
            "......TTTT......",
            ".....TTTTTT.....",
            "...DDDDDDDDDD...",
            "..DDDDDDDDDDDD..",
        ],
        .low: [
            "................",
            "................",
            "...GGGG..GGGG...",
            "..GGGGGGGGGGGG..",
            ".GGGLLGGGGGGGGG.",
            ".GGGGGGGGGGGGGG.",
            "..GGGGGGGGGGGG..",
            "...GGGGTTGGGG...",
            ".....GGTTGG.....",
            ".......TT.......",
            ".......TT.......",
            "......TTTT......",
            "......TTTT......",
            "....TTTTTTTT....",
            "...DDDDDDDDDD...",
            "..DDDDDDDDDDDD..",
        ],
    ]

    /// 모양 + 모티프 → 16×16 문자 그리드.
    ///
    /// 화분과 같은 모티프를 `small`(5×3)로 얹는다. `big`(7×5)은 16칸 안에서 잎을 다 덮어
    /// 꽃만 둥둥 뜬 것처럼 보인다.
    static func grid(_ shape: PlantShape, motif: BloomMotif) -> [[Character]] {
        var plant = (shapes[shape] ?? shapes[.round]!).map { Array($0) }
        let art = motif.art.small
        for anchor in GardenBloomLayout.anchors(shape) {
            PotSprites.stamp(&plant, art, row: anchor.row, col: anchor.col)
        }
        return PlantSpriteBuilder.decorate(plant.map { String($0) }, appending: [])
    }
}

/// 실루엣에 아웃라인과 음영을 자동으로 입힌다.
enum PlantSpriteBuilder {
    static let outlineChar: Character = "K"
    /// 배경을 절차적으로 그릴 때도 같은 아웃라인 색을 써야 씬과 스프라이트가 한 덩어리로 보인다.
    static var outlineHex: String { base(for: outlineChar) ?? "#2b2016" }

    static func base(for ch: Character) -> String? { PlantPalette.base[ch] }

    /// 1) 아래가 비어 있는 픽셀을 그림자색으로 2) 빈 칸인데 4방향 이웃이 있으면 아웃라인.
    /// `appending` 은 이미 아웃라인이 들어 있는 부분(화분)이라 손대지 않고 아래에 붙인다.
    static func decorate(_ silhouette: [String], appending tail: [String]) -> [[Character]] {
        var rows = silhouette.map { Array($0) }
        let h = rows.count
        let w = rows.first?.count ?? 0

        func solid(_ x: Int, _ y: Int) -> Bool {
            guard y >= 0, y < h, x >= 0, x < w else { return false }
            return rows[y][x] != "."
        }

        // 음영
        var shaded = rows
        for y in 0..<h {
            for x in 0..<w {
                let c = rows[y][x]
                if let s = PlantPalette.shade[c], !solid(x, y + 1) { shaded[y][x] = s }
            }
        }

        // 아웃라인
        var out = shaded
        for y in 0..<h {
            for x in 0..<w where rows[y][x] == "." {
                let neighbours = [(1, 0), (-1, 0), (0, 1), (0, -1)]
                if neighbours.contains(where: { solid(x + $0.0, y + $0.1) }) {
                    out[y][x] = outlineChar
                }
            }
        }

        rows = out
        return rows + tail.map { Array($0) }
    }

    /// 종 팔레트와 시듦 정도를 반영한 색 조회. nil = 투명.
    static func color(_ ch: Character, species: PlantSpecies, wilt: Double) -> String? {
        if ch == "." { return nil }
        var base = PlantPalette.base[ch]
        switch ch {
        case "G": base = species.leaf
        case "L": base = species.leafLight
        case "d": base = species.leafShade
        case "F": base = species.petal ?? PlantPalette.base["F"]
        // 겹꽃(장미) 그림자. 종마다 따로 정의하지 않고 꽃잎색을 어둡게 만든다 —
        // 팔레트에 고정색으로 두면 어떤 종이든 장미색 그림자가 생긴다.
        case "f": base = darken(species.petal ?? PlantPalette.base["F"] ?? "#f47f96", 0.72)
        default: break
        }
        guard let hex = base else { return nil }
        guard wilt > 0.01, let dry = PlantPalette.wilted[ch] else { return hex }
        return blend(hex, dry, wilt)
    }

    /// 색을 비율만큼 어둡게. 겹꽃 그림자를 꽃잎색에서 파생시키는 데 쓴다.
    static func darken(_ hex: String, _ k: Double) -> String {
        guard let c = rgb(hex) else { return hex }
        return String(format: "#%02x%02x%02x",
                      Int(Double(c.0) * k), Int(Double(c.1) * k), Int(Double(c.2) * k))
    }

    static func blend(_ a: String, _ b: String, _ t: Double) -> String {
        guard let ca = rgb(a), let cb = rgb(b) else { return a }
        let k = min(max(t, 0), 1)
        let r = Int((Double(ca.0) + (Double(cb.0) - Double(ca.0)) * k).rounded())
        let gg = Int((Double(ca.1) + (Double(cb.1) - Double(ca.1)) * k).rounded())
        let bb = Int((Double(ca.2) + (Double(cb.2) - Double(ca.2)) * k).rounded())
        return String(format: "#%02x%02x%02x", r, gg, bb)
    }

    static func rgb(_ hex: String) -> (Int, Int, Int)? {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        return ((v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff)
    }
}

// MARK: 생성됨 — verify/gen_motifs.py (손으로 고치지 말 것)

/// 꽃이 붙는 자리의 크기. 스탬프를 고른다.
enum BloomSize: Sendable {
    case bud, small, big, fruit
}

/// 꽃이 붙는 자리 — 원본 실루엣의 꽃 덩이 무게중심에서 뽑았다.
struct BloomAnchor: Sendable {
    let row: Int
    let col: Int
    let size: BloomSize
}

/// 한 모티프의 스탬프 세 장. `big` 7×5, `small` 5×3, `fruit` 3×2.
struct BloomArt: Sendable {
    let big: [String]
    let small: [String]
    let fruit: [String]
}

/// 꽃·열매 모티프.
///
/// 종마다 실루엣 10장을 손으로 그리면 150장이 된다. 그래서 **잎은 공용**으로 두고
/// 꽃만 갈아끼운다 — 사람이 보는 건 결국 꽃이고, 잎 덩이는 종이 달라도 비슷하다.
/// 꽃이 없는 종(상추·몬스테라·대나무)은 잎 특징을 모티프 자리에 넣어 구분한다.
enum BloomMotif: String, Codable, Sendable, CaseIterable {
    case trumpet, daisy, sun, rosette, cup, bell, spike, cluster, star, berry, needle, aurora, ruffle, split, node

    /// `.` = 밑의 잎을 그대로 둔다   `_` = 구멍을 뚫는다   나머지 = 칠한다
    var art: BloomArt {
        switch self {
        case .trumpet:
            return BloomArt(
                big: [".FFFFF.",
                      "FFFFFFF",
                      "FFFWFFF",
                      "..FWF..",
                      "...Y..."],
                small: [".FFF.",
                        "FFWFF",
                        ".FYF."],
                fruit: ["WOO",
                        "OOO"])
        case .daisy:
            return BloomArt(
                big: ["..F.F..",
                      ".FFFFF.",
                      "FFFYFFF",
                      ".FFFFF.",
                      "..F.F.."],
                small: [".F.F.",
                        "FFYFF",
                        ".F.F."],
                fruit: ["WWW",
                        "WWW"])
        case .sun:
            return BloomArt(
                big: [".FFFFF.",
                      "FFTTTFF",
                      "FTTTTTF",
                      "FFTTTFF",
                      ".FFFFF."],
                small: [".FFF.",
                        "FTTTF",
                        ".FFF."],
                fruit: ["WTT",
                        "TTT"])
        case .rosette:
            return BloomArt(
                big: [".FFFFF.",
                      "FFfFfFF",
                      "FfFFFfF",
                      "FFfFfFF",
                      ".FFFFF."],
                small: [".FFF.",
                        "FfFfF",
                        ".FFF."],
                fruit: ["WRR",
                        "RRR"])
        case .cup:
            return BloomArt(
                big: ["FF.F.FF",
                      "FFFFFFF",
                      "FFFFFFF",
                      ".FFFFF.",
                      "..FFF.."],
                small: ["F.F.F",
                        "FFFFF",
                        ".FFF."],
                fruit: ["Wyy",
                        "yyy"])
        case .bell:
            return BloomArt(
                big: ["...F...",
                      "..FFF..",
                      ".FFFFF.",
                      ".FFFFF.",
                      "..FWF.."],
                small: ["..F..",
                        ".FFF.",
                        ".FWF."],
                fruit: ["WOO",
                        "OOO"])
        case .spike:
            return BloomArt(
                big: ["..FFF..",
                      "..FFF..",
                      ".FFFFF.",
                      "..FFF..",
                      "...F..."],
                small: [".FFF.",
                        ".FFF.",
                        "..F.."],
                fruit: ["Wyy",
                        "yyy"])
        case .cluster:
            return BloomArt(
                big: [".FF.FF.",
                      "FFFFFFF",
                      ".FWFWF.",
                      "FFFFFFF",
                      ".FF.FF."],
                small: ["FF.FF",
                        ".FWF.",
                        "FF.FF"],
                fruit: ["WRR",
                        "RRR"])
        case .star:
            return BloomArt(
                big: ["...F...",
                      ".FFFFF.",
                      "FFFFFFF",
                      ".FF.FF.",
                      ".F...F."],
                small: [".F.F.",
                        "FFFFF",
                        "..F.."],
                fruit: ["WOO",
                        "OOO"])
        case .berry:
            return BloomArt(
                big: ["...G...",
                      "..RRR..",
                      ".RRRRR.",
                      ".RRRRR.",
                      "..RRR.."],
                small: ["..G..",
                        ".RRR.",
                        ".RRR."],
                fruit: ["WRR",
                        "RRR"])
        case .needle:
            return BloomArt(
                big: ["..WFW..",
                      ".FFFFF.",
                      "WFFYFFW",
                      ".FFFFF.",
                      "..WFW.."],
                small: [".WFW.",
                        "FFYFF",
                        ".WFW."],
                fruit: ["WFF",
                        "FFF"])
        case .aurora:
            return BloomArt(
                big: [".WFWFW.",
                      "FWFFFWF",
                      "WFFYFFW",
                      "FWFFFWF",
                      ".WFWFW."],
                small: [".WFW.",
                        "WFYFW",
                        ".WFW."],
                fruit: ["WWW",
                        "WWW"])
        case .ruffle:
            return BloomArt(
                big: [".LLLLL.",
                      "LGLGLGL",
                      "LLGLGLL",
                      "LGLGLGL",
                      ".LLLLL."],
                small: [".LLL.",
                        "LGLGL",
                        ".LLL."],
                fruit: ["Wyy",
                        "yyy"])
        case .split:
            return BloomArt(
                big: [".GdLdG.",
                      "GddLddG",
                      "dddLddd",
                      "GddLddG",
                      ".GdLdG."],
                small: [".dLd.",
                        "ddLdd",
                        ".dLd."],
                fruit: ["WOO",
                        "OOO"])
        case .node:
            return BloomArt(
                big: [".L...L.",
                      "..LLL..",
                      ".LLLLL.",
                      "..LLL..",
                      ".L...L."],
                small: ["LL.LL",
                        ".LLL.",
                        "..L.."],
                fruit: ["yyy",
                        "yyy"])
        }
    }
}

/// 꽃봉오리는 종을 안 가린다 — 실제로도 봉오리는 다 비슷하게 생겼다.
/// 꽃잎색만 한 픽셀 비쳐서 "뭐가 필지" 짐작만 되게 한다.
enum BloomBud {
    static let art: [String] = [".F.",
        "GFG",
        ".G."]
}

/// 단계별 꽃 자리. Lv.1~5 는 비어 있다 — 실제로도 그 시기엔 꽃이 없다.
enum BloomLayout {
    static let anchors: [[BloomAnchor]] = [
        [],                                  // Lv.1 씨앗
        [],                                  // Lv.2 발아
        [],                                  // Lv.3 떡잎
        [],                                  // Lv.4 어린잎
        [],                                  // Lv.5 자란 줄기
        // Lv.6 꽃봉오리
        [.init(row: 2, col: 11, size: .bud)],
        // Lv.7 첫 꽃
        [.init(row: 3, col: 11, size: .big)],
        // Lv.8 만개
        [.init(row: 3, col: 11, size: .big), .init(row: 2, col: 3, size: .small), .init(row: 2, col: 19, size: .small)],
        // Lv.9 열매
        [.init(row: 2, col: 11, size: .big), .init(row: 2, col: 3, size: .small), .init(row: 2, col: 19, size: .small), .init(row: 6, col: 3, size: .fruit), .init(row: 6, col: 19, size: .fruit), .init(row: 9, col: 11, size: .fruit)],
        // Lv.10 거목
        [.init(row: 3, col: 7, size: .small), .init(row: 3, col: 16, size: .small), .init(row: 6, col: 11, size: .small)],
    ]
}

/// 정원에 심긴 그루의 꽃 자리(16x16).
///
/// 이식하고 나면 꽃이 사라지는 게 제일 이상했다 — 다 키워서 정원에 옮겼더니
/// 초록 덩이만 늘어서, 30그루를 모아도 보상이 "나무밭"이었다.
/// 화분과 같은 모티프를 작게(5x3) 얹어 이식한 뒤에도 그 종의 꽃이 계속 핀다.
///
/// 앵커는 잎 덩이 **안쪽**이어야 한다. 가장자리에 걸치면 꽃이 허공에 뜬 것처럼 보인다.
enum GardenBloomLayout {
    static func anchors(_ shape: PlantShape) -> [(row: Int, col: Int)] {
        switch shape {
        case .round: return [(row: 2, col: 5), (row: 3, col: 10), (row: 5, col: 7)]
        case .tall: return [(row: 4, col: 7), (row: 6, col: 8)]
        case .low: return [(row: 4, col: 5), (row: 5, col: 10)]
        }
    }
}

// MARK: 생성 끝
