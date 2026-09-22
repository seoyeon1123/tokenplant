import Foundation

// 정원 씬 데이터. 배경 스프라이트를 그리지 않고 요소 플래그로 조합한다 —
// 티어가 7개인데 배경을 7장 그리면 계절 팔레트를 얹을 때마다 21장이 된다.

/// 배경 요소.
enum SceneFeature: String, Sendable {
    case sky, grass, fence, glass, sill, path, pond
}

/// 계절 팔레트. 배경만 갈아끼우고 스프라이트는 한 장도 다시 그리지 않는다.
struct SeasonPalette: Sendable {
    let key: String
    let name: String
    let sky: String
    let grass: String
    let grass2: String
    let path: String
    let fence: String
    let fence2: String
    let water: String
    /// 밤에는 잎도 같이 어두워져야 한다 — 배경만 어둡게 하면 나무가 형광처럼 뜬다.
    let extraHaze: Double

    static let all: [SeasonPalette] = [
        .init(key: "spring", name: "봄 · 낮",
              sky: "#cfe4ef", grass: "#7fbf6a", grass2: "#6aa858",
              path: "#c2a172", fence: "#a67c52", fence2: "#8a6440",
              water: "#6fb3d9", extraHaze: 0.0),
        .init(key: "autumn", name: "가을",
              sky: "#e8dcc0", grass: "#b09a52", grass2: "#98853f",
              path: "#c2a172", fence: "#8a6440", fence2: "#6f4f32",
              water: "#5f9dc0", extraHaze: 0.0),
        .init(key: "night", name: "밤",
              sky: "#2a3350", grass: "#3a5340", grass2: "#2f4535",
              path: "#5c4c3a", fence: "#4a3828", fence2: "#372a1e",
              water: "#2f5a78", extraHaze: 0.3),
    ]

    static func byKey(_ k: String) -> SeasonPalette { all.first { $0.key == k } ?? all[0] }

    /// 시스템 시간에 따라 고른다. 온실 티어부터 활성.
    static var current: SeasonPalette {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 6 || h >= 19 { return byKey("night") }
        let m = Calendar.current.component(.month, from: Date())
        return (9...11).contains(m) ? byKey("autumn") : byKey("spring")
    }
}

/// 티어별 캔버스와 슬롯 좌표. 슬롯은 나무 왼쪽-아래 기준점이고,
/// **뒷줄을 먼저 그려** 앞줄이 자연스럽게 겹친다.
struct SceneLayout: Sendable {
    let key: String
    let width: Int
    let height: Int
    let features: Set<SceneFeature>
    /// (baseline, x 좌표들) — 앞 원소가 뒷줄이다.
    let rows: [(baseline: Int, xs: [Int])]

    static let all: [SceneLayout] = [
        .init(key: "sill", width: 72, height: 40,
              features: [.sill, .sky],
              rows: []),
        .init(key: "balc", width: 88, height: 44,
              features: [.sill, .sky],
              rows: [(baseline: 30, xs: [36])]),
        .init(key: "bed", width: 104, height: 48,
              features: [.grass, .sky],
              rows: [(baseline: 34, xs: [12, 44, 76])]),
        .init(key: "yard", width: 136, height: 56,
              features: [.fence, .grass, .path, .sky],
              rows: [(baseline: 34, xs: [8, 40, 72, 104]), (baseline: 44, xs: [24, 88])]),
        .init(key: "green", width: 168, height: 64,
              features: [.glass, .grass, .path],
              rows: [(baseline: 38, xs: [8, 36, 64, 92, 120, 148]), (baseline: 50, xs: [22, 78, 106, 134])]),
        // 수목원은 18그루를 담아야 한다(해금 조건). 슬롯이 그보다 적으면 이식한 그루가
        // 조용히 사라진다 — 처음 좌표는 16개뿐이었고 오른쪽 끝 하나는 캔버스를 넘겼다.
        .init(key: "arbor", width: 224, height: 88,
              features: [.fence, .grass, .pond, .sky],
              rows: [(baseline: 46, xs: [4, 26, 48, 70, 92, 114, 136, 158, 180, 202]),
                     (baseline: 64, xs: [15, 38, 61, 84, 107, 130, 153, 176, 199])]),
        .init(key: "forest", width: 272, height: 104,
              features: [.grass, .path, .pond, .sky],
              rows: [(baseline: 48, xs: [4, 29, 54, 79, 104, 129, 154, 179, 204, 229, 254]),
                     (baseline: 66, xs: [14, 39, 64, 89, 114, 139, 164, 189, 214, 239]),
                     (baseline: 84, xs: [6, 34, 62, 90, 118, 146, 174, 202, 230])]),
    ]

    static func byKey(_ k: String) -> SceneLayout { all.first { $0.key == k } ?? all[0] }

    var horizon: Int { Int(Double(height) * 0.42) }

    /// 총 슬롯 수 — 티어가 담을 수 있는 그루 수.
    var slotCount: Int { rows.reduce(0) { $0 + $1.xs.count } }
}
