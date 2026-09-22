import Foundation
import ServiceManagement

/// 로그인할 때 자동 실행 — 메뉴바 앱은 이게 없으면 매번 직접 열어야 한다.
///
/// `swift run` 으로 띄운 프로세스에는 걸 수 없다. `SMAppService.mainApp` 은
/// **번들된 앱**(`TokenPlant.app`)의 번들 ID 로 등록하는데, 실행 파일만 돌리면
/// 등록할 대상이 없어서 조용히 실패한다. 그래서 번들인지 먼저 보고,
/// 아니면 토글 자체를 감춘다 — 눌리는데 아무 일도 안 일어나는 스위치가 제일 나쁘다.
@MainActor
enum LoginItem {

    /// 번들로 실행 중인가. `.app` 안에서 돌 때만 참이다.
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
            && Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// 시스템 설정에서 사용자가 직접 승인해야 하는 상태. 안내 문구가 달라진다.
    static var needsApproval: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .requiresApproval
    }

    /// 켜고 끈다. 실패하면 이유를 문자열로 돌려준다 — 조용히 무시하면
    /// 사용자는 껐다고 생각하는데 다음 로그인에 또 뜬다.
    @discardableResult
    static func setEnabled(_ on: Bool) -> String? {
        guard isAvailable else {
            return "앱으로 설치해야 켤 수 있어요 (./build-app.sh --install)"
        }
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
