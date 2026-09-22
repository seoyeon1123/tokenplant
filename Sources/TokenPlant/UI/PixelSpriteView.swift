import SwiftUI
import AppKit

// 픽셀 그리드를 그리는 곳. 스프라이트가 문자 배열이라 이미지 파일이 없다 —
// 종을 늘려도 에셋이 안 늘어나는 대신, 렌더는 여기 한 군데만 있어야 한다.

/// SwiftUI Canvas 로 픽셀 그리드를 그린다. 팝오버·정원 창 공용.
struct PixelSpriteView: View {
    let grid: [[Character]]
    let species: PlantSpecies
    var wilt: Double = 0
    /// 픽셀 하나의 화면 크기. nil = 주어진 공간에 맞춰 정수배로 채운다.
    var pixelSize: CGFloat? = nil
    /// 잎만 세로로 늘렸다 줄이는 연출(물 줄 때). 화분은 고정.
    var squash: Double = 1
    /// 이 행부터 아래는 화분 — squash 대상에서 제외한다.
    var potRow: Int = PotSprites.plantRows

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let rows = grid.count
            let cols = grid.first?.count ?? 0
            guard rows > 0, cols > 0 else { return }

            let s = pixelSize ?? max(1, floor(min(size.width / CGFloat(cols),
                                                  size.height / CGFloat(rows))))
            let originX = (size.width - s * CGFloat(cols)) / 2
            let originY = (size.height - s * CGFloat(rows)) / 2
            let pivotY = originY + s * CGFloat(potRow)

            for y in 0..<rows {
                let isPlant = y < potRow
                for x in 0..<cols {
                    guard let hex = PlantSpriteBuilder.color(grid[y][x], species: species, wilt: wilt),
                          let color = Color(hex: hex) else { continue }

                    var rect = CGRect(x: originX + s * CGFloat(x),
                                      y: originY + s * CGFloat(y),
                                      width: s, height: s)
                    if isPlant, squash != 1 {
                        // 화분 바닥을 피벗으로 세로 스케일. 픽셀 경계를 유지해야 자글거리지 않는다.
                        let top = pivotY - (pivotY - rect.minY) * squash
                        let bottom = pivotY - (pivotY - rect.maxY) * squash
                        rect = CGRect(x: rect.minX, y: top, width: s, height: max(0.5, bottom - top))
                    }
                    ctx.fill(Path(rect), with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// 아이콘 격자(`ItemIcons` · `DecorIcons`)를 그린다.
///
/// 식물 스프라이트와 렌더러를 나눈 이유: 식물은 팔레트가 종마다 바뀌어서
/// `PlantSpriteBuilder.color(_:species:wilt:)` 를 타야 하지만, 아이콘은 색이 고정이라
/// `IconPalette` 를 직접 본다. 한 함수에 두 규칙을 섞으면 종 팔레트가 아이콘까지 물들인다.
struct PixelIconView: View {
    let grid: [[Character]]
    var pixelSize: CGFloat = 1

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, _ in
            for (y, row) in grid.enumerated() {
                for (x, ch) in row.enumerated() {
                    guard let hex = IconPalette.color(ch), let c = Color(hex: hex) else { continue }
                    ctx.fill(Path(CGRect(x: CGFloat(x) * pixelSize, y: CGFloat(y) * pixelSize,
                                         width: pixelSize, height: pixelSize)), with: .color(c))
                }
            }
        }
        .frame(width: CGFloat(grid.first?.count ?? 0) * pixelSize,
               height: CGFloat(grid.count) * pixelSize)
        .allowsHitTesting(false)
    }
}

/// 상점 품목 아이콘 한 칸. 아트가 없으면 이모지로 떨어진다 —
/// 품목을 새로 추가하고 그림을 아직 안 그렸을 때 빈칸이 되면 안 된다.
struct ShopItemIcon: View {
    let item: ShopItem
    var pixelSize: CGFloat = 1
    var dimmed: Bool = false

    var body: some View {
        Group {
            if let g = ItemIcons.grid(item) {
                PixelIconView(grid: g, pixelSize: pixelSize)
            } else if let g = DecorIcons.grid(item.rawValue) {
                PixelIconView(grid: g, pixelSize: pixelSize)
            } else {
                Text(item.fallbackEmoji)
                    .font(.system(size: pixelSize * 11))
                    .frame(width: CGFloat(ItemIcons.size) * pixelSize,
                           height: CGFloat(ItemIcons.size) * pixelSize)
            }
        }
        .opacity(dimmed ? 0.32 : 1)
    }
}

/// 정원 장식 한 칸. **실루엣 모드**가 있다 — 아직 안 나온 장식을 검게 깔아두면
/// "저건 뭐지"가 생긴다. 빈칸으로 두면 몇 개가 남았는지도 안 보인다.
struct DecorIcon: View {
    let key: String
    var pixelSize: CGFloat = 1
    var silhouette: Bool = false

    var body: some View {
        Group {
            if let g = DecorIcons.grid(key) {
                if silhouette {
                    SilhouetteView(grid: g, pixelSize: pixelSize)
                } else {
                    PixelIconView(grid: g, pixelSize: pixelSize)
                }
            } else {
                Color.clear
                    .frame(width: CGFloat(DecorIcons.size) * pixelSize,
                           height: CGFloat(DecorIcons.size) * pixelSize)
            }
        }
    }
}

/// 칠해진 픽셀을 **모양만 남기고** 한 색으로 덮는다. 색이 남아 있으면 이미 본 것처럼 읽힌다.
struct SilhouetteView: View {
    let grid: [[Character]]
    var pixelSize: CGFloat = 1

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, _ in
            for (y, row) in grid.enumerated() {
                for (x, ch) in row.enumerated() where ch != "." {
                    ctx.fill(Path(CGRect(x: CGFloat(x) * pixelSize, y: CGFloat(y) * pixelSize,
                                         width: pixelSize, height: pixelSize)),
                             with: .color(.primary.opacity(0.22)))
                }
            }
        }
        .frame(width: CGFloat(grid.first?.count ?? 0) * pixelSize,
               height: CGFloat(grid.count) * pixelSize)
        .allowsHitTesting(false)
    }
}

/// 메뉴바용 NSImage. Canvas 는 메뉴바 아이템에 쓸 수 없어 별도 경로가 필요하다.
enum PixelSpriteImage {
    /// 16×16 근처로 축소해 그린다. `scale` 은 픽셀 하나가 몇 포인트인지.
    static func make(grid: [[Character]], species: PlantSpecies, wilt: Double, scale: CGFloat) -> NSImage {
        let rows = grid.count
        let cols = grid.first?.count ?? 0
        let size = NSSize(width: CGFloat(cols) * scale, height: CGFloat(rows) * scale)
        guard rows > 0, cols > 0, size.width > 0, size.height > 0 else { return NSImage(size: .init(width: 1, height: 1)) }

        let image = NSImage(size: size)
        image.lockFocusFlipped(true)
        defer { image.unlockFocus() }

        for y in 0..<rows {
            for x in 0..<cols {
                guard let hex = PlantSpriteBuilder.color(grid[y][x], species: species, wilt: wilt),
                      let ns = NSColor(hex: hex) else { continue }
                ns.setFill()
                NSRect(x: CGFloat(x) * scale, y: CGFloat(y) * scale, width: scale, height: scale).fill()
            }
        }
        // 템플릿으로 두면 단색이 되어 잎/화분 구분이 사라진다 — 컬러 그대로 쓴다.
        image.isTemplate = false
        return image
    }
}

// MARK: 색 변환

extension Color {
    init?(hex: String) {
        guard let rgb = PlantSpriteBuilder.rgb(hex) else { return nil }
        self.init(.sRGB,
                  red: Double(rgb.0) / 255,
                  green: Double(rgb.1) / 255,
                  blue: Double(rgb.2) / 255,
                  opacity: 1)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        guard let rgb = PlantSpriteBuilder.rgb(hex) else { return nil }
        self.init(srgbRed: CGFloat(rgb.0) / 255,
                  green: CGFloat(rgb.1) / 255,
                  blue: CGFloat(rgb.2) / 255,
                  alpha: 1)
    }
}
