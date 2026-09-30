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
    dependencies: [
        // 자동 업데이트. **Apple Developer 계정 없이도 된다** —
        // Developer ID 서명은 "가능하면" 권장이고, 없으면 EdDSA(ed25519) 서명으로 검증한다.
        // ad-hoc 서명은 빌드마다 달라지는데 Sparkle 2 는 코드 서명이 안 맞아도
        // EdDSA 가 맞으면 받아들인다. 잘못된 EdDSA 는 제대로 거부한다.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "TokenPlant",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/TokenPlant"
        ),
        .testTarget(
            name: "TokenPlantTests",
            dependencies: ["TokenPlant"],
            path: "Tests/TokenPlantTests"
        ),
    ]
)
