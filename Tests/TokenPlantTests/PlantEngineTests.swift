import XCTest
@testable import TokenPlant

// MARK: 성장 엔진 (적립 · 단계 · 시듦 · 상점 · 이식)

final class PlantEngineTests: XCTestCase {

    private func freshSave(species: String = "tomato") -> PlantSave {
        var s = PlantSave()
        s.pot = PotState(speciesID: species, plantedAt: Date(timeIntervalSince1970: 0))
        s.claimedTodayByProvider = [:]   // seed 완료 상태로 시작
        return s
    }

    private let day1 = "2026-09-01"
    private let day2 = "2026-09-02"

    // MARK: 적립 (토큰 → 물통)
    //
    // `ingest` 는 **두 곳을 동시에** 채운다: 화분(가중 환산 mL)과 지갑(원시 토큰).
    // 여기서는 중복 적립·날짜 넘김·첫 설치 상한만 본다.
    // 두 물길이 서로 안 뺏는다는 불변식은 `TwoStreamsTests` 가 지킨다.

    /// 같은 스냅샷이 여러 번 들어와도 두 번 세지 않는다 —
    /// UsageStore 는 refresh 마다 '오늘 누적'을 통째로 넘기기 때문이다.
    func testIngestIsIdempotentForSameSnapshot() {
        var s = freshSave()
        let snap = ["claude": TokenDelta(input: 1_000, output: 100_000, cacheWrite: 400_000, cacheRead: 20_000_000)]
        PlantEngine.ingest(&s, todayByProvider: snap, today: day1)
        let first = s.rawWallet
        let grown = s.pot!.water
        XCTAssertGreaterThan(first, 0)
        XCTAssertGreaterThan(grown, 0, "토큰을 썼는데 안 자랐다")

        PlantEngine.ingest(&s, todayByProvider: snap, today: day1)
        XCTAssertEqual(s.rawWallet, first, "같은 스냅샷이 지갑에 두 번 들어갔다")
        XCTAssertEqual(s.pot!.water, grown, "같은 스냅샷으로 또 자랐다")
    }

    /// 첫 설치는 **아무것도 적립하지 않는다.** 설치 전에 쓴 토큰은 내 것이 아니다.
    ///
    /// 예전엔 "이틀치까지" 인정했는데, 그 값이 정확히 5단계 문턱을 넘겨서
    /// 설치하자마자 「Lv.5 자란 줄기」로 시작하는 사람이 사실상 전부였다.
    func testFirstInstallCreditsNothing() {
        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato")
        XCTAssertNil(s.claimedTodayByProvider)

        // 캐시읽기 3B = 300,000mL 상당. 한 톨도 들어가면 안 된다.
        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(cacheRead: 3_000_000_000)], today: day1)

        XCTAssertEqual(s.rawWallet, 0, "설치 전 토큰이 지갑에 소급됐다")
        XCTAssertEqual(s.pot!.water, 0, "설치 전 토큰으로 자랐다")
        XCTAssertEqual(s.pot!.stageIndex, 0, "씨앗으로 시작하지 않았다")
        XCTAssertEqual(s.rawSinceInstall, 0, "설치 전 몫이 누적에 들어갔다")
        XCTAssertTrue(s.installBaselineSet)
        XCTAssertEqual(s.lastDate, day1, "seed 분기가 날짜를 안 적었다")
    }

    /// 첫날 적립이 사라지면서 `lastWaterDay` 도 빈 채로 시작한다.
    /// 그 상태를 "며칠째 안 준 것"으로 읽으면 **설치 직후 바싹 마른 씨앗**이 뜬다.
    func testFreshInstallIsNotThirsty() {
        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato")
        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(cacheRead: 3_000_000_000)],
                           today: day1)
        XCTAssertTrue(s.lastWaterDay.isEmpty, "전제가 깨졌다 — 설치가 물을 줬다")
        XCTAssertEqual(PlantEngine.thirstLevel(s, today: day1), 0, accuracy: 0.0001,
                       "설치 직후에 목이 말랐다")
        // 한참 뒤에 열어도 마찬가지다. 한 번도 안 준 그루는 마른 게 아니라 **막 심은** 것이다.
        XCTAssertEqual(PlantEngine.thirstLevel(s, today: "2027-01-01"), 0, accuracy: 0.0001,
                       "한 번도 안 준 씨앗이 바싹 말랐다")
        XCTAssertFalse(s.pendingEvents.contains(.thirsty), "설치 직후 목마름 알림이 쌓였다")
    }

    /// 기준선을 잡은 **뒤** 쓴 것은 같은 날이라도 온전히 들어온다.
    /// 이게 없으면 설치한 날 하루를 통째로 잃는다.
    func testUsageAfterInstallCreditsInFull() {
        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato")
        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(cacheRead: 3_000_000_000)], today: day1)
        XCTAssertEqual(s.rawWallet, 0)

        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(cacheRead: 3_010_000_000)], today: day1)
        XCTAssertEqual(s.rawWallet, 10_000_000, "설치 후 증분이 잘렸다")
        XCTAssertGreaterThan(s.pot!.water, 0, "설치 후 증분으로 안 자랐다")
    }

    /// 첫 설치 크레딧이 갱신마다 다시 들어오면 안 된다.
    func testFirstInstallCreditIsNotRepeated() {
        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato")
        let snap = ["claude": TokenDelta(cacheRead: 3_000_000_000)]
        PlantEngine.ingest(&s, todayByProvider: snap, today: day1)
        let credited = s.rawWallet
        PlantEngine.ingest(&s, todayByProvider: snap, today: day1)
        XCTAssertEqual(s.rawWallet, credited, "첫 크레딧이 두 번 들어갔다")
    }

    /// 회귀 방지: 날짜 갱신이 seed 판정보다 먼저 오면 `claimedTodayByProvider` 가 [:] 로 채워져
    /// 첫 설치 분기가 영영 안 타고 **설치 전 로그가 통째로 소급된다**.
    /// `lastDate` 가 빈 새 세이브에서 터진다.
    func testFreshInstallOnNewDayStillTakesSeedPath() {
        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato")
        XCTAssertEqual(s.lastDate, "")
        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(cacheRead: 3_000_000_000)],
                           today: day1)
        XCTAssertEqual(s.rawWallet, 0, "seed 분기를 안 타서 설치 전 로그가 소급됐다")
    }

    /// 프로바이더 로그가 정리돼 스냅샷이 줄어들면 기준을 내리고, 지갑은 깎지 않는다.
    func testShrinkingSnapshotDoesNotRemoveWater() {
        var s = freshSave()
        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(cacheRead: 50_000_000)], today: day1)
        let before = s.rawWallet
        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(cacheRead: 1_000_000)], today: day1)
        XCTAssertEqual(s.rawWallet, before)
        // 기준이 내려갔으니 다음 증분은 1M 위에서 정상 계산된다.
        PlantEngine.ingest(&s, todayByProvider: ["claude": TokenDelta(cacheRead: 11_000_000)], today: day1)
        // 기준이 1M 로 내려갔으니 증분은 10M — 지갑에는 원시 토큰 그대로 들어간다.
        XCTAssertEqual(s.rawWallet, before + 10_000_000)
    }

    // MARK: 단계



    /// 이식 준비는 전이에서 한 번만 알린다.
    func testReadyEventFiresOnceOnTransition() {
        var s = freshSave()
        PlantEngine.applyWater(&s, mL: s.pot!.cycleWater, today: day1)
        XCTAssertTrue(s.pot!.isReadyToTransplant)
        _ = PlantEngine.drainEvents(&s)
        PlantEngine.applyWater(&s, mL: 50_000, today: day1)
        XCTAssertFalse(s.pendingEvents.contains(.readyToTransplant))
    }

    // MARK: 스트릭

    /// 스트릭은 `credit`(토큰이 들어온 자리)이 센다. `applyWater` 는 아이템으로도 불리는데
    /// 거기서 세면 **가방의 물을 부어 스트릭을 이어붙일 수 있다** — 그건 "매일 썼다"가 아니다.
    func testStreakGrowsOnConsecutiveDaysAndResetsOnGap() {
        var s = freshSave()
        PlantEngine.credit(&s, raw: 1_000, water: 100, today: "2026-09-01")
        XCTAssertEqual(s.streakDays, 1)
        PlantEngine.credit(&s, raw: 1_000, water: 100, today: "2026-09-02")
        XCTAssertEqual(s.streakDays, 2)
        PlantEngine.credit(&s, raw: 1_000, water: 100, today: "2026-09-05")
        XCTAssertEqual(s.streakDays, 1, "3일 비었는데 스트릭이 이어졌다")

        // 아이템으로 부은 물은 스트릭을 건드리면 안 된다.
        let kept = s.streakDays
        PlantEngine.applyWater(&s, mL: 100, today: "2026-09-06")
        XCTAssertEqual(s.streakDays, kept, "가방의 물로 스트릭이 이어졌다")
    }


    // MARK: 시듦




    // MARK: 손으로 물 주기


    // MARK: 상점



    func testPassiveCannotBeBoughtTwice() {
        var s = freshSave()
        s.rawWallet = ShopItem.shinyCharm.price
        XCTAssertEqual(PlantEngine.buy(.shinyCharm, &s), .ok)
        XCTAssertEqual(PlantEngine.buy(.shinyCharm, &s), .alreadyOwned)
        XCTAssertTrue(s.hasShinyCharm)
    }

    /// 거름은 **기간이 이어 붙고 배수는 안 겹친다.**
    ///
    /// 예전엔 "7일이 다시 시작"이라 돌고 있는 동안 쓰면 남은 날이 날아갔고,
    /// 그걸 막으려고 화면이 버튼을 비활성화했다. 그 결과 **사도 바로 못 쓰는 품목**이 됐다 —
    /// 산 물건을 못 쓰게 막는 건 이유가 뭐든 사용자 입장에선 고장이다.
    /// 이어 붙이면 그 상태 자체가 사라지고, 회수량은 쓴 개수에 그대로 비례한다(선형).
    func testFertilizerExtendsSoItIsAlwaysUsable() {
        var s = freshSave()
        s.inventory[ShopItem.fertilizer.rawValue] = 2
        let now = Date(timeIntervalSince1970: 1_000_000)

        guard case .ok = PlantEngine.use(.fertilizer, &s, today: day1, now: now) else {
            return XCTFail("첫 거름이 실패했다")
        }
        guard let first = s.fertilizerExpiresAt else { return XCTFail("기간이 안 잡혔다") }

        guard case .ok = PlantEngine.use(.fertilizer, &s, today: day1, now: now) else {
            return XCTFail("돌고 있는 동안 못 썼다 — 이게 '사도 바로 못 쓴다'의 정체다")
        }
        guard let second = s.fertilizerExpiresAt else { return XCTFail("기간이 사라졌다") }
        XCTAssertGreaterThan(second, first, "기간이 안 늘었다 — 갱신되기만 했다")

        let days = Calendar.current.dateComponents([.day], from: now, to: second).day ?? 0
        XCTAssertEqual(days, PlantBalance.fertilizerDays * 2, "두 개를 썼는데 기간이 두 배가 아니다")

        // **배수는 절대 안 겹친다.** 겹치면 상점 상한 검증이 통째로 깨진다.
        XCTAssertEqual(PlantBalance.applied(water: 1_000, streakDays: 0, fertilizerActive: true),
                       1_250, "거름 두 개가 +50% 가 됐다")
    }

    /// 천장(3주)에 닿으면 **소모 전에** 막는다 — 소모부터 하면 산 게 그냥 사라진다.
    func testFertilizerStopsAtTheCeiling() {
        var s = freshSave()
        s.inventory[ShopItem.fertilizer.rawValue] = 10
        let now = Date(timeIntervalSince1970: 1_000_000)
        for _ in 0..<10 { _ = PlantEngine.use(.fertilizer, &s, today: day1, now: now) }

        guard let end = s.fertilizerExpiresAt else { return XCTFail("기간이 없다") }
        let days = Calendar.current.dateComponents([.day], from: now, to: end).day ?? 0
        XCTAssertLessThanOrEqual(days, PlantBalance.fertilizerMaxDays, "\(days)일까지 쌓였다")
        XCTAssertGreaterThan(s.count(.fertilizer), 0, "천장에 닿았는데 계속 소모됐다")

        guard case .noEffect = PlantEngine.use(.fertilizer, &s, today: day1, now: now) else {
            return XCTFail("천장을 넘겨서 또 쓰였다")
        }
    }



    // MARK: 이식

    func testTransplantMovesPotToGardenAndPlantsNewSeed() {
        var s = freshSave()
        let cycle = s.pot!.cycleWater
        PlantEngine.applyWater(&s, mL: cycle, today: day1)
        let balanceBefore = s.rawWallet

        XCTAssertTrue(PlantEngine.transplant(&s, roll: 7))
        XCTAssertEqual(s.garden.count, 1)
        XCTAssertEqual(s.garden[0].totalWater, cycle)
        XCTAssertEqual(s.rawWallet, balanceBefore, "이식이 지갑을 건드렸다")
        XCTAssertNotNil(s.pot)
        XCTAssertEqual(s.pot!.water, 0)
        XCTAssertEqual(s.pot!.stageIndex, 0)
    }

    /// 준비되지 않은 그루는 이식되지 않는다 — 자동으로 넘기면 거목을 못 보고 지나친다.
    func testTransplantRejectsUnreadyPot() {
        var s = freshSave()
        PlantEngine.applyWater(&s, mL: 375_000, today: day1)
        XCTAssertFalse(PlantEngine.transplant(&s, roll: 1), "여유분(+25,000)을 안 채웠는데 이식됐다")
    }

    func testSeedGuaranteeIsConsumedOnce() {
        var s = freshSave()
        s.inventory[ShopItem.legendarySeed.rawValue] = 1
        _ = PlantEngine.use(.legendarySeed, &s, today: day1)
        XCTAssertEqual(s.pendingSeedGuarantee, .legendary)

        PlantEngine.plantNewSeed(&s, roll: 3)
        XCTAssertEqual(s.pot!.species.rarity, .legendary)
        XCTAssertNil(s.pendingSeedGuarantee, "보증이 소비되지 않아 다음 씨앗도 전설이 된다")
    }


    // MARK: 연출 대기열

    /// 3일 만에 열었다고 연출을 세 번 재생하면 안 된다.
    func testEventsCoalesceAndDrainOnce() {
        var s = freshSave()
        PlantEngine.applyWater(&s, mL: 1_500, today: day1)
        PlantEngine.applyWater(&s, mL: 3_500, today: day1)
        PlantEngine.applyWater(&s, mL: 7_000, today: day1)
        XCTAssertEqual(s.pendingEvents.filter { $0.coalesceKey == "levelUp" }.count, 1)

        let drained = PlantEngine.drainEvents(&s)
        XCTAssertFalse(drained.isEmpty)
        XCTAssertTrue(s.pendingEvents.isEmpty)
        XCTAssertTrue(PlantEngine.drainEvents(&s).isEmpty)
    }

    /// 같은 종류를 40번 밀어 넣어도 마지막 한 건만 남는다.
    func testSameKindCollapsesToLatest() {
        var s = freshSave()
        for i in 0..<40 { PlantEngine.push(&s, .levelUp(stageIndex: i % 10)) }
        XCTAssertEqual(s.pendingEvents.count, 1)
        XCTAssertEqual(s.pendingEvents.first, PlantEvent.levelUp(stageIndex: 9))
    }

    /// 종류가 다 달라도 상한을 넘지 않는다.
    func testEventQueueIsBounded() {
        var s = freshSave()
        PlantEngine.push(&s, .thirsty)
        PlantEngine.push(&s, .fruitHarvest)
        PlantEngine.push(&s, .readyToTransplant)
        PlantEngine.push(&s, .levelUp(stageIndex: 3))
        PlantEngine.push(&s, .windowBurned(name: "w", raw: 1))
        PlantEngine.push(&s, .transplanted(speciesID: "tomato", isShiny: false))
        PlantEngine.push(&s, .newSeed(speciesID: "rose", rarity: .uncommon, isShiny: true))
        XCTAssertLessThanOrEqual(s.pendingEvents.count, 8)
    }

    // MARK: 저장 왕복

    func testSaveRoundTripsAndSurvivesCorruptField() throws {
        var s = freshSave()
        s.rawWallet = 1_234
        s.garden = [GardenEntry(speciesID: "maple", plantedAt: Date(timeIntervalSince1970: 0), totalWater: 400_000)]
        s.inventory = [ShopItem.fertilizer.rawValue: 3]

        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(PlantSave.self, from: data)
        XCTAssertEqual(back.rawWallet, 1_234)
        XCTAssertEqual(back.garden.count, 1)
        XCTAssertEqual(back.count(.fertilizer), 3)
        XCTAssertEqual(back.pot?.speciesID, "tomato")

        // 한 필드가 깨져도 나머지는 살아야 한다.
        var json = try XCTUnwrap(String(data: data, encoding: .utf8))
        // 키 이름은 `rawWallet` 이다. 옛 이름(`balance`)으로 바꾸면 **치환이 일어나지 않아**
        // 손상되지 않은 JSON 을 검사하게 되고, 테스트가 조용히 아무것도 안 본다.
        json = json.replacingOccurrences(of: "\"rawWallet\":1234", with: "\"rawWallet\":\"broken\"")
        let lenient = try JSONDecoder().decode(PlantSave.self, from: Data(json.utf8))
        XCTAssertEqual(lenient.rawWallet, 0)
        XCTAssertEqual(lenient.garden.count, 1, "한 필드 손상이 정원을 날렸다")
    }

    /// 저장값이 손상돼도 인덱스가 범위를 벗어나 렌더에서 크래시하지 않는다.
    func testCorruptStageIndexIsClamped() throws {
        let json = #"{"speciesID":"tomato","water":-5,"stageIndex":99,"isShiny":false,"fruitHarvested":false}"#
        let p = try JSONDecoder().decode(PotState.self, from: Data(json.utf8))
        XCTAssertEqual(p.stageIndex, PlantBalance.stageCount - 1)
        XCTAssertEqual(p.water, 0)
    }

    // MARK: 종 추첨

    func testGuaranteeNarrowsPoolToRarityOrAbove() {
        for roll in UInt64(0)..<300 {
            let s = PlantOdds.pickSpecies(roll: roll, guarantee: .rare)
            XCTAssertGreaterThanOrEqual(s.rarity.sortRank, PlantRarity.rare.sortRank)
        }
    }

    /// 가중치 공간 전체를 한 바퀴 돌아 실제 분포를 확인한다.
    /// 흔함 5종×620 + 보통 4종×250 + 희귀 4종×100 + 전설 2종×30 = 4,560.
    func testRarityDistributionMatchesWeights() {
        let total = PlantSpecies.catalog.reduce(0) { $0 + $1.rarity.weight }
        XCTAssertEqual(total, 4_560)

        var counts: [PlantRarity: Int] = [:]
        for roll in UInt64(0)..<UInt64(total) {
            let r = PlantOdds.pickSpecies(roll: roll, guarantee: nil).rarity
            counts[r, default: 0] += 1
        }
        XCTAssertEqual(counts[.common], 3_100)
        XCTAssertEqual(counts[.uncommon], 1_000)
        XCTAssertEqual(counts[.rare], 400)
        XCTAssertEqual(counts[.legendary], 60)

        // 전설은 1.3% — 흔하지 않아야 정원이 특별해진다.
        let legendaryShare = Double(counts[.legendary] ?? 0) / Double(total)
        XCTAssertLessThan(legendaryShare, 0.02)
    }

    /// 부적은 확률을 **4배**로 만든다 — 2배였을 때는 20일 값에 반짝 0.23→0.47마리라
    /// 한 마리도 확실하지 않은 데 사이클의 3/4을 거는 셈이었다.
    func testShinyCharmQuadruplesOdds() {
        var plain = 0, charmed = 0
        for roll in UInt64(0)..<1_280 {
            if PlantOdds.rollsShiny(roll: roll, charmOwned: false) { plain += 1 }
            if PlantOdds.rollsShiny(roll: roll, charmOwned: true) { charmed += 1 }
        }
        XCTAssertEqual(plain, 10)
        XCTAssertEqual(charmed, 40)
    }

    // MARK: 화분 슬롯 · 장식

    /// 슬롯 1을 옮겨도 슬롯 0은 그대로여야 한다 — 키패스를 잘못 쓰면 조용히 1번이 날아간다.
    func testTransplantSecondSlotLeavesFirstPotAlone() {
        var s = freshSave()
        // 값을 리터럴로 박으면 가격이 바뀔 때 구매가 조용히 실패하고,
        // 세 줄 뒤 `s.pot2!` 에서 크래시한다. 실제로 그렇게 터졌다.
        s.rawWallet = ShopItem.potSlot.price
        XCTAssertEqual(PlantEngine.buy(.potSlot, &s), .ok, "화분 슬롯을 못 샀다")
        PlantEngine.applyWater(&s, mL: max(s.pot!.cycleWater, s.pot2!.cycleWater), today: day1)
        XCTAssertTrue(s.pot!.isReadyToTransplant)
        XCTAssertTrue(s.pot2!.isReadyToTransplant)

        let firstWater = s.pot!.water
        XCTAssertTrue(PlantEngine.transplant(&s, slot: 1, roll: 7))
        XCTAssertEqual(s.garden.count, 1)
        XCTAssertEqual(s.pot!.water, firstWater, "1번 화분이 건드려졌다")
        XCTAssertEqual(s.pot2!.water, 0, "2번 화분에 새 씨앗이 안 심겼다")

        XCTAssertTrue(PlantEngine.transplant(&s, slot: 0, roll: 9))
        XCTAssertEqual(s.garden.count, 2)
        XCTAssertEqual(s.pot!.water, 0)
    }

    /// 산 씨앗 보증은 한 번만 쓰인다. 두 슬롯이 같이 완주해도 두 번 받으면 상점이 무너진다.
    func testSeedGuaranteeIsSpentOnlyOnFirstSlot() {
        var s = freshSave()
        s.rawWallet = ShopItem.potSlot.price + ShopItem.legendarySeed.price
        XCTAssertEqual(PlantEngine.buy(.potSlot, &s), .ok, "화분 슬롯을 못 샀다")
        XCTAssertEqual(PlantEngine.buy(.legendarySeed, &s), .ok, "전설 씨앗을 못 샀다")
        _ = PlantEngine.use(.legendarySeed, &s, today: day1)
        XCTAssertEqual(s.pendingSeedGuarantee, .legendary)

        PlantEngine.applyWater(&s, mL: max(s.pot!.cycleWater, s.pot2!.cycleWater), today: day1)
        _ = PlantEngine.transplant(&s, slot: 1, roll: 3)
        XCTAssertEqual(s.pendingSeedGuarantee, .legendary, "2번 슬롯이 보증을 먹었다")

        _ = PlantEngine.transplant(&s, slot: 0, roll: 3)
        XCTAssertNil(s.pendingSeedGuarantee)
        XCTAssertEqual(s.pot!.species.rarity, .legendary)
    }

    /// 장식은 가방을 거치지 않고 정원에 바로 놓이고, 두 번 살 수 없다.
    func testDecorationGoesStraightToGarden() {
        var s = freshSave()
        s.rawWallet = ShopItem.bench.price + ShopItem.lantern.price
        XCTAssertEqual(PlantEngine.buy(.bench, &s), .ok)
        XCTAssertEqual(s.decorations, ["bench"])
        XCTAssertEqual(s.count(.bench), 0, "장식이 가방에 담겼다")
        XCTAssertEqual(PlantEngine.buy(.bench, &s), .alreadyOwned, "장식을 두 번 살 수 있다")

        XCTAssertEqual(PlantEngine.buy(.lantern, &s), .ok)
        XCTAssertEqual(s.decorations, ["bench", "lantern"])
        XCTAssertEqual(s.rawWallet, 0, "장식 값이 지갑에서 안 나갔다")
    }

    /// 장식은 순수 꾸미기다. 성장에 손을 대면 "꾸미기"가 아니라 밸런스 품목이 된다.
    func testDecorationHasNoGrowthEffect() {
        var a = freshSave(), b = freshSave()
        let all = ShopItem.bench.price + ShopItem.feeder.price + ShopItem.lantern.price
        a.rawWallet = all; b.rawWallet = all
        for item in [ShopItem.bench, .feeder, .lantern] {
            XCTAssertEqual(PlantEngine.buy(item, &a), .ok, "\(item.name) 을 못 샀다")
        }

        PlantEngine.applyWater(&a, mL: 30_000, today: day1)
        PlantEngine.applyWater(&b, mL: 30_000, today: day1)
        XCTAssertEqual(a.pot!.water, b.pot!.water, "장식이 성장에 영향을 줬다")
        XCTAssertEqual(a.pot!.stageIndex, b.pot!.stageIndex)
    }

    func testDecorationCannotBeUsedFromBag() {
        var s = freshSave()
        s.rawWallet = ShopItem.bench.price
        XCTAssertEqual(PlantEngine.buy(.bench, &s), .ok)
        XCTAssertEqual(PlantEngine.use(.bench, &s, today: day1), .notOwned,
                       "가방에 없는 장식을 쓸 수 있다")
    }

    // MARK: 정원 티어

    func testGardenTiersAdvanceByCount() {
        XCTAssertEqual(GardenTier.tier(forCount: 0).key, "sill")
        XCTAssertEqual(GardenTier.tier(forCount: 2).key, "balc")
        XCTAssertEqual(GardenTier.tier(forCount: 3).key, "bed")
        XCTAssertEqual(GardenTier.tier(forCount: 100).key, "forest")
        XCTAssertEqual(GardenTier.next(afterCount: 3)?.need, 6)
        XCTAssertNil(GardenTier.next(afterCount: 30))
    }
}
