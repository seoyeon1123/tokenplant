import Foundation

// 16×16 아이콘 — 상점 품목 · 정원 장식 · 메뉴바 전용 단계 스프라이트.
//
// 식물 팔레트와 색이 겹치지 않게 별도 팔레트를 쓴다(금속·유리·마대 같은 건 잎 색으로 못 그린다).
// 16px 에서는 디테일이 안 읽히므로 실루엣만 명확하게 잡았다.

enum IconPalette {
    static let base: [Character: String] = [
        "K": "#2b2016",
        "W": "#ffffff",
        "M": "#9aafba",
        "m": "#6d8391",
        "B": "#6fb3d9",
        "b": "#4a90b8",
        "S": "#c9a86b",
        "s": "#9e8047",
        "V": "#cfe8f0",
        "L": "#86d06a",
        "G": "#5ec489",
        "g": "#2d8a6d",
        "Y": "#f5c542",
        "y": "#c2a02f",
        "O": "#b08355",
        "R": "#e0503f",
        "F": "#f2748c",
        "P": "#c9724f",
        "q": "#e5926b",
        "D": "#5b4232",
        "N": "#3a3a44",
        "w": "#a3764a",
        "x": "#7a5636",
        "E": "#b9b4a8",
        "e": "#8d887c",
        "T": "#7a5436",
        "t": "#5c3d26",
    ]

    static func color(_ ch: Character) -> String? { base[ch] }
}

/// 상점 품목 아이콘. 이모지 폴백을 대체한다 — 이모지는 시스템 폰트에 따라 모양이 바뀌고
/// 픽셀 스프라이트 옆에 두면 톤이 안 맞는다.
enum ItemIcons {
    static let size = 16

    static let art: [String: [String]] = [
        "fertilizer": [
            "................",
            "....KKKKKKK.....",
            "...KSSSSSSSK....",
            "...KSsSSSsSK....",
            "..KSSSSSSSSSK...",
            "..KSSsSSSsSSK...",
            "..KSSSSSSSSSK...",
            "..KSsSSSSSsSK...",
            "..KSSSSSSSSSK...",
            "..KKKKKKKKKKK...",
            "...DD.D..DD.....",
            "..D..DD.D..D....",
            "...D.D...DD.....",
            "................",
            "................",
            "................",
        ],
        // 물 — 물방울 하나. 제일 자주 쓰는 칸이라 실루엣이 한눈에 읽혀야 한다.
        "water": [
            "................",
            ".......KK.......",
            ".......KK.......",
            "......KVBK......",
            "......KVBK......",
            ".....KVBBBK.....",
            ".....KVBBBK.....",
            "....KVBBBBBK....",
            "....KVBBBBBK....",
            "....KVBBBBbK....",
            "....KVBBBbbK....",
            ".....KBBBbK.....",
            ".....KKbbKK.....",
            "......KKKK......",
            "................",
            "................",
        ],
        // 영양제 — 약병. 흙자루 그림은 이름과 안 맞아서 갈아끼웠다.
        "nutrient": [
            "................",
            "......KKKK......",
            "......KWWK......",
            "......KWWK......",
            ".....KKWWKK.....",
            ".....KVVVVK.....",
            "....KVGGGGVK....",
            "....KVGGGGVK....",
            "....KGGGGGGK....",
            "....KGGGGGGK....",
            "....KgGGGGgK....",
            "....KggGGggK....",
            "....KgggggGK....",
            ".....KKKKKK.....",
            "................",
            "................",
        ],
        "premiumSeed": [
            "................",
            "...KKKKKKKKK....",
            "...KSSSSSSSK....",
            "...KSSSSSSSK....",
            "...KS.OOO.SK....",
            "...KSOOOOOSK....",
            "...KS.OOO.SK....",
            "...KSSSSSSSK....",
            "...KSsssssSK....",
            "...KSSSSSSSK....",
            "...KKKKKKKKK....",
            "................",
            "................",
            "................",
            "................",
            "................",
        ],
        "legendarySeed": [
            ".......Y........",
            "...KKKKKKKKK.Y..",
            ".Y.KYYYYYYYK....",
            "...KYYKKKYYK....",
            "...KYKOOOKYK....",
            ".Y.KYKOOOKYK.Y..",
            "...KYKOOOKYK....",
            "...KYYKKKYYK....",
            "...KYYYYYYYK....",
            ".Y.KYYYYYYYK....",
            "...KKKKKKKKK.Y..",
            "......Y.........",
            "................",
            "................",
            "................",
            "................",
        ],
        "shinyCharm": [
            "................",
            ".......KK.......",
            "......KYYK......",
            ".....KYYYYK.....",
            "....KYYYYYYK....",
            "...KYYVVVVYYK...",
            "...KYVVWWVVYK...",
            "...KYVVWWVVYK...",
            "...KYYVVVVYYK...",
            "....KYYYYYYK....",
            ".....KYYYYK.....",
            "......KYYK......",
            ".......KK.......",
            "................",
            "................",
            "................",
        ],
        "decorBox": [
            "................",
            "................",
            "......KK........",
            ".....KRRK.KK....",
            "....KRRRRKRRK...",
            "....KKRRKRRKK...",
            "..KKKKKRRKKKKK..",
            "..KYYYKRRKYYYK..",
            "..KKKKKRRKKKKK..",
            "..KYYYKRRKYYYK..",
            "..KYYYKRRKYYYK..",
            "..KYYYKRRKYYYK..",
            "..KKKKKRRKKKKK..",
            "................",
            "................",
            "................",
        ],
        "potSlot": [
            "................",
            ".........G......",
            "........GGG.....",
            ".........g......",
            "......KKDDDKK...",
            "......KqqqqqK...",
            "..G...KPPPPPK...",
            ".GGG..KPPPPK....",
            "..g...KKKKK.....",
            ".KKDDDKK........",
            ".KqqqqqK........",
            ".KPPPPPK........",
            ".KPPPPK.........",
            ".KKKKK..........",
            "................",
            "................",
        ],
    ]

    static func grid(_ item: ShopItem) -> [[Character]]? {
        guard let rows = art[item.rawValue] else { return nil }
        return rows.map { Array($0) }
    }
}

/// 정원 장식. 연못은 수목원 배경에 이미 절차적으로 들어간다.
///
/// 열두 개다. 셋(벤치·모이통·석등)은 상점에서 직접 사고, 아홉은 **장식 뽑기**로만 나온다.
/// 직접 살 수 있게 다 열어두면 비싼 순서대로 사는 목록이 되고, 그건 재미가 아니라 숙제다.
///
/// 실루엣을 일부러 흩었다 — 낮고 넓은 것(물받이·울타리), 높고 좁은 것(요정·바람개비),
/// 둥근 것(버섯·해시계), 각진 것(돌 등불). 16px 에서 덩어리 모양이 겹치면 구분이 안 된다.
///
/// **생성물이다.** 원본은 `verify/gen_decor.py` 고, 거기서 콘택트 시트를 뽑아 보고 고친다.
/// 직접 고치면 다음 `--write` 에 날아간다.
enum DecorIcons {
    static let size = 16

    /// 상점에서 직접 사는 장식.
    static let shopKeys = ["bench", "feeder", "lantern"]

    /// 뽑기로만 나오는 장식.
    static let gachaKeys = ["birdbath", "gnome", "windmill", "mailbox", "steppingstones", "fence", "mushroom", "arch", "cat"]

    static var allKeys: [String] { shopKeys + gachaKeys }

    static let names: [String: String] = [
        "bench": "벤치",
        "feeder": "새 모이통",
        "lantern": "석등",
        "birdbath": "새 물받이",
        "gnome": "정원 요정",
        "windmill": "바람개비",
        "mailbox": "우편함",
        "steppingstones": "디딤돌",
        "fence": "울타리",
        "mushroom": "버섯",
        "arch": "덩굴 아치",
        "cat": "고양이",
    ]

    static func name(_ key: String) -> String { names[key] ?? key }

    static let art: [String: [String]] = [
        "bench": [
            "................",
            "................",
            "................",
            "................",
            "..KKKKKKKKKKKK..",
            "..KwwwwwwwwwwK..",
            "..KxxxxxxxxxxK..",
            "..KKKKKKKKKKKK..",
            "..KwwwwwwwwwwK..",
            "..KxxxxxxxxxxK..",
            "..KKKKKKKKKKKK..",
            "...K.K....K.K...",
            "...K.K....K.K...",
            "...KKK....KKK...",
            "................",
            "................",
        ],
        "feeder": [
            "................",
            ".......K........",
            ".......K........",
            "....KKKKKKK.....",
            "...KwwwwwwwK....",
            "...KxxxxxxxK....",
            "...KKKKKKKKK....",
            "....KwwwwwK.....",
            "....KOOOOOK.....",
            "....KKKKKKK.....",
            ".......K........",
            ".......K........",
            ".......K........",
            "......KKK.......",
            "................",
            "................",
        ],
        "lantern": [
            "................",
            ".....KKKKK......",
            "....KEEEEEK.....",
            "....KKKKKKK.....",
            "...KEEEEEEEK....",
            "...KEYYYYYEK....",
            "...KEYWWWYEK....",
            "...KEYYYYYEK....",
            "...KEEEEEEEK....",
            "....KKKKKKK.....",
            ".....KEEEK......",
            ".....KEEEK......",
            "....KEEEEEK.....",
            "....KKKKKKK.....",
            "................",
            "................",
        ],
        "birdbath": [
            "................",
            "................",
            "................",
            "...KKKKKKKKKK...",
            "..KEBBBBBBBBEK..",
            "..KEBVBBBBVBEK..",
            "..KEEBBBBBBEEK..",
            "...KEEEEEEEEK...",
            ".....KEEEEK.....",
            "......KEEK......",
            "......KEEK......",
            ".....KEEEEK.....",
            "....KEEEEEEK....",
            "....KKKKKKKK....",
            "................",
            "................",
        ],
        "gnome": [
            "................",
            ".......K........",
            "......KRK.......",
            "......KRK.......",
            ".....KRRRK......",
            ".....KRRRK......",
            "....KRRRRRK.....",
            "....KKKKKKK.....",
            "....KqqWqqK.....",
            "....KqWWWqK.....",
            "....KKKWKKK.....",
            "...KBBBBBBBK....",
            "...KBBBBBBBK....",
            "...KKKKKKKKK....",
            "................",
            "................",
        ],
        "windmill": [
            ".......K........",
            "...KK..K..KK....",
            "..KWWK.K.KWWK...",
            "..KWWWKKKWWWK...",
            "...KWWWKWWWK....",
            "....KKKKKKK.....",
            "...KWWWKWWWK....",
            "..KWWWKKKWWWK...",
            "..KWWK.K.KWWK...",
            "...KK..K..KK....",
            ".......K........",
            "......KwwK......",
            "......KwwK......",
            ".....KxxxxK.....",
            ".....KKKKKK.....",
            "................",
        ],
        "mailbox": [
            "................",
            "................",
            "....KKKKKKK.....",
            "...KRRRRRRRK....",
            "...KRWWWWWRK....",
            "...KRRRRRRRK....",
            "...KRRRRRRRK....",
            "...KKKKKKKKK....",
            "......KwK.......",
            "......KwK.......",
            "......KwK.......",
            "......KxK.......",
            ".....KxxxK......",
            ".....KKKKK......",
            "................",
            "................",
        ],
        "steppingstones": [
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "......KKKK......",
            ".....KEEEEK.....",
            ".....KEeeEK.....",
            "......KKKK......",
            ".KKKK......KKKK.",
            "KEEEEK....KEEEEK",
            "KEeeEK....KEeeEK",
            ".KKKK......KKKK.",
            "................",
            "................",
        ],
        "fence": [
            "................",
            "................",
            "................",
            "................",
            "..K..K..K..K..K.",
            "..KwwKwwKwwKwwK.",
            "..KKKKKKKKKKKKK.",
            "..KwwKwwKwwKwwK.",
            "..KwwKwwKwwKwwK.",
            "..KKKKKKKKKKKKK.",
            "..KxxKxxKxxKxxK.",
            "..KxxKxxKxxKxxK.",
            "..K..K..K..K..K.",
            "..K..K..K..K..K.",
            "................",
            "................",
        ],
        "mushroom": [
            "................",
            "................",
            "................",
            ".....KKKKK......",
            "...KKRRRRRKK....",
            "..KRRWRRRWRRK...",
            "..KRRRRWRRRRK...",
            "..KRWRRRRRWRK...",
            "..KKRRRRRRRKK...",
            "....KKWWWKK.....",
            "......KWK.......",
            "......KWK.......",
            ".....KWWWK......",
            ".....KKKKK......",
            "................",
            "................",
        ],
        "arch": [
            "....KKKKKKKK....",
            "...KLLwwwwLLK...",
            "..KLwwKKKKwwLK..",
            "..KwwK....KwwK..",
            "..KLwK....KwLK..",
            "..KwwK....KwwK..",
            "..KLwK....KwLK..",
            "..KwwK....KwwK..",
            "..KLwK....KwLK..",
            "..KwwK....KwwK..",
            "..KwwK....KwwK..",
            "..KxxK....KxxK..",
            "..KKKK....KKKK..",
            "................",
            "................",
            "................",
        ],
        "cat": [
            "................",
            "................",
            "...KK.....KK....",
            "..KyyK...KyyK...",
            "..KyyyKKKyyyK...",
            "..KyyyyyyyyyK...",
            "..KyKyyyyyKyK...",
            "..KyyyyKyyyyK...",
            "...KyyyyyyyK....",
            "....KyyyyyK.....",
            "....KyyyyyK...K.",
            "....KyyyyyK..KyK",
            "....KyyyyyKKKyK.",
            "....KyyyyyyyyK..",
            ".....KKKKKKK....",
            "................",
        ],
    ]

    static func grid(_ key: String) -> [[Character]]? {
        guard let rows = art[key] else { return nil }
        return rows.map { Array($0) }
    }

    /// 움직이는 장식의 **1번 프레임부터**. 0번은 `art` 에 이미 있다.
    ///
    /// 바람개비는 0°/45° 두 장이면 한 바퀴가 돈다 — 날개가 넷이라 90°마다 같은 그림이다.
    /// 고양이는 꼬리만 움직인다. 16px 에서 몸을 건드리면 덩어리가 흔들려 지저분해진다.
    static let frames: [String: [[String]]] = [
        "windmill": [
            [
                ".....KWWWK......",
                ".....KWWWK......",
                ".....KWWWK......",
                ".KKKKKKKKKKKKK..",
                ".KWWWKKKKKWWWK..",
                ".KWWWKKKKKWWWK..",
                ".KWWWKKKKKWWWK..",
                ".KKKKKKKKKKKKK..",
                ".....KWWWK......",
                ".....KWWWK......",
                ".....KWWWK......",
                "......KwwK......",
                "......KwwK......",
                ".....KxxxxK.....",
                ".....KKKKKK.....",
                "................",
            ],
        ],
        "cat": [
            [
                "................",
                "................",
                "...KK.....KK....",
                "..KyyK...KyyK...",
                "..KyyyKKKyyyK...",
                "..KyyyyyyyyyK...",
                "..KyKyyyyyKyK...",
                "..KyyyyKyyyyK...",
                "...KyyyyyyyK....",
                "....KyyyyyK..K..",
                "....KyyyyyK.KyK.",
                "....KyyyyyK.KyK.",
                "....KyyyyyKKyK..",
                "....KyyyyyyyK...",
                ".....KKKKKKK....",
                "................",
            ],
            [
                "................",
                "................",
                "...KK.....KK....",
                "..KyyK...KyyK...",
                "..KyyyKKKyyyK...",
                "..KyyyyyyyyyK...",
                "..KKKyyyyyKKK...",
                "..KyyyyKyyyyK...",
                "...KyyyyyyyK....",
                "....KyyyyyK..K..",
                "....KyyyyyK.KyK.",
                "....KyyyyyK.KyK.",
                "....KyyyyyKKyK..",
                "....KyyyyyyyK...",
                ".....KKKKKKK....",
                "................",
            ],
        ],
        "birdbath": [
            [
                "................",
                "................",
                "................",
                "...KKKKKKKKKK...",
                "..KEBBVBBBBBEK..",
                "..KEBBBVBBBVEK..",
                "..KEEBBBBBBEEK..",
                "...KEEEEEEEEK...",
                ".....KEEEEK.....",
                "......KEEK......",
                "......KEEK......",
                ".....KEEEEK.....",
                "....KEEEEEEK....",
                "....KKKKKKKK....",
                "................",
                "................",
            ],
            [
                "................",
                "................",
                "................",
                "...KKKKKKKKKK...",
                "..KEBBBBVBBBEK..",
                "..KEVBBBBBBVEK..",
                "..KEEBBBBBBEEK..",
                "...KEEEEEEEEK...",
                ".....KEEEEK.....",
                "......KEEK......",
                "......KEEK......",
                ".....KEEEEK.....",
                "....KEEEEEEK....",
                "....KKKKKKKK....",
                "................",
                "................",
            ],
        ],
    ]

    /// 0번 포함 전체 장수. 움직이지 않는 장식은 1이다.
    static func frameCount(_ key: String) -> Int {
        (frames[key]?.count ?? 0) + 1
    }

    /// `frame` 은 아무 수나 와도 된다 — 장수로 나눠 돌린다.
    static func grid(_ key: String, frame: Int) -> [[Character]]? {
        guard let zero = art[key] else { return nil }
        let extra = frames[key] ?? []
        guard !extra.isEmpty else { return zero.map { Array($0) } }
        let i = ((frame % (extra.count + 1)) + extra.count + 1) % (extra.count + 1)
        let rows = i == 0 ? zero : extra[i - 1]
        return rows.map { Array($0) }
    }
}

/// 새. **장식이 아니다** — 상점에도 뽑기에도 없고, 모이통이나 물받이를 놓아두면 찾아온다.
///
/// 그래서 `DecorIcons` 와 따로 둔다. 소유물 목록에 섞이면 도감에 빈 칸이 생긴다.
/// 세 장이다 — 앉음 · 날갯짓 · 쪼기. 옆모습에서 날개를 세우면 토끼 귀로 읽혀서,
/// 날갯짓은 두 칸 떠오른 자세로 대신한다. 그 장을 폴짝 뛰는 데도 같이 쓴다.
///
/// **생성물이다.** 원본은 `verify/gen_decor.py`.
enum BirdIcon {
    static let size = 16

    static let art: [[String]] = [
        [
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "......KKKK......",
            ".....KqqqqK.KK..",
            ".....KqKqqKKYK..",
            "....KqqqqqqKK...",
            "..KKqqxxxqqK....",
            ".KqqqqxxxqqK....",
            "..KKqqqqqqK.....",
            "......K..K......",
            "................",
        ],
        [
            "................",
            "................",
            "................",
            "................",
            "................",
            "......KKKK......",
            ".....KqqqqK.KK..",
            ".....KqKqqKKYK..",
            "....KqqqqqqKK...",
            "..KKqxxxxqqK....",
            ".KqqqxxxxqqK....",
            "..KKqqqqqqK.....",
            "................",
            "................",
            "................",
            "................",
        ],
        [
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "..KK............",
            ".KqqK...........",
            ".KqqqKKKK.......",
            "..KqqqqqqqK.....",
            "..KqqxxxqqqK....",
            "...KqqqqqqqK....",
            "....KKqqqqK.....",
            ".....KqqK.......",
            "......KYK.......",
        ],
    ]

    /// 자세 번호. 순서대로 돌리는 게 아니라 **골라 쓴다** —
    /// 날아오는 중엔 `flying`, 내려앉으면 `perched`, 가끔 `pecking`.
    static let perched = 0
    static let flying = 1
    static let pecking = 2

    static var frameCount: Int { art.count }

    static func grid(frame: Int) -> [[Character]] {
        let i = ((frame % art.count) + art.count) % art.count
        return art[i].map { Array($0) }
    }
}

enum MenuBarSprites {
    static let size = 16
    static let plantRows = 11

    /// 모든 단계가 공유하는 화분(5줄).
    static let pot: [String] = [
        "..KKDDDDDDDDKK..",
        "..KqqqqqqqqqqK..",
        "..KPPPPPPPPPpK..",
        "...KPPPPPPPPpK..",
        "....KKKKKKKK....",
    ]

    static let plants: [[String]] = [
        [   // Lv.1
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "......OOO.......",
        ],
        [   // Lv.2
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "......LGG.......",
            ".......g........",
            ".......g........",
        ],
        [   // Lv.3
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
            "....GGG.GGG.....",
            ".....GG.GG......",
            "......GgG.......",
            ".......g........",
            ".......g........",
        ],
        [   // Lv.4
            "................",
            "................",
            "................",
            "................",
            "....GGG.GGG.....",
            ".....GG.GG......",
            "......GgG.......",
            "....GG.g.GG.....",
            ".....G.g.G......",
            ".......g........",
            ".......g........",
        ],
        [   // Lv.5
            "................",
            "................",
            ".......GG.......",
            "......GGGG......",
            "....GGG.GGG.....",
            ".....GG.GG......",
            "...GG..g..GG....",
            "....GG.g.GG.....",
            ".....G.g.G......",
            ".......g........",
            ".......g........",
        ],
        [   // Lv.6
            ".......F........",
            "......FFF.......",
            ".......g........",
            "....GGG.GGG.....",
            ".....GG.GG......",
            "...GG..g..GG....",
            "....GG.g.GG.....",
            ".....G.g.G......",
            ".......g........",
            ".......g........",
            ".......g........",
        ],
        [   // Lv.7
            ".....FFFFF......",
            "....FFYYYFF.....",
            ".....FFFFF......",
            ".......g........",
            "....GGG.GGG.....",
            ".....GG.GG......",
            "...GG..g..GG....",
            "....GG.g.GG.....",
            ".....G.g.G......",
            ".......g........",
            ".......g........",
        ],
        [   // Lv.8
            "..FF.FFFFF.FF...",
            ".FFFFFYYYFFFFF..",
            "..FF..FFF..FF...",
            "...g...g...g....",
            "....GGG.GGG.....",
            "...GG..g..GG....",
            "....GG.g.GG.....",
            ".....G.g.G......",
            ".......g........",
            ".......g........",
            ".......g........",
        ],
        [   // Lv.9
            "..FF.FFFFF.FF...",
            ".FFFFFYYYFFFFF..",
            "..FF..FFF..FF...",
            "...g...g...g....",
            "..RR.GGGGG.RR...",
            "..RR..g.g..RR...",
            "....GG.g.GG.....",
            ".....RRRRR......",
            ".....G.g.G......",
            ".......g........",
            ".......g........",
        ],
        [   // Lv.10
            "...GGGGGGGGGG...",
            "..GGGGGRGGGGGG..",
            ".GGGGGGGGGGGGGG.",
            ".GGGRGGGGGGRGGG.",
            "..GGGGGGGGGGGG..",
            "...GGGGTTGGGG...",
            ".....GGTTGG.....",
            ".......TT.......",
            ".......TT.......",
            "......TTTT......",
            ".....TTTTTT.....",
        ],
    ]

    /// 아웃라인·음영까지 입힌 16×16 그리드. 식물 팔레트를 그대로 쓴다(잎 색이 종을 따라간다).
    static func grid(stageIndex idx: Int) -> [[Character]] {
        let i = min(max(0, idx), plants.count - 1)
        return PlantSpriteBuilder.decorate(plants[i], appending: pot)
    }
}
