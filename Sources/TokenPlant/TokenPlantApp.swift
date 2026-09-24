import SwiftUI
import AppKit

/// 메뉴바 앱은 **창이 하나도 없는 게 정상 상태**다.
///
/// AppKit 의 기본값은 그 반대다 — 마지막 창이 닫히면 앱을 종료한다. 보통 앱은 그게 맞지만
/// 여기서는 정원 창을 열었다 닫는 순간 앱이 통째로 사라진다. 크래시가 아니라 **정상 종료**라
/// 크래시 리포트도 안 남고, 그래서 화면만 봐서는 "그냥 꺼졌다"로 보인다.
///
/// SwiftUI 는 델리게이트를 안 끼우면 아무것도 대신 해주지 않는다 — AppKit 기본값이 그대로 먹는다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// 메뉴바 앱. 실제 로그(`~/.claude/projects`, `~/.codex/sessions`)를 읽어 물로 환산한다.
///
/// 포크에 합칠 때는 이 파일과 `UsageReader.swift` 만 버린다 —
/// `PokeTokenBarApp` 의 `updateCompanion()` 자리에
/// `store.update(todayUsageByProvider:todayDate:)` 를 꽂고 나머지 UI 는 그대로 쓴다.
@main
@MainActor
struct TokenPlantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverRoot(model: model)
        } label: {
            // 메뉴바는 전용 16×16 스프라이트다 — 24px 화분을 줄이면 정수배가 안 맞아 흐려진다.
            Image(nsImage: PixelSpriteImage.make(
                grid: MenuBarSprites.grid(stageIndex: model.store.pot?.stageIndex ?? 0),
                species: model.store.pot?.isShiny == true
                    ? PlantSpecies.shinyPalette(of: model.store.species)
                    : model.store.species,
                wilt: model.store.wilt,
                scale: 1))
            // 메뉴바 숫자는 원시 토큰을 유지한다 — 이미 익숙한 값이고, 물은 팝오버에서 본다.
            Text(TokenFormat.short(model.store.todayRaw))
        }
        .menuBarExtraStyle(.window)

        Window("정원", id: AppModel.gardenWindowID) {
            GardenView(store: model.store)
        }
        .defaultSize(width: 700, height: 480)
    }
}

/// 갱신 루프. 로그 파싱은 IO 라 메인 액터 밖에서 돌린다.
@MainActor
@Observable
final class AppModel {
    static let gardenWindowID = "garden"

    let store = PlantStore()
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    private(set) var readError: String?
    var tab: PopoverTab = .home

    /// 실제 등록 상태를 그대로 비춘다. 별도 플래그로 들고 있으면 사용자가 시스템 설정에서
    /// 끈 걸 앱이 모르고 계속 "켜짐"으로 보여준다.
    private(set) var launchAtLogin = LoginItem.isEnabled
    private(set) var loginItemError: String?

    private var ticker: Task<Void, Never>?

    // 한도 조회는 사용량 로그 읽기와 **주기가 달라야 한다.**
    //
    // 로그는 로컬 파일이라 30초마다 읽어도 공짜지만, 한도는 Anthropic usage 엔드포인트를
    // 때리고(네트워크) codex 는 `app-server` 프로세스를 띄운다. 둘을 같은 30초에 묶어뒀더니
    // 하루 2,880번을 보내 **429(조회 제한)** 를 받았고, 화면에는 "한도 조회가 제한됐어요"만
    // 남았다. 5시간 창의 사용률에 30초 해상도는 아무 의미가 없다.
    /// 지금 갱신이 언제 시작됐나. **감시견용이다.**
    ///
    /// `isRefreshing` 은 래치인데 끝에서만 풀렸다. 한 번 걸리면 이후 모든 갱신이
    /// 첫 줄에서 되돌아가고 앱이 조용히 죽는다 — 화면은 멀쩡한 숫자를 계속 보여주므로
    /// 아무도 모른다. 실제로 그렇게 하루를 잃었다(세이브가 15:06 에서 멈춰 있었다).
    private var refreshStartedAt: Date?
    /// 이만큼 붙잡혀 있으면 놓아준다. 30초 주기의 세 배 — 느린 디스크에 걸려도 넉넉하다.
    private static let refreshWatchdog: TimeInterval = 90

    private var lastLimitsAt: Date?
    /// 429 뒤 쉬는 시간. 성공하면 0 으로 돌아간다.
    private var limitsBackoff: TimeInterval = 0
    /// 평상시 주기 5분 · 제한을 받으면 10분부터 배로 늘려 최대 1시간.
    private static let limitsInterval: TimeInterval = 300
    private static let limitsFirstBackoff: TimeInterval = 600
    private static let limitsMaxBackoff: TimeInterval = 3600

    /// 지금 한도를 읽어도 되는가. 첫 실행은 무조건 읽는다.
    private var shouldReadLimits: Bool {
        guard let last = lastLimitsAt else { return true }
        return Date().timeIntervalSince(last) >= max(Self.limitsInterval, limitsBackoff)
    }

    func setLaunchAtLogin(_ on: Bool) {
        loginItemError = LoginItem.setEnabled(on)
        launchAtLogin = LoginItem.isEnabled
    }

    init() {
        // 30초마다. 로그가 그보다 자주 바뀌지도 않고, 더 짧게 두면 배터리만 먹는다.
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func refresh() {
        // 붙잡힌 지 오래됐으면 놓아준다. 멈춘 갱신 하나가 앱 전체를 영원히 멈추는 것보다
        // 같은 일을 두 번 하는 게 싸다(`store.update` 는 프로바이더 기준값으로 델타를
        // 재므로 두 번 들어와도 이중 적립이 안 된다).
        if isRefreshing, let started = refreshStartedAt,
           Date().timeIntervalSince(started) > Self.refreshWatchdog {
            isRefreshing = false
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshStartedAt = Date()
        let today = DayKey.make(Date())

        Task {
            // 어느 경로로 빠져나가도 래치를 푼다.
            defer { isRefreshing = false }

            // 설치 직후 딱 한 번, 과거 14일을 거슬러 읽어 "하루가 얼마인가"를 먼저 잡는다.
            // 이게 없으면 첫 며칠 동안 가격표가 남의 기본값으로 환산된다.
            if store.needsBackfill {
                let history = await Task.detached(priority: .utility) {
                    UsageReader.readRecent(days: PlantBalance.dailyRawWindow, today: today)
                }.value
                store.backfillHistory(history)
            }

            let snapshot = await Task.detached(priority: .utility) {
                UsageReader.readToday(today)
            }.value

            store.update(todayUsageByProvider: snapshot.byProvider, todayDate: today)
            readError = snapshot.note
                ?? (snapshot.byProvider.isEmpty && snapshot.skippedFiles > 0
                    ? "로그 \(snapshot.skippedFiles)개를 읽지 못했어요" : nil)

            lastRefresh = Date()
        }

        // 한도 조회는 **따로 돈다.** 주석에는 "성장을 묶으면 안 된다"고 적어놓고
        // 같은 Task 안에 순서대로 넣어뒀었다 — 그러면 묶인 것이다. codex 프로세스가
        // 한 번 안 끝나면 그 뒤의 `isRefreshing = false` 까지 막혀서 화분이 멈춘다.
        // 물길과 한도는 서로를 기다리지 않아야 한다.
        Task { await refreshLimits() }
    }

    /// 한도 창 조회. 실패해도 성장에는 아무 영향이 없다.
    private func refreshLimits() async {
        guard shouldReadLimits else { return }
        lastLimitsAt = Date()
        let limits = await LimitsReader.read()
        store.applyLimits(limits)
        limitsBackoff = limits.rateLimited
            ? min(max(Self.limitsFirstBackoff, limitsBackoff * 2), Self.limitsMaxBackoff)
            : 0
    }
}

enum PopoverTab: String, CaseIterable, Identifiable {
    case home, shop, bag, collection
    var id: String { rawValue }
    var label: String {
        switch self {
        // 이름을 한 세계로 묶는다. 예전엔 홈(웹) · 상점(게임) · 가방(RPG) · 컬렉션(외래어)로
        // 결이 다 달랐다. `case` 이름(bag/collection)은 그대로 둔다 — 화면 글자만 바꾼다.
        case .home: return "화분"
        case .shop: return "상점"
        case .bag: return "창고"
        case .collection: return "도감"
        }
    }
}

/// 팝오버 루트 — 탭 네 개. 기존 앱 구조를 그대로 따른다.
struct PopoverRoot: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var store: PlantStore { model.store }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            tabBar

            // 탭 내용만 스크롤한다. 탭바와 푸터는 늘 같은 자리에 있어야
            // 지갑과 톱니를 찾으러 스크롤할 일이 없다.
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    switch model.tab {
                    case .home:
                        HomeTab(model: model)
                    case .shop:
                        ShopView(store: store)
                    case .bag:
                        BagView(store: store)
                    case .collection:
                        CollectionView(store: store) {
                            // LSUIElement 앱은 Dock 에 없어서 창을 열어도 뒤에 뜬다 —
                            // 눌렀는데 아무 일도 안 일어난 것처럼 보인다. 먼저 앱을 앞으로 올린다.
                            NSApp.activate()
                            openWindow(id: AppModel.gardenWindowID)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            Divider()
            footer
        }
        .padding(13)
        // **높이를 고정한다.** 탭마다 내용 길이가 달라서 높이를 열어두면 패널이
        // 표시된 **뒤에** 커지는데, 그러면 macOS 가 위치를 다시 안 잡아서
        // 메뉴바에서 떨어진 자리에 뜨고 늘어난 부분은 배경이 안 칠해진 채로 남는다.
        .frame(width: 320, height: 440)
        .background(MenuPanelBackground().ignoresSafeArea())
        .task { model.refresh() }
    }

    private var tabBar: some View {
        HStack(spacing: 3) {
            ForEach(PopoverTab.allCases) { t in
                Button {
                    model.tab = t
                } label: {
                    Text(t.label)
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(model.tab == t ? Color.accentColor : Color.clear)
                )
                .foregroundStyle(model.tab == t ? Color.white : Color.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.isRefreshing)

            // 오래 멈춰 있으면 **눈에 띄어야** 한다. 흐린 회색 "1523분 전" 은 아무도 안 읽는다.
            Text(refreshLabel)
                .font(.system(size: 10, weight: isStale ? .medium : .regular))
                .foregroundStyle(isStale ? Color.orange : Color.secondary.opacity(0.6))
                .help(isStale ? "갱신이 멈춰 있어요. 새로고침을 눌러보세요." : "마지막으로 로그를 읽은 시각")

            Spacer()

            // 지갑은 앱 어느 탭에 있든 보여야 한다 — 상점 값이 전부 이 숫자로 매겨져 있다.
            Label(TokenFormat.short(store.wallet), systemImage: "bag.fill")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(store.wallet > 0 ? Color.blue : Color.secondary)

            settingsMenu
        }
    }

    /// 톱니 메뉴 — 자동 실행과 종료.
    ///
    /// `swift run` 으로 띄우면 자동 실행 항목이 아예 안 나온다. 눌러도 안 되는 스위치를
    /// 보여주느니 없는 게 낫다 — 대신 왜 없는지 한 줄 적어 둔다.
    private var settingsMenu: some View {
        Menu {
            if LoginItem.isAvailable {
                Toggle("로그인 시 자동 실행", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }))
                if LoginItem.needsApproval {
                    Text("시스템 설정 → 일반 → 로그인 항목에서 허용해 주세요")
                }
                if let err = model.loginItemError {
                    Text(err)
                }
            } else {
                Text("자동 실행은 앱으로 설치해야 켤 수 있어요")
                Text("터미널에서 ./build-app.sh --install")
            }
            Divider()
            Button("종료") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// 5분 넘게 안 읽혔으면 뭔가 잘못된 것이다 — 주기는 30초다.
    private var isStale: Bool {
        guard let t = model.lastRefresh else { return false }
        return Date().timeIntervalSince(t) > 300
    }

    /// 분 단위로만 찍으면 "1523분 전" 이 된다. 읽을 수 없는 숫자는 경고가 아니다.
    private var refreshLabel: String {
        guard let t = model.lastRefresh else { return "읽는 중" }
        let secs = Int(Date().timeIntervalSince(t))
        if secs < 60 { return "\(secs)초 전" }
        if secs < 3_600 { return "\(secs / 60)분 전" }
        if secs < 86_400 { return "\(secs / 3_600)시간 전" }
        return "\(secs / 86_400)일 전"
    }
}

/// 화분 탭 — 화분 + 오늘 사용량 + 도구별 분해.
struct HomeTab: View {
    let model: AppModel

    private var store: PlantStore { model.store }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if store.slotCount == 2 {
                // 화분 슬롯을 사면 그루가 둘이 된다. 물은 나뉘지 않고 **양쪽에 똑같이** 들어간다 —
                // 그래서 아이템 버튼도 한 벌이면 된다.
                HStack(alignment: .top, spacing: 10) {
                    PotView(store: store, slot: 0, compact: true)
                    Divider().frame(height: 165)
                    PotView(store: store, slot: 1, compact: true)
                }
                Text(store.statusLine)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // 축소판은 자기 퀵 슬롯을 안 그린다 — 물이 양쪽에 똑같이 들어가므로
                // 두 벌이면 같은 걸 두 번 살 수 있다고 오해한다.
                PotQuickSlots(store: store)
            } else {
                PotView(store: store)
            }
            Divider()
            todaySection
        }
    }

    /// 오늘 블록 — 게이지가 **누적**을 맡으니 여기는 **오늘**과 **지금**만 말한다.
    ///
    /// 큰 숫자를 mL 에서 토큰으로 바꿨다. 이유 둘:
    ///  1. 바로 위 게이지가 이미 mL 을 쓰고 있어 같은 단위가 화면에 두 번 나왔다.
    ///  2. "내가 얼마나 했나"의 단위는 토큰이다 — mL 은 식물 쪽 단위고,
    ///     메뉴바에 뜨는 숫자가 토큰이라 따로 배울 것도 없다.
    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("오늘 쓴 토큰")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)

            HStack(alignment: .firstTextBaseline) {
                Text(TokenFormat.short(store.todayRaw))
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                Spacer()
                // mL 은 "내가 쓴 것 → 식물이 받은 것" 다리 역할만 한다. 작게 옆으로.
                Text("물 +\(store.todayWater.formatted()) mL")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            baselineBar
            footnote
        }
    }

    /// 오늘 ÷ 평소. **막대는 이 블록에서 여기 하나뿐이다** —
    /// 지갑에도 막대를 붙였더니 뜻이 다른 두 막대가 똑같이 생겨서 구분이 안 됐다.
    @ViewBuilder
    private var baselineBar: some View {
        let ratio = store.todayVsBaseline
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill((ratio ?? 0) >= 1 ? Color.green.opacity(0.7) : Color.accentColor.opacity(0.65))
                    .frame(width: geo.size.width * 0.7 * min(1.0 / 0.7, ratio ?? 0))
                // 100% 눈금. 넘긴 날 "얼마나 넘겼나"가 이 선으로 읽힌다.
                if ratio != nil {
                    Rectangle().fill(Color.secondary)
                        .frame(width: 1.5)
                        .offset(x: geo.size.width * 0.7)
                }
            }
        }
        .frame(height: 5)

        .help(baselineTip)
    }

    /// 막대의 숫자는 **툴팁에만** 둔다.
    ///
    /// 본문에 「평소의 0%」와 「평소 255.0M」 두 줄로 있었는데 둘 다 문제였다.
    /// 777K 는 255M 의 0.3% 인데 반올림해서 **0%** 로 찍혔다 — 토큰을 썼는데 0% 라고
    /// 말하는 건 틀린 데다 기운 빠지는 말이다. 그리고 이 탭이 답할 질문은
    /// "내 식물이 어떤가"이지 "내가 평소 대비 몇 %인가"가 아니다.
    /// 막대는 눈으로 읽히니 남기고, 숫자는 궁금한 사람만 보게 한다.
    private var baselineTip: String {
        guard let ratio = store.todayVsBaseline, let base = store.baselineRate else {
            return "평소를 재는 중 — \(store.baselineDaysCollected)일째 (\(PlantBalance.dailyRawMinDays)일부터 나와요)"
        }
        let pct = ratio >= 1 ? String(format: "%.1f배", ratio)
                             : String(format: "%.1f%%", ratio * 100)
        return "평소 \(TokenFormat.short(base)) 대비 오늘 \(pct)"
    }

    /// 막대 아래 **한 줄뿐.** 지금 제일 할 말 하나만 고른다.
    ///
    /// 예전엔 여기에 지갑·구매가능·다음목표·연속일·한도오류가 줄줄이 쌓여 일곱 줄이었다.
    /// 지갑은 푸터에 항상 떠 있어 중복이었고, 구매 관련 두 줄은 상점 탭의 일이며,
    /// 한도 조회 실패는 사용자가 할 수 있는 게 없다(성장에도 영향이 없다).
    @ViewBuilder
    private var footnote: some View {
        if store.freeDraws > 0 {
            Text("선물 도착 · 상점에서 열어보세요")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(Color.orange)
        } else if store.save.streakDays > 0 {
            // 세 가지를 **한 줄에** 넣는다: 며칠째 · 지금 받는 보너스 · 다음 선물까지.
            // 따로 두면 줄이 세 개가 되는데, 셋 다 "이어서 쓰고 있다"는 한 가지 이야기다.
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 9)).foregroundStyle(Color.orange)
                Text("\(store.save.streakDays)일째").font(.system(size: 10, weight: .medium))
                let bonus = PlantBalance.streakBonusPercent(days: store.save.streakDays)
                if bonus > 0 {
                    Text("물 +\(bonus)%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.green)
                }
                Spacer(minLength: 4)
                if let left = store.daysToNextGift {
                    Text("다음 선물까지 \(left)일")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            .help("토큰을 쓴 날이 이어질수록 성장에 보너스가 붙어요. 하루 빠지면 처음부터 다시 셉니다.")
        } else if store.todayRaw == 0 {
            Text("Claude Code 나 Codex 를 쓰면 저절로 자랍니다.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // 지갑 줄은 여기서 뺐다. 푸터에 항상 떠 있어서(`🛍 109.8M`) 같은 숫자가 두 번 나왔고,
    // 거기 딸려 있던 "지금 N 살 수 있어요"·"거름까지 N 더"는 상점 탭의 일이다.

}

/// 큰 숫자를 메뉴바에 맞게 줄인다 — 180.4M 처럼.
enum TokenFormat {
    static func short(_ n: Int) -> String {
        let v = Double(n)
        if v >= 1_000_000_000 { return String(format: "%.2fB", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.0fK", v / 1_000) }
        return "\(n)"
    }
}
