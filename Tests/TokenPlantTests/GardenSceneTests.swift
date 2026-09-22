import XCTest
import SwiftUI
@testable import TokenPlant

// MARK: 정원 씬 조립
//
// 뷰 자체는 눈으로만 확인되지만, 씬 **조립**은 순수 함수다(`GardenComposer.compose`
// 가 hex 격자를 돌려주고 Canvas 와 PNG 가 그걸 나눠 쓴다). 그래서 여기까진 테스트가 닿는다.
//
// 잡으려는 것: 티어를 늘렸는데 슬롯이 부족해 그루가 사라지는 것,
// 좌표가 캔버스를 벗어나 그루가 화면 밖에 그려지는 것, 배경에 구멍(nil)이 남는 것.

final class GardenSceneTests: XCTestCase {

    // MARK: 레이아웃 불변식

    /// 티어 7개와 레이아웃 7개가 1:1 이어야 한다 — 하나 어긋나면 `byKey` 가 창가로 떨어진다.
    func testEveryGardenTierHasALayout() {
        XCTAssertEqual(SceneLayout.all.count, GardenTier.all.count)
        for tier in GardenTier.all {
            let layout = SceneLayout.byKey(tier.key)
            XCTAssertEqual(layout.key, tier.key, "\(tier.name) 레이아웃이 없다 — 창가로 떨어진다")
        }
    }

    /// 티어가 선언한 캔버스와 레이아웃 크기가 같아야 한다 — 다르면 미니뷰 배율이 틀어진다.
    func testTierCanvasMatchesLayoutSize() {
        for tier in GardenTier.all {
            let layout = SceneLayout.byKey(tier.key)
            XCTAssertEqual(layout.width, tier.canvas.w, "\(tier.name) 너비")
            XCTAssertEqual(layout.height, tier.canvas.h, "\(tier.name) 높이")
        }
    }

    /// 마지막 티어가 최대 그루 수를 담아야 한다. 부족하면 이식한 그루가 조용히 사라진다.
    func testFinalTierHoldsEveryTree() {
        let forest = SceneLayout.byKey("forest")
        XCTAssertGreaterThanOrEqual(forest.slotCount, GardenTier.maxCount,
                                    "비밀의 숲 슬롯이 \(GardenTier.maxCount)그루보다 적다")
    }

    /// 각 티어는 자기 해금 조건만큼은 담아야 한다 — 온실(10그루)에 슬롯이 8개면 두 그루가 안 보인다.
    func testEachTierHoldsItsOwnRequirement() {
        for tier in GardenTier.all {
            let layout = SceneLayout.byKey(tier.key)
            // 창가·베란다는 화분 자체를 보여주는 티어라 슬롯이 need 보다 적을 수 있다.
            guard tier.need >= 3 else { continue }
            XCTAssertGreaterThanOrEqual(layout.slotCount, tier.need,
                                        "\(tier.name): 슬롯 \(layout.slotCount) < 필요 \(tier.need)")
        }
    }

    /// 슬롯 좌표가 캔버스 안에 있어야 한다. 스프라이트 폭 16을 더해도 넘치면 안 된다.
    func testSlotCoordinatesStayInsideCanvas() {
        for layout in SceneLayout.all {
            XCTAssertGreaterThan(layout.horizon, 0, "\(layout.key) 지평선")
            XCTAssertLessThan(layout.horizon, layout.height, "\(layout.key) 지평선")

            for row in layout.rows {
                XCTAssertGreaterThan(row.baseline, GardenSprites.size - 1,
                                     "\(layout.key): 기준선이 낮아 나무 위쪽이 잘린다")
                XCTAssertLessThanOrEqual(row.baseline, layout.height,
                                         "\(layout.key): 기준선이 캔버스 아래로 나갔다")
                for x in row.xs {
                    XCTAssertGreaterThanOrEqual(x, 0, "\(layout.key) x=\(x)")
                    XCTAssertLessThanOrEqual(x + GardenSprites.size, layout.width,
                                             "\(layout.key): x=\(x) 에서 나무가 오른쪽으로 넘친다")
                }
            }
        }
    }

    /// 뒷줄을 먼저 그려 앞줄이 겹친다 — rows 가 기준선 오름차순이어야 그 순서가 맞는다.
    func testRowsAreOrderedBackToFront() {
        for layout in SceneLayout.all {
            let baselines = layout.rows.map(\.baseline)
            XCTAssertEqual(baselines, baselines.sorted(),
                           "\(layout.key): 줄 순서가 뒤에서 앞이 아니다 — 앞나무가 뒷나무에 가린다")
        }
    }

    /// 장식 자리도 캔버스 안이어야 한다.
    func testDecorSpotsStayInsideCanvas() {
        for layout in SceneLayout.all {
            for spot in layout.decorSpots {
                XCTAssertGreaterThanOrEqual(spot.x, 0, "\(layout.key)")
                XCTAssertLessThan(spot.x, layout.width, "\(layout.key)")
                XCTAssertLessThanOrEqual(spot.y, layout.height, "\(layout.key)")
            }
        }
    }

    // MARK: 계절 팔레트

    /// 팔레트 색을 하나라도 못 읽으면 그 자리가 투명 구멍이 된다.
    func testEverySeasonColorIsReadable() {
        for p in SeasonPalette.all {
            for hex in [p.sky, p.grass, p.grass2, p.path, p.fence, p.fence2, p.water] {
                XCTAssertNotNil(PlantSpriteBuilder.rgb(hex), "\(p.name) 의 \(hex)")
            }
            XCTAssertGreaterThanOrEqual(p.extraHaze, 0)
            XCTAssertLessThan(p.extraHaze, 1)
        }
    }

    /// 밤에는 잎도 같이 어두워져야 한다 — 배경만 어둡게 하면 나무가 형광처럼 뜬다.
    func testOnlyNightAddsHaze() {
        XCTAssertGreaterThan(SeasonPalette.byKey("night").extraHaze, 0)
        XCTAssertEqual(SeasonPalette.byKey("spring").extraHaze, 0)
        XCTAssertEqual(SeasonPalette.byKey("autumn").extraHaze, 0)
    }

    func testUnknownSeasonFallsBackToSpring() {
        XCTAssertEqual(SeasonPalette.byKey("여름").key, "spring")
        XCTAssertEqual(SceneLayout.byKey("없는티어").key, "sill")
    }

    // MARK: 조립

    private func compose(_ key: String,
                         entries: Int = 0,
                         decorations: [String] = [],
                         season: String = "spring") -> [[String?]] {
        let layout = SceneLayout.byKey(key)
        let list = (0..<entries).map { i in
            GardenEntry(speciesID: PlantSpecies.catalog[i % PlantSpecies.catalog.count].id,
                        isShiny: false,
                        plantedAt: Date(timeIntervalSince1970: 0),
                        transplantedAt: Date(timeIntervalSince1970: 86_400 * 20),
                        totalWater: PlantBalance.cycleWater(dailyRaw: PlantBalance.assumedDailyRaw))
        }
        return GardenComposer.compose(layout: layout,
                                      season: SeasonPalette.byKey(season),
                                      entries: list,
                                      decorations: decorations,
                                      currentPotStage: 5,
                                      currentSpecies: PlantSpecies.catalog[0])
    }

    /// 격자 크기가 레이아웃과 정확히 같아야 한다 — 안 맞으면 Canvas 와 PNG 가 어긋난다.
    func testComposedGridMatchesLayoutSize() {
        for layout in SceneLayout.all {
            let grid = compose(layout.key, entries: layout.slotCount)
            XCTAssertEqual(grid.count, layout.height, "\(layout.key) 높이")
            for row in grid { XCTAssertEqual(row.count, layout.width, "\(layout.key) 너비") }
        }
    }

    /// 배경이 모든 칸을 덮어야 한다. nil 이 남으면 그 픽셀이 투명 구멍으로 보인다.
    func testBackgroundLeavesNoHoles() {
        for layout in SceneLayout.all {
            for season in SeasonPalette.all {
                let grid = compose(layout.key, entries: layout.slotCount, season: season.key)
                let holes = grid.reduce(0) { $0 + $1.filter { $0 == nil }.count }
                XCTAssertEqual(holes, 0, "\(layout.key)/\(season.key) 에 빈 픽셀 \(holes)개")
            }
        }
    }

    /// 모든 색이 읽히는 hex 여야 한다 — 렌더가 조용히 건너뛰면 원인을 못 찾는다.
    func testEveryComposedPixelIsAValidHex() {
        for layout in SceneLayout.all {
            let grid = compose(layout.key, entries: layout.slotCount,
                               decorations: ["bench", "feeder", "lantern"])
            for row in grid {
                for hex in row {
                    guard let hex else { continue }
                    XCTAssertNotNil(PlantSpriteBuilder.rgb(hex), "못 읽는 색 \(hex) (\(layout.key))")
                }
            }
        }
    }

    /// 그루를 더하면 화면이 실제로 달라져야 한다.
    func testAddingTreesChangesTheScene() {
        let empty = compose("forest", entries: 0)
        let one = compose("forest", entries: 1)
        let many = compose("forest", entries: 30)
        XCTAssertNotEqual(empty, one, "그루를 심었는데 화면이 그대로다")
        XCTAssertNotEqual(one, many)
    }

    /// 슬롯보다 많은 그루가 들어와도 크래시하지 않는다(티어 경계에서 실제로 생긴다).
    func testMoreEntriesThanSlotsIsSafe() {
        let layout = SceneLayout.byKey("bed")      // 슬롯 3개
        let grid = compose("bed", entries: 30)
        XCTAssertEqual(grid.count, layout.height)
        XCTAssertEqual(grid.first?.count, layout.width)
    }

    /// 장식은 길이나 연못이 있는 티어부터 놓인다 — 창가 창틀에 벤치를 놓을 자리가 없다.
    func testDecorationsAppearOnlyOnOutdoorTiers() {
        let sill = compose("sill")
        let sillWithBench = compose("sill", decorations: ["bench"])
        XCTAssertEqual(sill, sillWithBench, "창가에 장식이 놓였다")

        let yard = compose("yard", entries: 6)
        let yardWithBench = compose("yard", entries: 6, decorations: ["bench"])
        XCTAssertNotEqual(yard, yardWithBench, "뒷마당에 장식이 안 놓였다")
    }

    /// 장식 세 개가 서로 다른 자리에 놓여야 한다 — 같은 자리면 하나만 보인다.
    func testThreeDecorationsUseThreeDistinctSpots() {
        let layout = SceneLayout.byKey("forest")
        let spots = layout.decorSpots
        XCTAssertGreaterThanOrEqual(spots.count, 3)
        XCTAssertEqual(Set(spots.prefix(3).map(\.x)).count, 3, "장식 자리가 겹친다")

        let one = compose("forest", decorations: ["bench"])
        let three = compose("forest", decorations: ["bench", "feeder", "lantern"])
        XCTAssertNotEqual(one, three)
    }

    /// 알 수 없는 장식 키는 조용히 건너뛴다(세이브에 남은 옛 키).
    func testUnknownDecorationKeyIsIgnored() {
        let plain = compose("forest")
        let bogus = compose("forest", decorations: ["없는장식"])
        XCTAssertEqual(plain, bogus)
    }

    /// 창가·베란다는 지금 키우는 화분을 함께 보여준다 — 빈 씬을 내밀지 않는다.
    func testSillAndBalconyShowTheCurrentPot() {
        for key in ["sill", "balc"] {
            let layout = SceneLayout.byKey(key)
            let withPot = GardenComposer.compose(layout: layout, season: .byKey("spring"),
                                                 entries: [], decorations: [],
                                                 currentPotStage: 9,
                                                 currentSpecies: PlantSpecies.catalog[0])
            let without = GardenComposer.compose(layout: layout, season: .byKey("spring"),
                                                 entries: [], decorations: [],
                                                 currentPotStage: nil,
                                                 currentSpecies: nil)
            XCTAssertNotEqual(withPot, without, "\(key) 에 화분이 안 그려졌다")
        }
    }

    /// 계절은 배경만 갈아끼운다 — 스프라이트를 다시 그리지 않는다는 게 전제다.
    func testSeasonChangesTheScene() {
        let spring = compose("forest", entries: 10, season: "spring")
        let night = compose("forest", entries: 10, season: "night")
        XCTAssertNotEqual(spring, night)
        XCTAssertEqual(spring.count, night.count)
    }

    /// 같은 입력이면 같은 격자 — 조립이 결정적이어야 PNG 가 화면과 같다.
    func testCompositionIsDeterministic() {
        XCTAssertEqual(compose("arbor", entries: 12, decorations: ["bench"]),
                       compose("arbor", entries: 12, decorations: ["bench"]))
    }

    /// PNG 는 화면과 같은 격자를 정수배로 늘린 것이어야 한다.
    func testExportedImageSizeIsGridTimesScale() {
        let grid = compose("forest", entries: 30)
        let image = GardenComposer.image(grid, scale: 8)
        XCTAssertEqual(Int(image.size.width), (grid.first?.count ?? 0) * 8)
        XCTAssertEqual(Int(image.size.height), grid.count * 8)
    }

    // MARK: 색 변환

    func testHexParsingAcceptsValidAndRejectsGarbage() {
        XCTAssertNotNil(Color(hex: "#7fbf6a"))
        XCTAssertNotNil(PlantSpriteBuilder.rgb("#000000"))
        XCTAssertEqual(PlantSpriteBuilder.rgb("#ffffff")?.0, 255)
        XCTAssertNil(PlantSpriteBuilder.rgb("초록색"))
        XCTAssertNil(PlantSpriteBuilder.rgb("#12345"))
        XCTAssertNil(Color(hex: ""))
    }

    /// 뒷줄은 하늘색으로 흐려져 깊이가 생긴다 — 픽셀 스프라이트는 크기를 못 줄이니 이게 유일한 수단이다.
    func testBlendMovesTowardTheTargetColor() throws {
        let mixed = PlantSpriteBuilder.blend("#000000", "#ffffff", 0.5)
        let rgb = try XCTUnwrap(PlantSpriteBuilder.rgb(mixed))
        XCTAssertTrue((120...135).contains(rgb.0), "절반 섞었는데 \(rgb.0)")
        XCTAssertEqual(PlantSpriteBuilder.blend("#123456", "#ffffff", 0), "#123456")
        XCTAssertEqual(PlantSpriteBuilder.blend("#123456", "#ffffff", 1), "#ffffff")
        // 비율을 벗어나도 잘라야 한다 — haze 계산이 음수가 될 여지가 있다.
        XCTAssertEqual(PlantSpriteBuilder.blend("#123456", "#ffffff", -3), "#123456")
        XCTAssertEqual(PlantSpriteBuilder.blend("#123456", "#ffffff", 9), "#ffffff")
    }

    // MARK: 정원 상한 — **이식을 막지 않는다**

    /// 정원이 꽉 차면 예전엔 `transplant` 가 `false` 를 돌려주고 끝이었다.
    /// 화분은 완주 상태로 영원히 대기하고, 그 뒤로 아무 일도 일어나지 않는다.
    /// 사이클이 9일이던 시점엔 9개월이면 그 벽에 닿았다.
    ///
    /// 자리가 없는 건 **화면 문제**고, 그걸로 게임을 멈추는 건 순서가 거꾸로다.
    func testGardenNeverBlocksTransplant() {
        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato", cycleWater: PlantBalance.legacyCycleWater)

        let over = GardenTier.maxCount + 5
        for n in 1...over {
            PlantEngine.credit(&s, raw: 0, water: s.pot!.cycleWater, today: "2026-09-01")
            XCTAssertTrue(PlantEngine.transplant(&s, roll: UInt64(n)),
                          "\(s.garden.count)그루에서 이식이 막혔다")
        }
        XCTAssertEqual(s.garden.count, over, "만렙 이후 기록이 안 쌓였다")
        XCTAssertNotNil(s.pot, "새 씨앗이 안 심겼다")
        XCTAssertEqual(s.pot?.water, 0)
    }

    /// 자리보다 그루가 많으면 **최근 것**을 그린다. 앞에서 자르면 오래된 30그루가
    /// 영원히 박혀서, 그 뒤에 심은 건 정원에 한 번도 안 나타난다.
    func testSceneShowsTheNewestEntriesWhenItOverflows() {
        let layout = SceneLayout.byKey("forest")
        let slots = layout.slotCount

        func entry(_ id: String) -> GardenEntry {
            GardenEntry(speciesID: id, isShiny: false,
                        plantedAt: Date(timeIntervalSince1970: 0),
                        transplantedAt: Date(timeIntervalSince1970: 86_400 * 20),
                        totalWater: 1)
        }
        // 자리를 토마토로 다 채우고, 넘치는 자리에 단풍(잎 색이 확 다르다)을 놓는다.
        var entries = Array(repeating: entry("tomato"), count: slots)
        entries.append(contentsOf: Array(repeating: entry("maple"), count: 3))

        let grid = GardenComposer.compose(layout: layout,
                                          season: SeasonPalette.byKey("spring"),
                                          entries: entries, decorations: [],
                                          currentPotStage: nil, currentSpecies: nil)
        let painted = Set(grid.flatMap { $0 }.compactMap { $0 })
        guard let maple = PlantSpecies.byID("maple"),
              let tomato = PlantSpecies.byID("tomato") else { return XCTFail("카탈로그가 비었다") }

        // 두 종의 잎 색이 같으면 이 검증이 아무것도 안 본다.
        let mapleHues: Set<String> = [maple.leaf, maple.leafLight, maple.leafShade]
        let tomatoHues: Set<String> = [tomato.leaf, tomato.leafLight, tomato.leafShade]
        XCTAssertTrue(mapleHues.isDisjoint(with: tomatoHues), "두 종의 잎 색이 겹쳐 구분이 안 된다")

        // 넘친 그루는 마지막 자리 = 앞줄에 놓인다. 앞줄은 haze 가 0 이라 색이 그대로 남는다
        // (봄 팔레트의 `extraHaze` 도 0). 그래서 원래 hex 로 찾을 수 있다.
        XCTAssertFalse(mapleHues.isDisjoint(with: painted),
                       "넘친 자리에 놓은 최근 그루가 정원에 안 나온다")
    }

    // MARK: 장식이 **언제부터** 보이나

    /// 모든 티어에서 그려져야 한다.
    ///
    /// 예전엔 뒷마당(6그루)부터만 그렸다. 장식이 셋뿐이고 전부 직접 사는 것이었을 때는
    /// 그래도 됐는데, 뽑기가 생기면서 깨졌다: 이틀째에 뽑아서 "정원에 놓았어요"라고
    /// 띄우는데 실제로 보이는 건 6그루를 채운 석 달 뒤다.
    func testDecorationsShowOnEveryTier() {
        for layout in SceneLayout.all {
            let bare = compose(layout.key)
            let with = compose(layout.key, decorations: ["bench"])
            XCTAssertNotEqual(bare, with, "\(layout.key) 에서 장식이 안 그려진다")
        }
    }

    /// 열두 개를 다 모았을 때 마지막 두 티어에서 전부 그려져야 한다.
    /// 자리를 좌표로 박아뒀을 때는 넷째부터 조용히 안 그려졌다(`i < decorSpots.count` 에서 잘린다).
    func testEveryDecorationFitsInTheLastTiers() {
        for key in ["arbor", "forest"] {
            let layout = SceneLayout.byKey(key)
            XCTAssertGreaterThanOrEqual(layout.decorSpots.count, DecorIcons.allKeys.count,
                                        "\(key) 장식 자리 \(layout.decorSpots.count)개 < 12")
            // 자리가 캔버스를 벗어나면 그 장식은 잘려 나간다.
            for (n, spot) in layout.decorSpots.enumerated() {
                XCTAssertLessThanOrEqual(spot.x + DecorIcons.size, layout.width,
                                         "\(key) \(n + 1)번째 자리가 오른쪽으로 넘친다")
                XCTAssertLessThanOrEqual(spot.y, layout.height, "\(key) \(n + 1)번째 자리가 아래로 넘친다")
            }
        }
    }

    // MARK: 장식 자리 — 끌어서 옮기기

    /// 옮겨둔 자리는 **그리기·클릭·끌기가 같은 함수**에서 나와야 한다.
    /// 정원 나무에서 그리는 창과 클릭 판정이 갈려 엉뚱한 명패가 뜬 적이 있어서,
    /// 장식은 처음부터 `decorPlacements` 한 곳으로 모았다.
    func testMovedDecorationUsesTheStoredSpot() {
        let layout = SceneLayout.byKey("forest")
        let keys = ["bench", "cat", "mushroom"]
        let moved = layout.decorPlacements(keys, positions: ["cat": [40, 90]])

        guard let cat = moved.first(where: { $0.key == "cat" }) else { return XCTFail("고양이가 없다") }
        XCTAssertEqual(cat.spot.x, 40)
        XCTAssertEqual(cat.spot.y, 90)
        // 옮긴 장식은 기본 자리를 안 먹는다 — 그래야 남은 장식이 앞으로 당겨진다.
        let others = moved.filter { $0.key != "cat" }.map(\.spot.x)
        XCTAssertEqual(others, Array(layout.decorSpots.prefix(2)).map(\.x))
    }

    /// 옮긴 자리가 실제로 **격자에 그려져야** 한다. 저장만 되고 안 그려지면 옮긴 게 아니다.
    func testMovedDecorationActuallyMovesInTheGrid() {
        let layout = SceneLayout.byKey("forest")
        func gridWith(_ positions: [String: [Int]]) -> [[String?]] {
            GardenComposer.compose(layout: layout, season: SeasonPalette.byKey("spring"),
                                   entries: [], decorations: ["mushroom"],
                                   currentPotStage: nil, currentSpecies: nil,
                                   positions: positions)
        }
        let a = gridWith([:])
        let b = gridWith(["mushroom": [layout.width - DecorIcons.size, layout.height]])
        XCTAssertNotEqual(a, b, "자리를 옮겼는데 격자가 그대로다")
    }

    /// 끌고 있는 장식은 격자에서 빠져야 한다 — 안 그러면 원본과 유령이 겹쳐 보인다.
    func testDraggedDecorationIsHiddenFromTheGrid() {
        let layout = SceneLayout.byKey("forest")
        let shown = GardenComposer.compose(layout: layout, season: SeasonPalette.byKey("spring"),
                                           entries: [], decorations: ["mushroom"],
                                           currentPotStage: nil, currentSpecies: nil)
        let hidden = GardenComposer.compose(layout: layout, season: SeasonPalette.byKey("spring"),
                                            entries: [], decorations: ["mushroom"],
                                            currentPotStage: nil, currentSpecies: nil,
                                            hiding: "mushroom")
        XCTAssertNotEqual(shown, hidden, "끌고 있는 장식이 격자에 남았다")
        // 숨긴 쪽은 장식이 하나도 없는 정원과 같아야 한다.
        let none = GardenComposer.compose(layout: layout, season: SeasonPalette.byKey("spring"),
                                          entries: [], decorations: [],
                                          currentPotStage: nil, currentSpecies: nil)
        XCTAssertEqual(hidden, none)
    }
}
