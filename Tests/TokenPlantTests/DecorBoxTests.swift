import XCTest
@testable import TokenPlant

// MARK: 장식 뽑기 — **꽝이 없어야 한다**
//
// 왜 넣었나: 보유형 다섯 개(슬롯·부적·장식 셋)는 17일이면 다 팔리고,
// 그 뒤로 상점에 새로 열리는 게 영원히 없다. 살 수 있는 건 물·거름·영양제·씨앗뿐인데
// 그건 전부 "또 그거"라서, 구매가 사건이 아니라 유지보수가 된다.
//
// 장식 아홉을 그냥 상점에 늘어놓는 것도 방법이다. 그런데 그러면 값 오름차순으로
// 사는 목록이 될 뿐이라 **누를 때 아무 일도 안 일어난다.** 뽑기는 그 순간에 결과가 있다.
//
// 대신 지켜야 할 선이 하나 있다: **중복이 나오면 그 즉시 도박이 된다.**
// 돈을 냈는데 아무것도 못 받는 경험이 한 번이라도 있으면 성격이 통째로 바뀐다.
// 그래서 아직 없는 것 중에서만 뽑는다. 이 파일은 그 선을 지킨다.

final class DecorBoxTests: XCTestCase {

    private let day1 = "2026-09-01"

    private func freshSave() -> PlantSave {
        var s = PlantSave()
        s.pot = PotState(speciesID: "tomato", cycleWater: PlantBalance.legacyCycleWater)
        s.claimedTodayByProvider = [:]
        return s
    }

    /// 아홉 번 뽑으면 아홉 종이 나온다. 롤을 흩어도 중복이 없어야 한다.
    func testDecorBoxNeverGivesADuplicate() {
        var s = freshSave()
        let pool = DecorIcons.gachaKeys
        s.inventory[ShopItem.decorBox.rawValue] = pool.count

        var got: [String] = []
        for i in 0..<pool.count {
            let r = PlantEngine.use(.decorBox, &s, today: day1, roll: UInt64(i * 7 + 3))
            guard case .ok = r else { return XCTFail("\(i + 1)번째 뽑기가 실패했다: \(r)") }
            got.append(s.decorations.last ?? "")
        }
        XCTAssertEqual(Set(got).count, pool.count, "중복이 나왔다: \(got)")
        XCTAssertEqual(got.sorted(), pool.sorted(), "안 나온 장식이 있다")
    }

    /// 다 모은 사람이 또 쓰면 **소모되지 않고** 거절된다.
    /// 소모부터 하면 "돈 내고 아무것도 못 받음"이 되는데, 그게 정확히 피하려던 것이다.
    func testDecorBoxRefusesWhenEverythingIsOwned() {
        var s = freshSave()
        s.decorations = DecorIcons.gachaKeys
        s.inventory[ShopItem.decorBox.rawValue] = 1

        let r = PlantEngine.use(.decorBox, &s, today: day1, roll: 1)
        guard case .noEffect = r else { return XCTFail("다 모았는데 또 뽑혔다: \(r)") }
        XCTAssertEqual(s.count(.decorBox), 1, "실패했는데 소모됐다")
    }

    /// 성장도 지갑도 안 건드린다. 장식은 순수 꾸미기고, 여기서 물이 나오면 두 물길이 섞인다.
    func testDecorBoxDoesNotTouchGrowthOrWallet() {
        var s = freshSave()
        s.inventory[ShopItem.decorBox.rawValue] = 1
        let water = s.pot?.water ?? -1
        let wallet = s.rawWallet

        let r = PlantEngine.use(.decorBox, &s, today: day1, roll: 5)
        guard case .ok(let gained) = r else { return XCTFail("뽑기가 실패했다: \(r)") }
        XCTAssertEqual(gained, 0, "뽑기가 물을 줬다")
        XCTAssertEqual(s.pot?.water, water, "뽑기가 화분을 키웠다")
        XCTAssertEqual(s.rawWallet, wallet, "뽑기가 지갑을 건드렸다")
        XCTAssertEqual(s.decorations.count, 1, "정원에 안 놓였다")
    }

    /// 뭐가 나왔는지를 이벤트에 실어야 한다. "장식을 받았어요"만 띄우면
    /// 정원을 열어봐야 확인이 되고, 그러면 누른 보람이 그 자리에서 사라진다.
    func testDecorBoxSaysWhatCameOut() {
        var s = freshSave()
        s.inventory[ShopItem.decorBox.rawValue] = 1
        _ = PlantEngine.use(.decorBox, &s, today: day1, roll: 2)

        let found = PlantEngine.drainEvents(&s).compactMap { event -> String? in
            if case .decorFound(let key) = event { return key }
            return nil
        }
        XCTAssertEqual(found.count, 1, "뽑기 결과 이벤트가 없다")
        XCTAssertEqual(found.first, s.decorations.last)
        XCTAssertNotEqual(DecorIcons.name(found[0]), found[0], "이름이 없어 키가 그대로 화면에 뜬다")
    }

    /// 하루치라 제일 싸서 늘 먼저 걸린다. 성장에 도움이 안 되는 걸 목표로 걸면 모을 이유가 없다.
    func testDecorBoxIsNotANextGoal() {
        XCTAssertTrue(ShopItem.decorBox.isCosmetic, "장식 뽑기가 성장 품목으로 분류됐다")
        XCTAssertFalse(ShopItem.decorBox.isDecoration, "뽑기 자체는 정원에 놓이는 물건이 아니다")
        XCTAssertFalse(ShopItem.decorBox.isPassive, "뽑기는 소모품이어야 한다")
    }

    /// 상점에서 직접 사는 장식과 뽑기 풀이 겹치면, 산 걸 또 뽑거나 풀이 조용히 줄어든다.
    func testShopDecorAndGachaDecorDoNotOverlap() {
        let shop = Set(DecorIcons.shopKeys)
        let gacha = Set(DecorIcons.gachaKeys)
        XCTAssertTrue(shop.isDisjoint(with: gacha), "겹치는 장식: \(shop.intersection(gacha))")
        XCTAssertEqual(DecorIcons.allKeys.count, 12)

        // 선언만 있고 아트가 없으면 정원에 빈칸이 놓이는데, 뽑기는 "받았다"고 말한다.
        for key in DecorIcons.allKeys {
            XCTAssertNotNil(DecorIcons.grid(key), "\(key) 아트가 없다")
            XCTAssertNotEqual(DecorIcons.name(key), key, "\(key) 이름이 없다")
        }
    }

    /// 상점에서 직접 사는 장식 셋이 `isDecoration` 과 `shopKeys` 양쪽에서 같아야 한다.
    /// 갈리면 상점에서 산 장식이 정원에 안 놓이거나, 뽑기 풀에 끼어든다.
    func testShopDecorationsMatchTheirKeys() {
        let fromShop = Set(ShopItem.allCases.filter { $0.isDecoration }.map(\.rawValue))
        XCTAssertEqual(fromShop, Set(DecorIcons.shopKeys))
    }
}
