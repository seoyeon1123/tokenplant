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
        guard !isRefreshing else { return }
        isRefreshing = true
        let today = DayKey.make(Date())

        Task {
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

            // 한도 조회는 물 적립과 분리해 **뒤에** 돌린다. Keychain·프로세스·네트워크를 타서
            // 실패가 흔하고 느리다 — 여기에 성장을 묶으면 한도를 못 읽는 날 화분이 멈춘다.
            let limits = await LimitsReader.read()
            store.applyLimits(limits)

            lastRefresh = Date()
            isRefreshing = false
        }
    }
}

enum PopoverTab: String, CaseIterable, Identifiable {
    case home, shop, bag, collection
    var id: String { rawValue }
    var label: String {
        switch self {
        case .home: return "홈"
        case .shop: return "상점"
        case .bag: return "가방"
        case .collection: return "컬렉션"
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

            Text(refreshLabel).font(.system(size: 10)).foregroundStyle(.tertiary)

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

    private var refreshLabel: String {
        guard let t = model.lastRefresh else { return "읽는 중" }
        let secs = Int(Date().timeIntervalSince(t))
        return secs < 60 ? "\(secs)초 전" : "\(secs / 60)분 전"
    }
}

/// 홈 탭 — 화분 + 오늘 사용량 + 도구별 분해.
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
            walletLine

            if store.todayRaw == 0 && store.wallet == 0 {
                Text("오늘 아직 쓴 토큰이 없어요. Claude Code 나 Codex 를 쓰면 저절로 자랍니다.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.save.streakDays > 1 {
                Text("연속 \(store.save.streakDays)일 · 물 +\(PlantBalance.streakBonusPercent(days: store.save.streakDays))%")
                    .font(.system(size: 10)).foregroundStyle(.green)
            }
            // 한도 조회 실패는 성장에 영향이 없다. 본문 두 줄을 먹을 일이 아니라 회색 한 줄.
            if let err = model.readError ?? store.limits.note {
                Text(err).font(.system(size: 9)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

        HStack(spacing: 4) {
            if let ratio, let base = store.baselineRate {
                Text(ratio >= 1 ? String(format: "평소의 %.1f배", ratio)
                                : "평소의 \(Int((ratio * 100).rounded()))%")
                    .foregroundStyle(ratio >= 1 ? Color.green : Color.secondary)
                Spacer()
                Text("평소 \(TokenFormat.short(base))").foregroundStyle(.tertiary)
            } else {
                // 표본이 모자라면 퍼센트를 **아예 안 쓴다.** 틀린 82% 는 아무 숫자도 안 쓴 것보다 나쁘다.
                Text("평소를 재는 중 · \(store.baselineDaysCollected)일째")
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(PlantBalance.dailyRawMinDays)일부터").foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 10, design: .monospaced))
    }

    /// 지갑 — **막대 없이 한 줄.** 자세한 건 가방 탭이 맡는다(거기 이미 같은 숫자가 있다).
    ///
    /// "얼마나 찼나"보다 **"뭘 살 수 있나"** 가 실제로 알고 싶은 것이다.
    /// 그리고 다음 목표에서 장식은 뺀다 — 벤치가 제일 싸서 늘 먼저 걸리는데,
    /// 성장에 도움이 안 되는 걸 목표로 걸어주면 모을 이유가 안 된다.
    @ViewBuilder
    private var walletLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text("지갑").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                Text(TokenFormat.short(store.wallet))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(store.wallet > 0 ? Color.blue : Color.secondary)
                Spacer()
            }

            if let now = store.affordableNow {
                Text("지금 \(now.name) 살 수 있어요 · \(store.dayText(store.price(now)))")
                    .font(.system(size: 10)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let goal = store.nextGoal {
                Text("\(goal.item.name)까지 \(TokenFormat.short(goal.short)) 더 · \(store.dayText(goal.short))")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.todayWindowBonus > 0 {
                Text("한도 창 소진 보너스 +\(TokenFormat.short(store.todayWindowBonus))")
                    .font(.system(size: 10)).foregroundStyle(.orange)
            }
        }
        .padding(.top, 3)
    }

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
