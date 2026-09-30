import Foundation
import Sparkle

/// 자동 업데이트. 하루 한 번 확인하고, 있으면 받아서 깐다.
///
/// **왜 필요한가.** 이 앱은 메뉴바에 띄워놓고 잊어버리는 물건이다. 그게 컨셉이다 —
/// 안 보고 있어도 자란다. 그런데 그 말은 **고장난 버전을 몇 주씩 쓰고 있어도 모른다**는
/// 뜻이기도 하다. 실제로 저장이 통째로 안 되던 버전이 하루 넘게 돌았고, 만든 사람조차
/// 화분이 안 자라는 걸 보고서야 알았다. 사용자한테 "가끔 brew upgrade 쳐보세요" 라고
/// 말하는 건 답이 아니다.
///
/// **서명.** 이 앱은 Apple Developer ID 가 없고 ad-hoc 서명이라 빌드마다 서명이 바뀐다.
/// Sparkle 2 는 코드 서명이 안 맞아도 **EdDSA(ed25519) 서명이 맞으면** 받아들이므로
/// 이 조합으로 동작한다. 잘못된 EdDSA 는 제대로 거부한다 — 검증이 느슨해지는 게 아니다.
/// 비밀키는 저장소에 없다. 잃어버리면 아무도 업데이트를 못 받으니 따로 백업해 둬야 한다.
@MainActor
final class Updater {
    /// Sparkle 의 표준 컨트롤러. `startingUpdater: true` 면 만들자마자 일정이 돈다.
    ///
    /// `updaterDelegate`·`userDriverDelegate` 는 안 넣는다. 기본 동작(하루 한 번 확인 →
    /// 조용히 받아서 설치)이 정확히 원하는 것이고, 직접 끼어들수록 깨질 자리만 는다.
    private let controller = SPUStandardUpdaterController(startingUpdater: true,
                                                          updaterDelegate: nil,
                                                          userDriverDelegate: nil)

    /// 자동 확인 켜기/끄기. 톱니 메뉴의 토글이 이걸 읽고 쓴다.
    ///
    /// Sparkle 이 제 저장소(UserDefaults)에 들고 있으므로 우리 세이브에 복사해 두지 않는다.
    /// 두 곳에 두면 한쪽만 바뀌어 "껐는데 계속 확인한다"가 된다.
    var automatic: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// 마지막으로 확인한 시각. 메뉴에 한 줄 띄우는 용도.
    var lastCheck: Date? { controller.updater.lastUpdateCheckDate }

    /// 사용자가 직접 눌렀을 때. 최신이면 "최신입니다" 창이 뜬다 —
    /// 자동 확인과 달리 **아무 일도 안 일어나면 안 된다.** 누른 사람은 답을 기대한다.
    func checkNow() {
        controller.updater.checkForUpdates()
    }
}
