import XCTest
@testable import TokenPlant

// MARK: 스프라이트 데이터 무결성
//
// 픽셀맵은 손으로 적는 문자열이라 한 줄만 길이가 틀려도 렌더에서 인덱스가 밀린다.
// 컴파일은 통과하고 화면만 깨지는 종류의 버그라 테스트가 유일한 방어선이다.

final class PlantSpritesTests: XCTestCase {

    func testEveryPotStageIsExactly24x24() {
        XCTAssertEqual(PotSprites.stages.count, PlantBalance.stageCount,
                       "스프라이트 단계 수와 임계값 단계 수가 다르다")
        for stage in PotSprites.stages {
            XCTAssertEqual(stage.silhouette.count, PotSprites.plantRows,
                           "Lv.\(stage.level) \(stage.name): 실루엣 줄 수")
            for (y, row) in stage.silhouette.enumerated() {
                XCTAssertEqual(row.count, PotSprites.size,
                               "Lv.\(stage.level) \(stage.name) \(y)번째 줄 길이")
            }
        }
        XCTAssertEqual(PotSprites.pot.count, PotSprites.size - PotSprites.plantRows)
        for row in PotSprites.pot { XCTAssertEqual(row.count, PotSprites.size) }
    }

    func testDecoratedGridIsSquare() {
        for i in 0..<PotSprites.stages.count {
            let g = PotSprites.grid(stageIndex: i, motif: .daisy)
            XCTAssertEqual(g.count, PotSprites.size, "단계 \(i) 높이")
            for row in g { XCTAssertEqual(row.count, PotSprites.size, "단계 \(i) 너비") }
        }
    }

    func testStageIndexIsClampedNotCrashing() {
        XCTAssertEqual(PotSprites.grid(stageIndex: -5, motif: .daisy).count, PotSprites.size)
        XCTAssertEqual(PotSprites.grid(stageIndex: 999, motif: .daisy).count, PotSprites.size)
    }

    func testGardenShapesAre16x16AndCoverEveryCase() {
        for shape in PlantShape.allCases {
            let rows = try? XCTUnwrap(GardenSprites.shapes[shape])
            XCTAssertNotNil(rows, "\(shape.rawValue) 실루엣이 없다")
            guard let rows else { continue }
            XCTAssertEqual(rows.count, GardenSprites.size, "\(shape.rawValue) 줄 수")
            for row in rows { XCTAssertEqual(row.count, GardenSprites.size, "\(shape.rawValue) 줄 길이") }
        }
    }

    /// 모든 문자가 팔레트에 있어야 한다 — 오타 한 글자가 투명 구멍으로 남는다.
    func testNoUnknownCharactersInAnySprite() {
        var known = Set(PlantPalette.base.keys)
        known.insert(".")
        let sample = PlantSpecies.catalog[0]

        for i in 0..<PotSprites.stages.count {
            for row in PotSprites.grid(stageIndex: i, motif: .daisy) {
                for ch in row {
                    XCTAssertTrue(known.contains(ch), "단계 \(i) 에 알 수 없는 문자 '\(ch)'")
                    if ch != "." {
                        XCTAssertNotNil(PlantSpriteBuilder.color(ch, species: sample, wilt: 0),
                                        "'\(ch)' 색을 못 찾는다")
                    }
                }
            }
        }
        for shape in PlantShape.allCases {
            for row in GardenSprites.grid(shape, motif: .daisy) {
                for ch in row { XCTAssertTrue(known.contains(ch), "\(shape.rawValue) 에 '\(ch)'") }
            }
        }
    }

    /// 씨앗은 화분만 보이고, 거목은 위쪽까지 꽉 찬다 — 단계가 실제로 자라는지.
    func testSilhouettesActuallyGrow() {
        func filled(_ i: Int) -> Int {
            PotSprites.stages[i].silhouette.reduce(0) { acc, row in
                acc + row.filter { ch in ch != "." }.count
            }
        }
        let seed = filled(0)
        let final = filled(PotSprites.stages.count - 1)
        XCTAssertLessThan(seed, 12, "씨앗이 너무 크다")
        XCTAssertGreaterThan(final, 150, "거목이 너무 작다")

        // 단조 증가까진 요구하지 않는다(꽃이 피면 잎이 줄기도 한다) —
        // 다만 뒤쪽 절반이 앞쪽 절반보다 확실히 커야 한다.
        let early = (0..<5).reduce(0) { $0 + filled($1) }
        let late = (5..<10).reduce(0) { $0 + filled($1) }
        XCTAssertGreaterThan(late, early * 2)
    }

    /// 자동 아웃라인이 실제로 테두리를 만들었는지 — 실루엣에는 K 가 하나도 없어야 한다.
    func testOutlineIsGeneratedNotHandDrawn() {
        for stage in PotSprites.stages {
            for row in stage.silhouette {
                XCTAssertFalse(row.contains("K"),
                               "Lv.\(stage.level) 실루엣에 아웃라인이 손으로 들어 있다 — decorate() 가 중복 처리한다")
            }
        }
        let decorated = PotSprites.grid(stageIndex: 9, motif: .daisy)
        let outlines = decorated.reduce(0) { acc, row in acc + row.filter { ch in ch == "K" }.count }
        XCTAssertGreaterThan(outlines, 40, "아웃라인이 거의 안 생겼다")
    }

    // MARK: 종 팔레트

    func testEverySpeciesHasReadableHexPalette() {
        for s in PlantSpecies.catalog {
            for hex in [s.leaf, s.leafLight, s.leafShade] + [s.petal].compactMap({ $0 }) {
                XCTAssertNotNil(PlantSpriteBuilder.rgb(hex), "\(s.name) 의 \(hex) 를 못 읽는다")
            }
        }
    }

    func testSpeciesIDsAreUnique() {
        let ids = PlantSpecies.catalog.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "종 id 가 중복이다")
    }

    /// 실루엣 3종 × 팔레트 — 모든 실루엣이 최소 한 종씩 쓰여야 한다.
    /// 안 쓰이는 실루엣이 있으면 30그루 정원에서 반복이 눈에 띈다.
    func testEveryShapeIsUsedBySomeSpecies() {
        for shape in PlantShape.allCases {
            XCTAssertTrue(PlantSpecies.catalog.contains { $0.shape == shape },
                          "\(shape.rawValue) 실루엣을 쓰는 종이 없다")
        }
    }

    func testEveryRarityHasAtLeastTwoSpecies() {
        for r in PlantRarity.allCases {
            XCTAssertGreaterThanOrEqual(PlantSpecies.all(r).count, 2, "\(r.rawValue) 종이 너무 적다")
        }
    }

    /// 시들면 색이 실제로 바뀌고, 회복하면 원래대로 돌아온다.
    func testWiltBlendsLeafColorAndIsReversible() {
        let s = PlantSpecies.byID("tomato")!
        let healthy = PlantSpriteBuilder.color("G", species: s, wilt: 0)
        let dying = PlantSpriteBuilder.color("G", species: s, wilt: 1)
        let half = PlantSpriteBuilder.color("G", species: s, wilt: 0.5)
        XCTAssertEqual(healthy, s.leaf)
        XCTAssertNotEqual(dying, healthy)
        XCTAssertNotEqual(half, healthy)
        XCTAssertNotEqual(half, dying)
        // 아웃라인은 시들어도 그대로 — 실루엣이 흐려지면 안 된다.
        XCTAssertEqual(PlantSpriteBuilder.color("K", species: s, wilt: 1),
                       PlantSpriteBuilder.color("K", species: s, wilt: 0))
    }
}

// MARK: 아이콘 · 메뉴바 스프라이트

final class IconSpritesTests: XCTestCase {

    /// 모든 상점 품목에 아이콘이 있어야 한다 — 하나 빼먹으면 그 줄만 이모지로 튄다.
    func testEveryShopItemHasAnIcon() {
        for item in ShopItem.allCases {
            let g = ItemIcons.grid(item) ?? DecorIcons.grid(item.rawValue)
            XCTAssertNotNil(g, "\(item.name) 아이콘이 없다")
            guard let g else { continue }
            XCTAssertEqual(g.count, ItemIcons.size, "\(item.name) 줄 수")
            for row in g { XCTAssertEqual(row.count, ItemIcons.size, "\(item.name) 줄 길이") }
        }
    }

    /// 장식 세 개는 정원에도 그려진다 — `DecorIcons` 키가 rawValue 와 맞아야 한다.
    func testDecorationKeysMatchShopRawValues() {
        for item in ShopItem.allCases where item.isDecoration {
            XCTAssertNotNil(DecorIcons.grid(item.rawValue),
                            "\(item.rawValue) 장식 아트가 없다 — 정원에 빈칸이 놓인다")
        }
        // 뽑기로만 나오는 아홉 개는 상점 품목이 아니다 — 그것까지 세야 한다.
        for key in DecorIcons.gachaKeys {
            XCTAssertNotNil(DecorIcons.grid(key), "\(key) 뽑기 장식 아트가 없다")
        }
        let owned = Set(ShopItem.allCases.filter(\.isDecoration).map(\.rawValue))
            .union(DecorIcons.gachaKeys)
        XCTAssertEqual(DecorIcons.art.count, owned.count,
                       "어디서도 안 나오는 장식 아트가 남아 있다")
        // 삭제된 품목의 아트가 남아 있으면 상점에 없는 그림을 계속 들고 다니게 된다.
        XCTAssertEqual(ItemIcons.art.count,
                       ShopItem.allCases.filter { !$0.isDecoration }.count,
                       "상점에 없는 품목 아트가 남아 있다")
    }

    /// 아이콘 팔레트에 없는 문자는 투명 구멍이 된다.
    func testNoUnknownCharactersInIcons() {
        var known = Set(IconPalette.base.keys)
        known.insert(".")
        for (name, rows) in ItemIcons.art.merging(DecorIcons.art, uniquingKeysWith: { a, _ in a }) {
            for row in rows {
                for ch in row {
                    XCTAssertTrue(known.contains(ch), "\(name) 에 알 수 없는 문자 '\(ch)'")
                }
            }
        }
    }

    /// 메뉴바는 1픽셀 = 1포인트로 딱 맞아야 흐려지지 않는다.
    func testMenuBarSpritesAre16x16() {
        XCTAssertEqual(MenuBarSprites.plants.count, PlantBalance.stageCount,
                       "메뉴바 단계 수가 임계값 단계 수와 다르다")
        XCTAssertEqual(MenuBarSprites.pot.count, MenuBarSprites.size - MenuBarSprites.plantRows)
        for row in MenuBarSprites.pot { XCTAssertEqual(row.count, MenuBarSprites.size) }

        for i in 0..<PlantBalance.stageCount {
            let g = MenuBarSprites.grid(stageIndex: i)
            XCTAssertEqual(g.count, MenuBarSprites.size, "단계 \(i) 높이")
            for row in g { XCTAssertEqual(row.count, MenuBarSprites.size, "단계 \(i) 너비") }
        }
        XCTAssertEqual(MenuBarSprites.grid(stageIndex: -3).count, MenuBarSprites.size)
        XCTAssertEqual(MenuBarSprites.grid(stageIndex: 99).count, MenuBarSprites.size)
    }

    /// 메뉴바 스프라이트도 식물 팔레트를 타므로 색을 못 찾는 문자가 없어야 한다.
    func testMenuBarSpritesResolveToColors() {
        let sample = PlantSpecies.catalog[0]
        for i in 0..<PlantBalance.stageCount {
            for row in MenuBarSprites.grid(stageIndex: i) {
                for ch in row where ch != "." {
                    XCTAssertNotNil(PlantSpriteBuilder.color(ch, species: sample, wilt: 0),
                                    "단계 \(i) 의 '\(ch)' 색을 못 찾는다")
                }
            }
        }
    }

    /// 메뉴바도 단계가 실제로 자라야 한다 — 24px 판과 별개 아트라 따로 검사한다.
    func testMenuBarSilhouettesGrow() {
        func filled(_ i: Int) -> Int {
            MenuBarSprites.plants[i].reduce(0) { $0 + $1.filter { ch in ch != "." }.count }
        }
        XCTAssertLessThan(filled(0), 8, "씨앗이 너무 크다")
        XCTAssertGreaterThan(filled(PlantBalance.stageCount - 1), 60, "거목이 너무 작다")
        let early = (0..<5).reduce(0) { $0 + filled($1) }
        let late = (5..<10).reduce(0) { $0 + filled($1) }
        XCTAssertGreaterThan(late, early * 2)
    }

    /// 아웃라인은 `decorate()` 가 만든다 — 손으로 K 를 넣으면 이중 처리된다.
    func testMenuBarOutlineIsGenerated() {
        for (i, rows) in MenuBarSprites.plants.enumerated() {
            for row in rows {
                XCTAssertFalse(row.contains("K"), "메뉴바 단계 \(i) 실루엣에 아웃라인이 손으로 들어 있다")
            }
        }
        let outlines = MenuBarSprites.grid(stageIndex: 9)
            .reduce(0) { $0 + $1.filter { ch in ch == "K" }.count }
        XCTAssertGreaterThan(outlines, 20, "메뉴바 아웃라인이 거의 안 생겼다")
    }
}
