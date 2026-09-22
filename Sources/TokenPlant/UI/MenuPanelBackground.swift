import SwiftUI
import AppKit

/// 메뉴바 팝오버의 배경.
///
/// `MenuBarExtra(.window)` 는 배경을 알아서 칠해주지 않는다. 그냥 두면 패널의
/// 맨바닥(불투명한 흰 창 배경)이 그대로 보여서, 맥 기본 메뉴 팝오버와 달리
/// 뒤가 안 비치는 흰 판이 화면에 붕 떠 있는 것처럼 보인다.
///
/// `.ultraThinMaterial` 같은 SwiftUI 머티리얼로는 안 된다 — 그건 **창 안의**
/// 내용을 흐리므로, 흰 바닥을 흐려봤자 여전히 흰색이다. 뒤에 있는 화면을 흐리려면
/// `blendingMode = .behindWindow` 인 `NSVisualEffectView` 여야 한다.
struct MenuPanelBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: NSVisualEffectView) {
        // `.menu` 는 메뉴·메뉴바 팝오버가 쓰는 바로 그 머티리얼이다.
        view.material = .menu
        view.blendingMode = .behindWindow
        // `.followsWindowActiveState` 로 두면 팝오버가 포커스를 잃는 순간
        // 흐림이 꺼져 회색 판이 된다. 메뉴바 팝오버는 항상 활성으로 그린다.
        view.state = .active
    }
}
