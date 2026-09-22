// swift-tools-version: 6.0
import PackageDescription

// TokenPlant — PokeTokenBar(MIT, chattymin) 의 구조를 따르되 포켓몬 레이어를 식물로 교체한다.
//
// PokeTokenBar 와 같은 모양으로 둔다: 단일 executableTarget + 그것에 의존하는 testTarget.
// 그래야 Core 타입들을 public 으로 열지 않고 `@testable import` 로 그대로 쓸 수 있고,
// 포크에 합칠 때 파일만 옮기면 된다.
//
// Core/  는 Foundation 전용이라 UI 없이도 테스트가 돈다.
// UI/    는 SwiftUI. 지금은 가짜 물로 연출을 검증하는 프리뷰 앱이 붙어 있고,
//        포크에서는 그 자리에 UsageStore 가 들어온다.
let package = Package(
    name: "TokenPlant",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TokenPlant",
            path: "Sources/TokenPlant"
        ),
        .testTarget(
            name: "TokenPlantTests",
            dependencies: ["TokenPlant"],
            path: "Tests/TokenPlantTests"
        ),
    ]
)
