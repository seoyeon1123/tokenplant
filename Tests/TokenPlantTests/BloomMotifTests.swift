import XCTest
@testable import TokenPlant

// MARK: 꽃 모티프 — 종이 **형태로** 구분되는가
//
// 이 파일이 지키는 것은 하나다: 종을 바꾸면 화분 그림이 실제로 달라진다.
// 오래 이게 안 지켜졌다 — `PotSprites.grid(stageIndex:)` 가 종을 인자로 받지 않아서
// 15종이 전부 같은 실루엣에 잎 색만 달랐다. 색만 다른 걸 "다양하다"고 할 수 없다.

final class BloomMotifTests: XCTestCase {

    /// 스탬프 치수. 이게 어긋나면 앵커 중심이 밀려 꽃이 잎 밖에 붙는다.
    func testStampDimensions() {
        for motif in BloomMotif.allCases {
            let art = motif.art
            XCTAssertEqual(art.big.count, 5, "\(motif.rawValue).big 이 5줄이 아니다")
            XCTAssertEqual(art.small.count, 3, "\(motif.rawValue).small 이 3줄이 아니다")
            XCTAssertEqual(art.fruit.count, 2, "\(motif.rawValue).fruit 이 2줄이 아니다")
            for row in art.big {
                XCTAssertEqual(row.count, 7, "\(motif.rawValue).big 줄이 7칸이 아니다")
            }
            for row in art.small {
                XCTAssertEqual(row.count, 5, "\(motif.rawValue).small 줄이 5칸이 아니다")
            }
            for row in art.fruit {
                XCTAssertEqual(row.count, 3, "\(motif.rawValue).fruit 줄이 3칸이 아니다")
            }
        }
    }

    /// 합성 결과는 항상 24×24 여야 한다. 스탬프가 넘쳐 줄이 늘어나면 렌더가 깨진다.
    func testComposedGridIsAlwaysSquare() {
        for motif in BloomMotif.allCases {
            for stage in 0..<PlantBalance.stageCount {
                let grid = PotSprites.grid(stageIndex: stage, motif: motif)
                XCTAssertEqual(grid.count, PotSprites.size,
                               "\(motif.rawValue) Lv.\(stage + 1) 줄 수가 24가 아니다")
                for row in grid {
                    XCTAssertEqual(row.count, PotSprites.size,
                                   "\(motif.rawValue) Lv.\(stage + 1) 칸 수가 24가 아니다")
                }
            }
        }
    }

    /// 범위를 벗어난 단계도 잘라서 그린다 — 손상된 세이브에서 렌더마다 크래시하면 앱을 못 연다.
    func testOutOfRangeStageIsClamped() {
        let low = PotSprites.grid(stageIndex: -5, motif: .daisy)
        let high = PotSprites.grid(stageIndex: 999, motif: .daisy)
        XCTAssertEqual(low.count, PotSprites.size)
        XCTAssertEqual(high.count, PotSprites.size)
        XCTAssertEqual(high, PotSprites.grid(stageIndex: PlantBalance.stageCount - 1, motif: .daisy))
    }

    /// **핵심.** 만개(Lv.8)에서 모티프가 다르면 그림이 달라야 한다.
    /// 여기가 통과하지 않으면 종을 몇 개로 늘려도 "같은 그림 N가지 색"이다.
    func testEveryMotifLooksDifferentAtFullBloom() {
        let bloomStage = 7          // Lv.8 만개
        var seen: [String: BloomMotif] = [:]
        for motif in BloomMotif.allCases {
            let grid = PotSprites.grid(stageIndex: bloomStage, motif: motif)
            let key = grid.map { String($0) }.joined()
            if let twin = seen[key] {
                XCTFail("\(motif.rawValue) 와 \(twin.rawValue) 가 만개에서 똑같이 생겼다")
            }
            seen[key] = motif
        }
        XCTAssertEqual(seen.count, BloomMotif.allCases.count)
    }

    /// 거목(Lv.10)도 갈려야 한다. 사이클의 끝이고 제일 오래 보는 그림이라
    /// 여기가 전부 같으면 앞 단계를 아무리 갈라도 "결국 같은 나무"로 남는다.
    func testEveryMotifLooksDifferentAtTheFinalStage() {
        var seen: [String: BloomMotif] = [:]
        for motif in BloomMotif.allCases {
            let grid = PotSprites.grid(stageIndex: PlantBalance.stageCount - 1, motif: motif)
            let key = grid.map { String($0) }.joined()
            if let twin = seen[key] {
                XCTFail("\(motif.rawValue) 와 \(twin.rawValue) 가 거목에서 똑같이 생겼다")
            }
            seen[key] = motif
        }
    }

    /// 반대로 초반 다섯 단계는 **일부러** 같다. 씨앗은 실제로도 다 비슷하게 생겼고,
    /// 여기서부터 갈라면 종당 실루엣 10장을 손으로 그려야 한다(15종 = 150장).
    /// 이건 타협이므로 테스트로 못 박아 둔다 — 나중에 누가 "왜 똑같지?" 하고 고치려 들 때
    /// 의도였다는 걸 알 수 있게.
    func testEarlyStagesAreDeliberatelyShared() {
        for stage in 0..<5 {
            let reference = PotSprites.grid(stageIndex: stage, motif: .daisy)
            for motif in BloomMotif.allCases {
                XCTAssertEqual(PotSprites.grid(stageIndex: stage, motif: motif), reference,
                               "Lv.\(stage + 1) 은 공용이어야 한다 (\(motif.rawValue))")
            }
        }
    }

    /// 꽃은 Lv.6 부터 나온다. 그 전에 앵커가 있으면 씨앗에 꽃이 핀다.
    func testNoBloomBeforeBudStage() {
        for stage in 0..<5 {
            XCTAssertTrue(BloomLayout.anchors[stage].isEmpty,
                          "Lv.\(stage + 1) 에 꽃 자리가 있다")
        }
        XCTAssertFalse(BloomLayout.anchors[5].isEmpty, "꽃봉오리 단계에 꽃 자리가 없다")
    }

    /// 앵커 수가 단계 수와 맞아야 한다 — 어긋나면 마지막 단계에서 인덱스 초과로 크래시한다.
    func testAnchorTableMatchesStageCount() {
        XCTAssertEqual(BloomLayout.anchors.count, PlantBalance.stageCount)
        XCTAssertEqual(PotSprites.stages.count, PlantBalance.stageCount)
    }

    /// 15종 전부 모티프가 있고, 서로 충분히 갈린다.
    /// 같은 모티프를 쓰는 종이 있어도 팔레트가 다르면 되지만, 절반이 한 모티프면 안 된다.
    func testSpeciesMotifsAreSpreadOut() {
        var count: [BloomMotif: Int] = [:]
        for sp in PlantSpecies.catalog {
            count[sp.motif, default: 0] += 1
        }
        XCTAssertEqual(count.values.reduce(0, +), PlantSpecies.catalog.count)
        let worst = count.values.max() ?? 0
        XCTAssertLessThanOrEqual(worst, 3,
                                 "한 모티프에 종이 \(worst)개 몰렸다 — 그만큼 똑같아 보인다")
    }

    /// 잎만 남기기: 꽃 문자가 하나도 안 남아야 한다. 남으면 종 꽃잎색이 아닌
    /// 고정색 꽃이 스탬프 밑에 비쳐 나온다.
    func testFoliageStripsEveryBloomCharacter() {
        for stage in PotSprites.stages {
            let leaves = PotSprites.foliage(stage.silhouette).joined()
            for ch in leaves {
                XCTAssertFalse(PotSprites.bloomChars.contains(ch),
                               "\(stage.name) 에 꽃 문자 \(ch) 가 남았다")
            }
        }
    }

    /// 겹꽃 그림자는 종 꽃잎색에서 파생돼야 한다 — 팔레트에 고정색으로 두면
    /// 어떤 종이든 장미색 그림자가 생긴다.
    func testLayeredPetalShadeFollowsTheSpecies() {
        let rose = PlantSpecies.byID("rose")!
        let tulip = PlantSpecies.byID("tulip")!
        let a = PlantSpriteBuilder.color("f", species: rose, wilt: 0)
        let b = PlantSpriteBuilder.color("f", species: tulip, wilt: 0)
        XCTAssertNotNil(a)
        XCTAssertNotEqual(a, b, "겹꽃 그림자가 종과 무관하게 같은 색이다")
        // 꽃잎보다 어두워야 그림자로 읽힌다.
        let petal = PlantSpriteBuilder.rgb(rose.petal!)!
        let shade = PlantSpriteBuilder.rgb(a!)!
        XCTAssertLessThan(shade.0, petal.0)
        XCTAssertLessThan(shade.1, petal.1)
    }
}

// MARK: 정원 개화 — 이식하고 나서도 꽃이 핀다
//
// 이식하면 꽃이 사라지는 게 제일 이상했다. 다 키워서 정원에 옮겼더니 초록 덩이만 늘어서,
// 서른 그루를 모아도 보상이 "나무밭"이었다. 모으는 게 목적인 화면에서 그건 치명적이다.

final class GardenBloomTests: XCTestCase {

    func testGardenGridIsAlwaysSquare() {
        for shape in PlantShape.allCases {
            for motif in BloomMotif.allCases {
                let grid = GardenSprites.grid(shape, motif: motif)
                XCTAssertEqual(grid.count, GardenSprites.size,
                               "\(shape.rawValue)/\(motif.rawValue) 줄 수가 16이 아니다")
                for row in grid {
                    XCTAssertEqual(row.count, GardenSprites.size,
                                   "\(shape.rawValue)/\(motif.rawValue) 칸 수가 16이 아니다")
                }
            }
        }
    }

    /// 모든 모양에 꽃 자리가 있어야 한다. 하나라도 비면 그 모양을 쓰는 종은
    /// 이식하는 순간 꽃을 잃는다.
    func testEveryShapeHasBloomAnchors() {
        for shape in PlantShape.allCases {
            XCTAssertFalse(GardenBloomLayout.anchors(shape).isEmpty,
                           "\(shape.rawValue) 에 꽃 자리가 없다")
        }
    }

    /// 꽃은 **잎 안쪽**에 찍혀야 한다. 가장자리에 걸치면 허공에 뜬 것처럼 보인다.
    func testBloomsLandInsideTheFoliage() {
        for shape in PlantShape.allCases {
            let base = GardenSprites.shapes[shape] ?? []
            for motif in BloomMotif.allCases {
                let art = motif.art.small
                let h = art.count, w = art.first?.count ?? 0
                for anchor in GardenBloomLayout.anchors(shape) {
                    for (y, line) in art.enumerated() {
                        for (x, ch) in line.enumerated() where ch != "." && ch != "_" {
                            let gy = anchor.row - h / 2 + y
                            let gx = anchor.col - w / 2 + x
                            guard gy >= 0, gy < base.count else {
                                return XCTFail("\(shape.rawValue) 꽃이 격자를 벗어난다")
                            }
                            let row = Array(base[gy])
                            XCTAssertTrue(gx >= 0 && gx < row.count && row[gx] != ".",
                                          "\(shape.rawValue)/\(motif.rawValue) 꽃이 잎 밖(\(gy),\(gx))에 찍힌다")
                        }
                    }
                }
            }
        }
    }

    /// 정원에서도 종이 갈려야 한다. 여기가 전부 같으면 이식한 보람이 없다.
    func testGardenSpritesDifferByMotif() {
        for shape in PlantShape.allCases {
            var seen: [String: BloomMotif] = [:]
            for motif in BloomMotif.allCases {
                let key = GardenSprites.grid(shape, motif: motif).map { String($0) }.joined()
                if let twin = seen[key] {
                    XCTFail("\(shape.rawValue): \(motif.rawValue) 와 \(twin.rawValue) 가 똑같다")
                }
                seen[key] = motif
            }
        }
    }

    /// 꽃을 달아도 원래 잎이 절반은 남아야 한다 — 다 덮으면 꽃만 둥둥 뜬다.
    ///
    /// 전체 픽셀 대비로 재면 안 된다. 줄기·흙·외곽선이 분모에 섞여서 기준이 흔들린다
    /// (그렇게 짰다가 0.27 이 나와 테스트가 틀렸었다). **꽃을 얹기 전후의 잎 수**를
    /// 견주는 게 "삼켰다"를 직접 재는 방법이다.
    func testBloomsDoNotSwallowTheWholeCanopy() {
        // 한 줄 체인(`flatMap → filter(== "G" || …) → count`)으로 쓰면 타입 체커가
        // 시간 초과로 컴파일을 포기한다. 문자 리터럴이 체인 안에서 후보를 폭발시킨다.
        // 집합을 **미리 타입을 박아** 두고 평범한 루프로 센다.
        let leafChars: Set<Character> = ["G", "L", "d"]
        func leafCount(_ grid: [[Character]]) -> Int {
            var n = 0
            for row in grid {
                for ch in row where leafChars.contains(ch) { n += 1 }
            }
            return n
        }
        for shape in PlantShape.allCases {
            let plain = PlantSpriteBuilder.decorate(GardenSprites.shapes[shape] ?? [],
                                                    appending: [])
            let before = leafCount(plain)
            XCTAssertGreaterThan(before, 0, "\(shape.rawValue) 에 잎이 없다")
            for motif in BloomMotif.allCases {
                let after = leafCount(GardenSprites.grid(shape, motif: motif))
                XCTAssertGreaterThan(Double(after) / Double(before), 0.5,
                                     "\(shape.rawValue)/\(motif.rawValue) 가 잎을 너무 덮는다")
            }
        }
    }
}
