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
    /// 여기 `testDecorationsAppearOnlyOnOutdoorTiers`("창가엔 안 놓인다")가 나란히 남아 있었다.
    /// 정면으로 모순되는 두 테스트가 한 파일에 있었던 셈인데, 맥에서 빌드를 안 돌리는 동안
    /// 아무도 몰랐다. 새 규칙이 이긴다 — **뽑기로 받은 건 받은 자리에서 보여야 한다.**
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

    // ── 움직이는 정원 ────────────────────────────────────────────
    //
    // 오버레이를 얹지 않고 **격자째 다시 조립한다.** 그래서 애니메이션이 제대로 도는지는
    // 조립 결과를 프레임별로 비교하면 그대로 드러난다 — 뷰를 띄울 필요가 없다.

    /// 프레임 번호는 아무 수나 와도 된다. 계속 올라가는 카운터를 그대로 받으므로
    /// 음수·오버플로 근처에서 인덱스가 터지면 창이 죽는다.
    func testFrameIndexWrapsForAnyNumber() {
        for key in DecorIcons.allKeys {
            let n = DecorIcons.frameCount(key)
            XCTAssertGreaterThanOrEqual(n, 1, "\(key) 장수가 0이다")
            for f in [-9_999, -3, -1, 0, 1, 7, 10_000, Int.max, Int.min] {
                XCTAssertNotNil(DecorIcons.grid(key, frame: f), "\(key) frame \(f) 에서 nil")
            }
        }
        for f in [-9_999, -1, 0, 3, Int.max, Int.min] {
            XCTAssertEqual(BirdIcon.grid(frame: f).count, BirdIcon.size)
        }
    }

    /// 0번은 `art` 와 같아야 한다. 갈리면 정지 상태의 장식이 상점 아이콘과 달라 보인다.
    func testFrameZeroIsTheStillSprite() {
        for key in DecorIcons.allKeys {
            XCTAssertEqual(DecorIcons.grid(key, frame: 0), DecorIcons.grid(key),
                           "\(key) 0번 프레임이 정지 그림과 다르다")
            XCTAssertEqual(DecorIcons.grid(key, frame: DecorIcons.frameCount(key)),
                           DecorIcons.grid(key), "\(key) 한 바퀴 돌면 0번으로 돌아와야 한다")
        }
    }

    /// **프레임이 실제로 달라야** 움직인다. 같은 그림을 두 장 넣어두면
    /// 타이머는 도는데 화면은 멈춰 있고, 아무 검사도 그걸 못 잡는다.
    func testAnimatedDecorationsActuallyChange() {
        for key in DecorIcons.allKeys where DecorIcons.frameCount(key) > 1 {
            let zero = DecorIcons.grid(key, frame: 0)
            var moved = false
            for f in 1..<DecorIcons.frameCount(key) where DecorIcons.grid(key, frame: f) != zero {
                moved = true
            }
            XCTAssertTrue(moved, "\(key) 는 프레임이 여러 장인데 전부 같은 그림이다")
        }
        // 세 자세가 서로 달라야 한다. 같은 그림을 넣어두면 날아와도 티가 안 난다.
        let poses = [BirdIcon.perched, BirdIcon.flying, BirdIcon.pecking]
        XCTAssertEqual(Set(poses).count, 3)
        for a in poses {
            for b in poses where a < b {
                XCTAssertNotEqual(BirdIcon.grid(frame: a), BirdIcon.grid(frame: b),
                                  "새 자세 \(a) 와 \(b) 가 같은 그림이다")
            }
        }
    }

    /// 새는 **모이통이나 물받이가 있어야** 온다. 손님이지 소유물이 아니다.
    func testBirdNeedsAFeederOrBirdbath() {
        let layout = SceneLayout.byKey("forest")
        XCTAssertNil(layout.birdPerch([], positions: [:], day: 0))
        XCTAssertNil(layout.birdPerch(["bench", "mushroom", "cat"], positions: [:], day: 0))
        XCTAssertNotNil(layout.birdPerch(["feeder"], positions: [:], day: 0))
        XCTAssertNotNil(layout.birdPerch(["birdbath"], positions: [:], day: 0))
        // 새는 소유물 목록에 없어야 한다 — 있으면 도감에 영영 안 채워지는 칸이 생긴다.
        XCTAssertFalse(DecorIcons.allKeys.contains("bird"))
    }

    /// 끌고 있는 모이통에는 앉지 않는다. 유령만 따라오고 새는 남아서 허공에 뜬다.
    func testBirdLeavesWithTheDraggedFeeder() {
        let layout = SceneLayout.byKey("forest")
        XCTAssertNil(layout.birdPerch(["feeder"], positions: [:], day: 0, hiding: "feeder"))
        XCTAssertNotNil(layout.birdPerch(["feeder", "birdbath"], positions: [:],
                                         day: 0, hiding: "feeder"))
    }

    /// 날마다 자리가 바뀐다. 붙박이면 장식이 하나 더 늘어난 것과 같다.
    /// 그리고 **어느 날이든 캔버스 안에** 있어야 한다 — 밖으로 나가면 새가 통째로 사라진다.
    func testBirdMovesDayToDayAndStaysOnCanvas() {
        for key in ["sill", "yard", "forest"] {
            let layout = SceneLayout.byKey(key)
            var seen = Set<String>()
            for day in 0..<40 {
                guard let p = layout.birdPerch(["feeder", "birdbath"],
                                               positions: [:], day: day) else {
                    return XCTFail("\(key): 모이통이 있는데 새가 안 온다")
                }
                XCTAssertGreaterThanOrEqual(p.x, 0, "\(key) \(day)일: 왼쪽으로 나갔다")
                XCTAssertLessThanOrEqual(p.x + BirdIcon.size, layout.width,
                                         "\(key) \(day)일: 오른쪽으로 나갔다")
                seen.insert("\(p.x),\(p.y)")
            }
            XCTAssertGreaterThan(seen.count, 2, "\(key): 새가 늘 같은 자리에 앉는다")
        }
    }

    /// 새가 **다른 장식 위에 올라타면 안 된다.** 장식 자리 간격이 18px 라서
    /// "모이통에서 10~14px 옆" 규칙이 정확히 옆 장식 위에 새를 얹었다 —
    /// 베란다(88px)에서 새가 바람개비 날개에 박혔다.
    func testBirdDoesNotSitOnAnotherDecoration() {
        for key in ["balc", "bed", "yard", "forest"] {
            let layout = SceneLayout.byKey(key)
            let decor = ["feeder", "windmill", "cat"]
            let places = layout.decorPlacements(decor, positions: [:])
            guard let feeder = places.first(where: { $0.key == "feeder" })?.spot.x else {
                return XCTFail("\(key): 모이통이 안 놓였다")
            }
            // 새 잉크는 제 칸의 1~12번을 쓴다. 옆 장식 잉크와 실제로 닿는지를 본다 —
            // 16px 상자끼리 비교하면 여백만 닿아도 겹쳤다고 나온다.
            let birdLo = 1, birdHi = 12
            for day in 0..<40 {
                guard let p = layout.birdPerch(decor, positions: [:], day: day) else {
                    return XCTFail("\(key): 모이통이 있는데 새가 안 온다")
                }
                for other in places where other.key != "feeder" {
                    guard let art = DecorIcons.grid(other.key) else { continue }
                    // 연쇄식으로 쓰면 타입 체커가 포기한다(이 저장소에서 이미 한 번 겪었다).
                    var lo = DecorIcons.size, hi = -1
                    for row in art {
                        for (c, ch) in row.enumerated() where ch != "." {
                            if c < lo { lo = c }
                            if c > hi { hi = c }
                        }
                    }
                    guard hi >= lo else { continue }
                    XCTAssertFalse(p.x + birdLo <= other.spot.x + hi
                                   && other.spot.x + lo <= p.x + birdHi,
                                   "\(key) \(day)일: 새(\(p.x))가 \(other.key)(\(other.spot.x)) 와 겹쳤다")
                }
                // 그리고 **모이통에서 멀면 안 된다.** 빈칸을 찾아 보냈더니 정원 반대편까지 갔다.
                XCTAssertLessThanOrEqual(abs(p.x - feeder), 3,
                                         "\(key) \(day)일: 새가 모이통에서 \(abs(p.x - feeder))px 떨어졌다")
            }
        }
    }

    /// **장식이 그루보다 앞에 있다.** 장식은 앞쪽 바닥에 서고 앞줄 그루의 기준선은
    /// 그보다 위다. 한동안 그루를 나중에 그려서 앞줄 나무가 고양이를 덮었다.
    func testDecorationsDrawInFrontOfTrees() {
        let layout = SceneLayout.byKey("yard")
        // 앞줄 그루 자리(24)와 겹치는 자리에 장식을 놓는다.
        let spot = [21, layout.height - 2]
        let full = (0..<layout.slotCount).map { i in
            GardenEntry(speciesID: PlantSpecies.catalog[i % PlantSpecies.catalog.count].id,
                        plantedAt: Date(timeIntervalSince1970: 0),
                        totalWater: 1_000)
        }
        func grid(_ decor: [String]) -> [[String?]] {
            GardenComposer.compose(layout: layout, season: SeasonPalette.byKey("spring"),
                                   entries: full, decorations: decor,
                                   currentPotStage: nil, currentSpecies: nil,
                                   positions: decor.isEmpty ? [:] : ["cat": spot])
        }
        let bare = grid([])
        let withCat = grid(["cat"])
        XCTAssertNotEqual(bare, withCat, "장식을 놓았는데 격자가 그대로다")

        // 고양이 픽셀이 **거의 다** 살아 있어야 한다. 나무가 나중에 그려지면 윗부분이 먹힌다.
        guard let art = DecorIcons.grid("cat") else { return XCTFail("고양이 아트가 없다") }
        var kept = 0, total = 0
        for (gy, row) in art.enumerated() {
            for (gx, ch) in row.enumerated() where ch != "." {
                let x = spot[0] + gx, y = spot[1] + gy - DecorIcons.size
                guard y >= 0, y < layout.height, x >= 0, x < layout.width else { continue }
                total += 1
                if withCat[y][x] == IconPalette.color(ch) { kept += 1 }
            }
        }
        XCTAssertEqual(kept, total, "고양이 \(total - kept)칸이 나무에 덮였다 — 깊이가 뒤집혔다")
    }

    /// 그루가 자리보다 적어도 장식은 그려져야 한다. 그루 루프가 중간에 `return` 하면
    /// **대부분의 정원에서** 장식이 통째로 사라진다.
    func testDecorationsSurviveAHalfEmptyGarden() {
        let layout = SceneLayout.byKey("forest")
        let one = [GardenEntry(speciesID: PlantSpecies.catalog[0].id,
                               plantedAt: Date(timeIntervalSince1970: 0), totalWater: 1_000)]
        func grid(_ decor: [String]) -> [[String?]] {
            GardenComposer.compose(layout: layout, season: SeasonPalette.byKey("spring"),
                                   entries: one, decorations: decor,
                                   currentPotStage: nil, currentSpecies: nil)
        }
        XCTAssertNotEqual(grid([]), grid(["mushroom"]),
                          "그루 한 개짜리 정원에서 장식이 안 그려진다")
    }

    // ── 날아와 앉기 ──────────────────────────────────────────────
    //
    // "모이통을 옮기면 새가 순간이동한다"가 원래 모습이었다. 자리를 바꾼 순간부터
    // 몇 프레임에 걸쳐 날아와 내려앉게 했고, 그 규칙은 순수 함수라 여기서 다 볼 수 있다.

    private var spot: BirdSpot { BirdSpot(x: 30, y: 46) }

    /// 첫 등장은 **화면 밖에서** 들어온다. 정원을 열자마자 새가 박혀 있으면 손님이 아니다.
    func testFirstArrivalComesFromOffScreen() {
        let first = BirdFlight.pose(to: spot, from: nil, elapsed: 0, width: 104)
        XCTAssertEqual(first.art, BirdIcon.flying, "날아오는 중인데 앉은 자세다")
        XCTAssertTrue(first.x < 0 || first.x + BirdIcon.size > 104,
                      "화면 안(\(first.x))에서 갑자기 나타났다")
        XCTAssertLessThan(first.y, spot.y, "땅을 기어서 온다")
    }

    /// 착지하면 정확히 목표 자리에 선다. 1px 어긋나면 내려앉는 순간 튄다.
    func testLandingEndsExactlyOnTheSpot() {
        for elapsed in BirdFlight.landing...(BirdFlight.landing + BirdFlight.idleCycle * 2) {
            let p = BirdFlight.pose(to: spot, from: nil, elapsed: elapsed, width: 104)
            XCTAssertEqual(p.x, spot.x, "\(elapsed)프레임: x 가 어긋났다")
            XCTAssertEqual(p.y, spot.y, "\(elapsed)프레임: y 가 어긋났다")
        }
    }

    /// 날아오는 동안 **실제로 움직여야** 한다. 값이 같으면 그냥 기다렸다 나타나는 것이다.
    func testFlightActuallyMoves() {
        let from = BirdSpot(x: 3, y: 46)
        let to = BirdSpot(x: 75, y: 46)
        var xs: [Int] = []
        for e in 0..<BirdFlight.landing {
            xs.append(BirdFlight.pose(to: to, from: from, elapsed: e, width: 104).x)
        }
        XCTAssertGreaterThan(Set(xs).count, 3, "날아오는 동안 자리가 안 바뀐다: \(xs)")
        XCTAssertEqual(xs, xs.sorted(), "왔다 갔다 한다 — 한 방향으로 가야 한다")
        XCTAssertGreaterThanOrEqual(xs.first ?? 0, from.x)
        XCTAssertLessThanOrEqual(xs.last ?? 0, to.x)
    }

    /// **가는 쪽을 보고 날아야 한다.** 스프라이트가 오른쪽을 보고 한 장뿐이라,
    /// 왼쪽으로 갈 때 안 뒤집으면 뒷걸음질로 날아온다.
    func testBirdFacesWhereItIsGoing() {
        let left = BirdSpot(x: 3, y: 46), right = BirdSpot(x: 80, y: 46)
        for e in 0..<BirdFlight.landing {
            XCTAssertTrue(BirdFlight.pose(to: left, from: right, elapsed: e, width: 104).facingLeft,
                          "\(e)프레임: 왼쪽으로 가는데 오른쪽을 본다")
            XCTAssertFalse(BirdFlight.pose(to: right, from: left, elapsed: e, width: 104).facingLeft,
                           "\(e)프레임: 오른쪽으로 가는데 왼쪽을 본다")
        }
        // 내려앉은 뒤에도 방향을 지킨다. 착지하는 순간 고개가 홱 돌면 다른 새로 보인다.
        let landed = BirdFlight.landing + 3
        XCTAssertTrue(BirdFlight.pose(to: left, from: right, elapsed: landed, width: 104).facingLeft)
        XCTAssertFalse(BirdFlight.pose(to: right, from: left, elapsed: landed, width: 104).facingLeft)
        // 화면 밖에서 처음 들어올 때도 마찬가지 — 왼쪽 자리면 오른쪽에서 오므로 왼쪽을 본다.
        XCTAssertTrue(BirdFlight.pose(to: left, from: nil, elapsed: 0, width: 104).facingLeft)
        XCTAssertFalse(BirdFlight.pose(to: right, from: nil, elapsed: 0, width: 104).facingLeft)
    }

    /// 뒤집힌 새가 **격자에서도** 뒤집혀야 한다. 자세만 바뀌고 그리기가 그대로면 소용없다.
    func testFlippedBirdIsDrawnMirrored() {
        let layout = SceneLayout.byKey("forest")
        func grid(_ flip: Bool) -> [[String?]] {
            GardenComposer.compose(layout: layout, season: SeasonPalette.byKey("spring"),
                                   entries: [], decorations: ["feeder"],
                                   currentPotStage: nil, currentSpecies: nil,
                                   bird: BirdPose(x: 30, y: 46, art: BirdIcon.perched,
                                                  facingLeft: flip))
        }
        XCTAssertNotEqual(grid(false), grid(true), "뒤집었는데 그림이 그대로다")
    }

    /// 앉은 뒤에도 가만히만 있으면 안 된다 — 쪼고, 가끔 폴짝 뛴다.
    func testPerchedBirdPecksAndHops() {
        var seen = Set<Int>()
        for e in BirdFlight.landing..<(BirdFlight.landing + BirdFlight.idleCycle) {
            seen.insert(BirdFlight.pose(to: spot, from: nil, elapsed: e, width: 104).art)
        }
        XCTAssertTrue(seen.contains(BirdIcon.perched), "쉬는 자세가 없다")
        XCTAssertTrue(seen.contains(BirdIcon.pecking), "한 바퀴 도는 동안 한 번도 안 쫀다")
        XCTAssertTrue(seen.contains(BirdIcon.flying), "한 번도 안 뛴다")
    }

    /// 프레임 번호는 계속 올라간다. 오래 켜둬도 자세 계산이 터지면 안 된다.
    func testPoseSurvivesAnyElapsed() {
        for e in [-5, 0, 1, 999, 100_000, Int.max - 1] {
            let p = BirdFlight.pose(to: spot, from: nil, elapsed: e, width: 104)
            XCTAssertTrue([BirdIcon.perched, BirdIcon.flying, BirdIcon.pecking].contains(p.art))
        }
    }

    /// 움직일 게 없으면 타이머가 격자를 다시 조립할 이유가 없다.
    func testStillGardenReportsNoMotion() {
        let layout = SceneLayout.byKey("forest")
        XCTAssertFalse(layout.hasMotion([], positions: [:], day: 0))
        XCTAssertFalse(layout.hasMotion(["bench", "mushroom"], positions: [:], day: 0))
        XCTAssertTrue(layout.hasMotion(["windmill"], positions: [:], day: 0))
        XCTAssertTrue(layout.hasMotion(["cat"], positions: [:], day: 0))
        XCTAssertTrue(layout.hasMotion(["feeder"], positions: [:], day: 0))
    }

    /// 조립까지 와야 진짜다 — 프레임이 달라도 `compose` 가 0번만 그리면 화면은 정지다.
    func testComposeDrawsDifferentFrames() {
        let layout = SceneLayout.byKey("forest")
        func grid(_ decor: [String], _ frame: Int, _ bird: BirdPose? = nil) -> [[String?]] {
            GardenComposer.compose(layout: layout, season: SeasonPalette.byKey("spring"),
                                   entries: [], decorations: decor,
                                   currentPotStage: nil, currentSpecies: nil,
                                   frame: frame, bird: bird)
        }
        XCTAssertNotEqual(grid(["windmill"], 0), grid(["windmill"], 1), "바람개비가 안 돈다")
        XCTAssertNotEqual(grid(["cat"], 0), grid(["cat"], 1), "고양이가 안 움직인다")
        // 움직이지 않는 장식만 있으면 프레임을 올려도 그대로여야 한다.
        XCTAssertEqual(grid(["bench"], 0), grid(["bench"], 5))

        // 새가 실제로 그 자리에 **찍혀야** 한다. 자리 계산만 맞고 안 그리면 소용없다.
        guard let pose = layout.landedBird(["feeder"], positions: [:], day: 0) else {
            return XCTFail("새 자리가 없다")
        }
        XCTAssertNotEqual(grid(["feeder"], 0, pose), grid(["feeder"], 0, nil),
                          "새를 줬는데 격자가 그대로다")
        let g = grid(["feeder"], 0, pose)
        var drawn = 0
        for (gy, row) in BirdIcon.grid(frame: pose.art).enumerated() {
            for (gx, ch) in row.enumerated() where ch != "." {
                let x = pose.x + gx, y = pose.y + gy - BirdIcon.size
                guard y >= 0, y < layout.height, x >= 0, x < layout.width else { continue }
                if g[y][x] == IconPalette.color(ch) { drawn += 1 }
            }
        }
        XCTAssertGreaterThan(drawn, 20, "새가 자리는 잡았는데 격자에 안 그려졌다")
    }
}
