import Foundation
import XCTest
@testable import TokenPlant

final class LocalizationTests: XCTestCase {
    func testLanguagePreferenceOrderAndFallback() {
        XCTAssertEqual(L10n.language(for: ["zh-Hans-CN", "ko-KR"]), .simplifiedChinese)
        XCTAssertEqual(L10n.language(for: ["ko-KR", "zh-Hans"]), .korean)
        XCTAssertEqual(L10n.language(for: ["en-US", "zh_CN"]), .simplifiedChinese)
        XCTAssertEqual(L10n.language(for: ["zh-SG"]), .simplifiedChinese)
        XCTAssertEqual(L10n.language(for: ["en-US"]), .korean)
        XCTAssertEqual(L10n.language(for: []), .korean)
    }
    func testKoreanStringsArePreserved() {
        XCTAssertEqual(L10n.text("화분", language: .korean), "화분")
        XCTAssertEqual(L10n.text("다음 선물까지 \(3)일", language: .korean), "다음 선물까지 3일")
    }
    func testChineseNamesAndDisplayUnits() {
        XCTAssertEqual(L10n.text("튤립", language: .simplifiedChinese), "郁金香")
        XCTAssertEqual(L10n.text("행운", language: .simplifiedChinese), "闪光")
        XCTAssertEqual(L10n.text("\(2)시간", language: .simplifiedChinese), "2 小时")
        XCTAssertEqual(L10n.text("\(45)분", language: .simplifiedChinese), "45 分钟")
        XCTAssertEqual(L10n.lookup("새 모이통", language: .simplifiedChinese), "喂鸟器")
    }
    func testArgumentsCanBeReordered() {
        XCTAssertEqual(L10n.text("\(7)일간 +\(25)% · 사용 중 \(3)일", language: .simplifiedChinese),
                       "水量 +25%，持续 7 天 · 剩余 3 天")
    }
    func testFormattedGrowthAndGardenLabelsKeepTheirValues() {
        let water = "1,500", tier = "阳台"
        XCTAssertEqual(L10n.text("다음까지 \(water) mL", language: .simplifiedChinese), "距下一阶段还需 1,500 mL")
        XCTAssertEqual(L10n.text("\(tier)까지 \(1)그루", language: .simplifiedChinese), "再移栽 1 株可升级至阳台")
    }
    func testNicknameAndPercentAreNeverReinterpreted() {
        let name = "小花{1}%🌻", amount = "1,234"
        XCTAssertEqual(L10n.text("\(name) — 물 +\(amount) mL", language: .simplifiedChinese),
                       "小花{1}%🌻 · 水量 +1,234 mL")
        XCTAssertEqual(L10n.text("\(name) — 물 +\(amount) mL", language: .korean),
                       "小花{1}%🌻 — 물 +1,234 mL")
    }
    func testUnknownStringsFallBackWithoutLosingArguments() {
        XCTAssertEqual(L10n.text("unknown \(42)", language: .simplifiedChinese), "unknown 42")
        XCTAssertEqual(L10n.lookup("unknown", language: .simplifiedChinese), "unknown")
    }
    func testCatalogPreservesEveryPlaceholderAndContainsNoKoreanTranslation() throws {
        let placeholders = try NSRegularExpression(pattern: #"\{[0-9]+\}"#)
        let korean = try NSRegularExpression(pattern: "[가-힣]")
        func tokens(_ value: String) -> [String] {
            placeholders.matches(in: value, range: NSRange(value.startIndex..., in: value))
                .map { (value as NSString).substring(with: $0.range) }.sorted()
        }
        for (source, translation) in L10n.simplifiedChinese {
            XCTAssertEqual(tokens(source), tokens(translation), source)
            XCTAssertNil(korean.firstMatch(in: translation, range: NSRange(translation.startIndex..., in: translation)), source)
        }
    }
    func testShopCategoryKeysStayLanguageIndependent() {
        XCTAssertEqual(ShopItem.water.category, "성장")
        XCTAssertEqual(ShopItem.decorBox.category, "장식")
        XCTAssertTrue(ShopItem.decorBox.isCosmetic)
        XCTAssertFalse(ShopItem.water.isCosmetic)
    }
}
