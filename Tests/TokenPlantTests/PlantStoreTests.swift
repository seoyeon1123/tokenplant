import XCTest
@testable import TokenPlant

// MARK: 상태 보관 · 저장 왕복 · 연출 신호
//
// `PlantStore` 는 판정을 안 한다(그건 `PlantEngine`). 여기서 검증하는 건 세 가지다:
//   1. 디스크에 썼다 읽으면 같은 상태인가 — 앱을 껐다 켜도 화분이 그대로여야 한다
//   2. 손상된 파일을 만나도 살아남는가 — 크래시하면 사용자는 앱을 못 연다
//   3. 연출 신호가 화분 두 개에 같이 가는가 — 슬롯 UI 가 여기 걸려 있다

@MainActor
final class PlantStoreTests: XCTestCase {

    /// 테스트마다 새 임시 폴더.
    ///
    /// `setUpWithError`/`tearDownWithError` 를 안 쓴다 — 그건 nonisolated override 라
    /// @MainActor 클래스의 프로퍼티를 건드릴 수 없다(Swift 6 경고). XCTest 는 테스트마다
    /// 인스턴스를 새로 만들므로 `lazy` 만으로 매번 새 폴더가 되고, 정리는 여기서 등록한다.
    private lazy var dir: URL = {
        let d = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tokenplant-store-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: d) }
        return d
    }()

    private var url: URL { dir.appendingPathComponent("state.json") }

    /// 고정 시계. 실제 시각을 쓰면 자정 근처에 테스트가 흔들린다.
    private func clock(_ iso: String = "2026-09-09T04:00:00Z") -> () -> Date {
        let f = ISO8601DateFormatter()
        let d = f.date(from: iso)!
        return { d }
    }

    private func makeStore(_ at: String = "2026-09-09T04:00:00Z") -> PlantStore {
        PlantStore(url: url, clock: clock(at))
    }

    /// 설치 기준선만 잡아 둔다.
    ///
    /// v0.1.1 부터 **첫 갱신은 아무것도 적립하지 않는다**(설치 전 로그를 소급하지 않으려고).
    /// 그래서 "토큰을 썼다"를 재현하려면 기준선을 먼저 잡고 그 뒤에 사용량이 들어와야 한다.
    private func install(_ store: PlantStore, on day: String = "2026-09-09") {
        store.update(todayUsageByProvider: [:], todayDate: day)
    }

    /// 저장 파일을 직접 깔고 읽게 한다.
    /// 화분 슬롯은 150,000mL 이라 테스트 안에서 정직하게 벌어 사기엔 너무 비싸다.
    private func seedFile(_ json: String) throws -> PlantStore {
        try json.write(to: url, atomically: true, encoding: .utf8)
        return makeStore()
    }

    /// 목표(`cycleWater`)는 그루마다 다르다. 옛 저장본엔 이 키가 없어서 `legacyCycleWater` 로 읽히는데,
    /// 테스트 픽스처도 같은 값을 쓴다 — 여기서만 다른 값을 쓰면 단계 임계값이 어긋난다.
    private static let fixtureCycle = PlantBalance.legacyCycleWater

    private func potJSON(_ id: String, water: Int, stage: Int, planted: Double = 800_000_000) -> String {
        """
        {"speciesID":"\(id)","water":\(water),"stageIndex":\(stage),"isShiny":false,
         "plantedAt":\(planted),"fruitHarvested":false,
         "cycleWater":\(Self.fixtureCycle)}
        """
    }

    // MARK: 첫 실행 · 저장 왕복

    /// 화분이 비면 게이지도 상태 문구도 그릴 게 없다 — 첫 실행에 씨앗이 심겨야 한다.
    func testFirstRunPlantsASeedAndWritesFile() {
        let store = makeStore()
        XCTAssertNotNil(store.pot)
        XCTAssertEqual(store.pot?.stageIndex, 0)
        XCTAssertEqual(store.pot?.water, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    /// 앱을 껐다 켜면 같은 그루여야 한다. 매번 새 씨앗이면 사이클이 성립하지 않는다.
    /// 지갑도 같이 살아남아야 한다 — 재시작에 날아가면 모을 이유가 없다.
    func testReloadKeepsTheSamePlantAndWallet() throws {
        let first = makeStore()
        let species = first.pot!.speciesID
        let planted = first.pot!.plantedAt
        install(first)
        first.update(todayUsageByProvider: ["claude": TokenDelta(output: 40_000)],
                     todayDate: "2026-09-09")
        let water = first.pot!.water
        let balance = first.wallet
        XCTAssertGreaterThan(water, 0, "토큰을 썼는데 안 자랐다")
        XCTAssertGreaterThan(balance, 0, "지갑이 안 찼다")

        let second = makeStore()
        XCTAssertEqual(second.pot?.speciesID, species)
        XCTAssertEqual(second.pot?.water, water)
        XCTAssertEqual(second.wallet, balance)
        // `accuracy:` 오버로드는 Optional 을 안 받는다 — 먼저 풀어야 한다.
        let reloaded = try XCTUnwrap(second.pot?.plantedAt.timeIntervalSince1970)
        XCTAssertEqual(reloaded, planted.timeIntervalSince1970, accuracy: 1)
    }

    /// 상점·정원·잔액까지 전부 왕복해야 한다 — 한 필드만 빠지면 사용자가 산 걸 잃는다.
    func testFullSaveRoundTrip() throws {
        let first = makeStore()
        first.injectWaterForPreview(first.pot!.cycleWater)
        XCTAssertTrue(first.pot!.isReadyToTransplant)
        XCTAssertTrue(first.transplant())

        // 벤치를 사려면 지갑에 값만큼 있어야 한다 — 이식은 화폐를 주지 않는다.
        first.creditWalletForPreview(first.price(.bench))
        XCTAssertEqual(first.buy(.bench), .ok)
        XCTAssertEqual(first.wallet, 0, "구매가 지갑에서 안 나갔다")

        let gardenCount = first.save.gardenCount
        let entry = first.save.garden.first!

        let second = makeStore()
        XCTAssertEqual(second.wallet, 0)
        XCTAssertEqual(second.save.gardenCount, gardenCount)
        XCTAssertEqual(second.save.decorations, ["bench"])
        XCTAssertEqual(second.save.passives, ["bench"])
        XCTAssertEqual(second.save.garden.first?.speciesID, entry.speciesID)
        XCTAssertEqual(second.save.garden.first?.totalWater, entry.totalWater)
    }

    // MARK: 손상된 파일

    /// 완전히 깨진 파일이면 새로 시작한다. 크래시하면 사용자는 앱을 아예 못 연다.
    func testGarbageFileFallsBackToFreshSeed() throws {
        try "이건 JSON 이 아니다 {{{".write(to: url, atomically: true, encoding: .utf8)
        let store = makeStore()
        XCTAssertNotNil(store.pot, "손상된 파일에서 화분을 못 만들었다")
        XCTAssertEqual(store.pot?.stageIndex, 0)
    }

    /// 필드가 빠진 예전 버전 파일도 읽혀야 한다 — 업데이트마다 세이브를 날릴 수는 없다.
    func testPartialSaveDecodesLeniently() throws {
        let json = """
        {"pot":{"speciesID":"tomato","water":30000,"stageIndex":4,"isShiny":false,
         "plantedAt":800000000,"fruitHarvested":false},"rawWallet":777}
        """
        try json.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        XCTAssertEqual(store.pot?.speciesID, "tomato")
        XCTAssertEqual(store.pot?.water, 30_000)
        XCTAssertEqual(store.wallet, 777)
        // 없던 필드는 기본값으로 채워진다.
        XCTAssertTrue(store.save.garden.isEmpty)
        XCTAssertTrue(store.save.decorations.isEmpty)
    }

    /// 범위를 벗어난 인덱스는 잘라야 한다 — 안 자르면 스프라이트 배열에서 렌더마다 크래시한다.
    func testOutOfRangeValuesAreClamped() throws {
        let json = """
        {"pot":{"speciesID":"tomato","water":-500,"stageIndex":999,"isShiny":false,
         "plantedAt":800000000,"fruitHarvested":false}}
        """
        try json.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        XCTAssertEqual(store.pot?.stageIndex, PlantBalance.stageCount - 1)
        XCTAssertEqual(store.pot?.water, 0)
        // 실제로 그려지는지까지 확인한다 — clamp 의 목적이 이것이다.
        XCTAssertEqual(PotSprites.grid(stageIndex: store.pot!.stageIndex, motif: store.species(0).motif).count, PotSprites.size)
        XCTAssertFalse(store.stageName.isEmpty)
    }

    /// 알 수 없는 종 id 는 카탈로그 첫 종으로 떨어진다(종을 뺀 업데이트에서 생긴다).
    func testUnknownSpeciesFallsBackInsteadOfCrashing() throws {
        let json = """
        {"pot":{"speciesID":"만들지-않은-종","water":0,"stageIndex":0,"isShiny":false,
         "plantedAt":800000000,"fruitHarvested":false}}
        """
        try json.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        XCTAssertEqual(store.species.id, PlantSpecies.catalog[0].id)
    }

    // MARK: 사용량 유입

    /// 같은 스냅샷이 30초마다 다시 들어온다. 두 번 적립되면 하루에 만렙이다.
    func testRepeatedUpdateWithSameSnapshotDoesNotDoubleCount() {
        let store = makeStore()
        let snap = ["claude": TokenDelta(input: 1_000, output: 50_000, cacheRead: 5_000_000)]

        install(store)
        store.update(todayUsageByProvider: snap, todayDate: "2026-09-09")
        let after = store.wallet
        let grown = store.pot!.water
        XCTAssertGreaterThan(after, 0)
        XCTAssertGreaterThan(grown, 0, "토큰을 썼는데 안 자랐다")

        for _ in 0..<5 { store.update(todayUsageByProvider: snap, todayDate: "2026-09-09") }
        XCTAssertEqual(store.wallet, after, "같은 스냅샷이 지갑에 다시 들어갔다")
        XCTAssertEqual(store.pot!.water, grown, "같은 스냅샷으로 또 자랐다")
    }

    /// 오늘 표시값은 누적에서 빼서 만들면 날 넘어갈 때 틀어진다 — 스냅샷 합으로 직접 계산한다.
    func testTodayDisplayComesFromSnapshotNotFromRunningTotal() {
        let store = makeStore()
        let snap = ["claude": TokenDelta(input: 1_000, output: 100_000,
                                         cacheWrite: 400_000, cacheRead: 20_000_000)]
        install(store)
        store.update(todayUsageByProvider: snap, todayDate: "2026-09-09")

        XCTAssertEqual(store.todayRaw, 20_501_000)
        XCTAssertEqual(store.todayWater, 3_001)

        // 다음 날 아침: 스냅샷이 0으로 리셋되면 표시도 0이어야 한다.
        store.update(todayUsageByProvider: [:], todayDate: "2026-09-10")
        XCTAssertEqual(store.todayRaw, 0)
        XCTAssertEqual(store.todayWater, 0)
        XCTAssertGreaterThan(store.save.rawSinceInstall, 0, "누적은 남아 있어야 한다")
    }

    /// 설치한 사람이 처음 보는 화면은 **씨앗**이어야 한다.
    /// 설치 전에 그날 쓴 토큰이 아무리 많아도 한 톨도 안 센다.
    func testFirstInstallStartsAtSeed() {
        let store = makeStore()
        // 실측 하루(캐시읽기 3B) = 약 300,000mL. 그래도 0 이다.
        store.update(todayUsageByProvider: ["claude": TokenDelta(cacheRead: 3_000_000_000)],
                     todayDate: "2026-09-09")
        XCTAssertEqual(store.wallet, 0, "설치 전 토큰이 지갑에 소급됐다")
        XCTAssertEqual(store.pot!.stageIndex, 0, "씨앗으로 시작하지 않았다")

        // 그 뒤 실제로 더 쓰면 그때부터 자란다.
        store.update(todayUsageByProvider: ["claude": TokenDelta(cacheRead: 3_050_000_000)],
                     todayDate: "2026-09-09")
        XCTAssertGreaterThan(store.wallet, 0, "설치 후 사용분이 안 들어왔다")
    }

    // MARK: 아이템 · 연출 신호

    /// 아이템은 슬롯을 모르는 신호(`itemEffectSeq`)를 올린다 —
    /// 뷰에서 직접 애니메이션을 시작하면 화분이 두 개일 때 한쪽만 움직인다.
    func testUsingAnItemRaisesTheSignalOnlyWhenItWorked() {
        let store = makeStore()
        let before = store.itemEffectSeq

        // 없는 걸 쓰면 아무 일도 없어야 한다 — 헛연출이 제일 나쁘다.
        XCTAssertEqual(store.use(.water), .notOwned)
        XCTAssertEqual(store.itemEffectSeq, before, "안 썼는데 연출이 돌았다")

        store.creditWalletForPreview(store.price(.water))
        XCTAssertEqual(store.buy(.water), .ok)
        XCTAssertEqual(store.wallet, 0, "구매가 지갑에서 안 나갔다")

        let grown = store.pot!.water
        guard case .ok(let gained) = store.use(.water) else { return XCTFail("물을 못 썼다") }
        XCTAssertEqual(gained, store.lastWaterGained)
        XCTAssertGreaterThan(store.pot!.water, grown, "물을 줬는데 안 자랐다")
        XCTAssertEqual(store.itemEffectSeq, before + 1)
    }

    /// 사도 이미 자란 건 안 줄어든다 — 두 물길이 서로 뺏지 않는다는 걸 스토어 층에서도 확인한다.
    func testBuyingNeverShrinksThePlant() {
        let store = makeStore()
        install(store)
        store.update(todayUsageByProvider: ["claude": TokenDelta(output: 400_000)],
                     todayDate: "2026-09-09")
        let grown = store.pot!.water
        XCTAssertGreaterThan(grown, 0)

        store.creditWalletForPreview(store.price(.lantern))
        XCTAssertEqual(store.buy(.lantern), .ok)
        XCTAssertEqual(store.pot!.water, grown, "구매가 성장을 갉아먹었다")
    }

    /// 목마름은 **색만** 마른다. 이미 쓴 토큰으로 자란 걸 방치했다고 깎으면 두 번 뺏는 셈이다.
    func testNeglectDriesTheColorButNeverTheProgress() {
        let store = makeStore()
        store.injectWaterForPreview(20_000)
        let water = store.pot!.water
        XCTAssertEqual(store.wilt, 0, accuracy: 0.001)

        // 열흘 뒤에 열어본다.
        let later = PlantStore(url: url, clock: clock("2026-09-19T04:00:00Z"))
        later.update(todayUsageByProvider: [:], todayDate: "2026-09-19")
        XCTAssertEqual(later.pot!.water, water, "방치가 누적 물을 깎았다")
        XCTAssertEqual(later.wilt, 1, accuracy: 0.001)
        XCTAssertEqual(later.displayState, .parched)
    }

    /// 3일 만에 열었다고 연출을 세 번 재생하면 안 된다 — 가장 중요한 것 하나만.
    func testCelebrationPicksOneEventByPriority() {
        let store = makeStore()
        let before = store.celebrationSeq

        // 단계 상승 여러 번 + 열매 + 이식 가능이 한꺼번에 쌓인다.
        store.injectWaterForPreview(store.pot!.cycleWater)

        XCTAssertEqual(store.celebrationSeq, before + 1, "연출이 여러 번 재생됐다")
        XCTAssertNotNil(store.celebration)
        // 대기열은 비워졌다.
        XCTAssertTrue(store.save.pendingEvents.isEmpty)
    }

    /// 뷰가 이벤트를 소비하지 않는다 — 화분 두 개가 같은 신호를 봐야 한다.
    /// 소비 함수가 있으면 먼저 그려진 쪽이 먹고 다른 쪽은 조용히 게이지만 오른다.
    func testCelebrationSurvivesBeingReadTwice() {
        let store = makeStore()
        store.injectWaterForPreview(5_000)
        let seq = store.celebrationSeq
        let first = store.celebration
        XCTAssertNotNil(first)
        // 두 번째 뷰가 읽어도 값이 남아 있다.
        XCTAssertEqual(store.celebration, first)
        XCTAssertEqual(store.celebrationSeq, seq)
    }

    // MARK: 슬롯 파생값

    func testSlotCountFollowsPotSlotOwnership() throws {
        let one = makeStore()
        XCTAssertEqual(one.slotCount, 1)
        XCTAssertNil(one.pot(1))

        let two = try seedFile("""
        {"pot":\(potJSON("tomato", water: 0, stage: 0)),
         "pot2":\(potJSON("rose", water: 0, stage: 0)),
         "passives":["potSlot"],"rawWallet":100}
        """)
        XCTAssertEqual(two.slotCount, 2)
        XCTAssertNotNil(two.pot(1))
        XCTAssertEqual(two.pot(1)?.speciesID, "rose")
    }

    /// 슬롯별 파생값이 각자의 화분을 봐야 한다 — 키패스를 잘못 쓰면 둘이 같은 값을 보여준다.
    func testSlotAwareDerivedValuesAreIndependent() throws {
        let store = try seedFile("""
        {"pot":\(potJSON("tomato", water: PlantBalance.threshold(stage: 5, cycle: Self.fixtureCycle), stage: 5)),
         "pot2":\(potJSON("rose", water: 0, stage: 0)),
         "passives":["potSlot"]}
        """)

        XCTAssertEqual(store.stageName(0), PotSprites.stages[5].name)
        XCTAssertEqual(store.stageName(1), PotSprites.stages[0].name)
        XCTAssertEqual(store.species(0).id, "tomato")
        XCTAssertEqual(store.species(1).id, "rose")
        XCTAssertNotEqual(store.waterToNext(0), store.waterToNext(1))
        XCTAssertEqual(store.stageProgress(1), 0)
        XCTAssertLessThan(store.daysToTransplant(0)!, store.daysToTransplant(1)!)

        // 0-인자 버전은 슬롯 0 의 별칭이어야 한다.
        XCTAssertEqual(store.stageProgress, store.stageProgress(0))
        XCTAssertEqual(store.stageName, store.stageName(0))
        XCTAssertEqual(store.waterToNext, store.waterToNext(0))
        XCTAssertEqual(store.species.id, store.species(0).id)
    }

    /// 물은 **양쪽 화분에 똑같이** 들어간다.
    /// 나눠 주면 슬롯을 사는 게 성장 반토막이라 아무도 안 산다.
    func testGrowthReachesBothSlotsEqually() throws {
        let store = try seedFile("""
        {"pot":\(potJSON("tomato", water: 1_000, stage: 0)),
         "pot2":\(potJSON("rose", water: 5_000, stage: 2)),
         "passives":["potSlot"],"claimedTodayByProvider":{}}
        """)
        let before0 = store.pot(0)!.water
        let before1 = store.pot(1)!.water

        store.update(todayUsageByProvider: ["claude": TokenDelta(output: 30_000)],
                     todayDate: "2026-09-09")
        XCTAssertGreaterThan(store.wallet, 0, "지갑이 안 찼다")

        let gained0 = store.pot(0)!.water - before0
        let gained1 = store.pot(1)!.water - before1
        XCTAssertGreaterThan(gained0, 0, "화분이 안 자랐다")
        XCTAssertEqual(gained0, gained1, "두 화분이 다른 양을 받았다")
    }

    /// 이식은 슬롯별이다 — 물·아이템과 달리 여기만 화분을 갈라 본다.
    func testTransplantingOneSlotLeavesTheOtherAlone() throws {
        let store = try seedFile("""
        {"pot":\(potJSON("tomato", water: Self.fixtureCycle, stage: 9)),
         "pot2":\(potJSON("rose", water: 12_345, stage: 3)),
         "passives":["potSlot"]}
        """)
        XCTAssertTrue(store.pot(0)!.isReadyToTransplant)
        XCTAssertFalse(store.pot(1)!.isReadyToTransplant)

        XCTAssertTrue(store.transplant(slot: 0))
        XCTAssertEqual(store.save.gardenCount, 1)
        XCTAssertEqual(store.save.garden.first?.speciesID, "tomato")
        XCTAssertEqual(store.pot(0)?.water, 0, "새 씨앗이 안 심겼다")
        XCTAssertEqual(store.pot(1)?.water, 12_345, "다른 슬롯이 건드려졌다")

        // 아직 안 자란 슬롯은 이식할 수 없다.
        XCTAssertFalse(store.transplant(slot: 1))
        XCTAssertEqual(store.save.gardenCount, 1)
    }

    func testRenameTargetsTheRequestedSlot() throws {
        let store = try seedFile("""
        {"pot":\(potJSON("tomato", water: 0, stage: 0)),
         "pot2":\(potJSON("rose", water: 0, stage: 0)),
         "passives":["potSlot"]}
        """)
        store.rename("첫째", slot: 0)
        store.rename("둘째", slot: 1)
        XCTAssertEqual(store.pot(0)?.nickname, "첫째")
        XCTAssertEqual(store.pot(1)?.nickname, "둘째")

        // 공백만 넣으면 별명을 지운다.
        store.rename("   ", slot: 0)
        XCTAssertNil(store.pot(0)?.nickname)
        XCTAssertEqual(store.pot(1)?.nickname, "둘째")

        // 저장까지 왕복해야 명패가 유지된다.
        XCTAssertEqual(makeStore().pot(1)?.nickname, "둘째")
    }

    // MARK: 상태 문구 · 표시값

    /// 모든 상태에 문구가 있어야 한다 — 빈 줄이 뜨면 화면이 깨진 것처럼 보인다.
    func testEveryDisplayStateHasAStatusLine() {
        let store = makeStore()
        for _ in 0..<3 {
            XCTAssertFalse(store.statusLine.isEmpty)
            store.injectWaterForPreview(20_000)
        }
        XCTAssertFalse(store.stageName.isEmpty)
    }

    /// 성장 배율을 켜둔 채 업데이트한 사람의 세이브도 그대로 읽혀야 한다.
    /// 필드는 없어졌지만 남아 있는 키 때문에 디코딩이 통째로 실패하면 정원이 날아간다.
    func testLegacyGrowthScaleKeyIsIgnored() throws {
        let json = """
        {"pot":{"speciesID":"tomato","water":30000,"stageIndex":4,"isShiny":false,
         "plantedAt":800000000,"fruitHarvested":false},
         "rawWallet":555,"growthScalePercent":200}
        """
        try json.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        XCTAssertEqual(store.pot?.speciesID, "tomato")
        XCTAssertEqual(store.pot?.water, 30_000)
        XCTAssertEqual(store.wallet, 555, "옛 키 하나 때문에 세이브가 통째로 버려졌다")
    }

    /// 이식까지 남은 일수는 남은 양보다 잘 읽힌다. 만렙이면 0.
    func testDaysToTransplantIsPositiveThenZero() {
        let store = makeStore()
        XCTAssertGreaterThan(store.daysToTransplant ?? 0, 0)
        store.injectWaterForPreview(store.pot!.cycleWater)
        XCTAssertEqual(store.daysToTransplant, 0)
    }
}
