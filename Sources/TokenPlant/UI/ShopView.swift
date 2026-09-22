import SwiftUI

/// 상점 탭. 값은 전부 **원시 토큰** — 메뉴바에 뜨는 그 숫자로 산다.
///
/// 화분은 토큰만 써도 자란다. 여기서 사는 건 **가속**이고, 사도 이미 자란 건 줄지 않는다.
/// 사면 가방으로 들어간다(즉시 발동 아님) — 언제 쓰느냐가 값어치를 좌우하기 때문이다.
struct ShopView: View {
    let store: PlantStore
    @State private var flash: String?
    /// 방금 뽑아서 나온 장식. 결과를 **글씨 한 줄이 아니라 그림으로** 보여주는 데 쓴다.
    @State private var revealed: String?
    /// 같은 장식을 연달아 뽑아도 연출이 다시 돌게 한다 — 값만 보면 두 번째가 조용하다.
    @State private var revealSeq = 0

    private let categories = ["성장", "씨앗", "정원", "장식"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(categories, id: \.self) { cat in
                        let items = ShopItem.sortedByPrice.filter { $0.category == cat }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(cat)
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .padding(.bottom, 3)
                                ForEach(items, id: \.self) { row($0) }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 300)

            if let f = flash {
                Text(f).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    /// 머리말이 답해야 하는 건 잔액이 아니라 **기준**이다.
    ///
    /// `152 mL` 만 띄우면 20,000이 하루치인지 한 달치인지 알 수 없고, 그러면 상점은
    /// "영영 못 사는 곳"으로 읽힌다. 하루 유입을 같이 적어야 모든 가격이 시간으로 읽힌다.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(TokenFormat.short(store.wallet))
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    Text("토큰").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .foregroundStyle(Color.blue)
                Spacer()
                // 사도 성장은 안 줄어든다는 걸 여기서 못 박아둔다 — 이게 이 상점의 성격이다.
                Text("사도 자란 건 안 줄어요")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            HStack(spacing: 4) {
                Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 8))
                // 측정값인지 기본값인지 구분해 쓴다 — 남의 평균을 자기 값인 척 보여주면 안 된다.
                Text(store.dailyRateIsMeasured
                     ? "하루 평균 \(TokenFormat.short(store.dailyRate)) 씁니다 (최근 14일)"
                     : "하루 \(TokenFormat.short(store.dailyRate)) 기준 (측정 중 — 3일 지나면 내 값으로)")
                    .font(.system(size: 9))
            }
            .foregroundStyle(.tertiary)

            // 지갑이 **왜 이 숫자인지** 여기서 풀어준다.
            //
            // 지갑은 오늘치가 아니라 설치 후 쌓인 잔액인데, 그게 화면에 안 적혀 있으면
            // "오늘 127M 썼는데 왜 지갑이 95M 이지?" 에서 멈춘다. 뺄셈을 그대로 보여주면
            // 그 자리에서 풀린다 — 차액이 곧 지금까지 쓴 값이다.
            if store.earnedTotal > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "equal.circle").font(.system(size: 8))
                    Text("번 것 \(TokenFormat.short(store.earnedTotal))")
                    Text("−").foregroundStyle(.tertiary)
                    Text("쓴 것 \(TokenFormat.short(store.spentTotal))")
                    Text("=").foregroundStyle(.tertiary)
                    Text(TokenFormat.short(store.wallet)).foregroundStyle(Color.blue)
                }
                .font(.system(size: 9, design: .monospaced))
                .help("지갑은 오늘치가 아니라 설치 후 쌓인 잔액이에요. 자정에 초기화되지 않습니다.")
                .foregroundStyle(.tertiary)
            }
        }
    }

    private func row(_ item: ShopItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            itemLine(item)
            // 뽑기는 **모으는 것**이라 진행도가 같이 보여야 한다.
            // 뭘 모으는 중인지 안 보이면 한 번 누르고 끝난다.
            if item == .decorBox { decorCollection }
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
        }
    }

    private func itemLine(_ item: ShopItem) -> some View {
        let state = PlantEngine.canBuy(item, store.save)
        return HStack(alignment: .top, spacing: 8) {
            ShopItemIcon(item: item, pixelSize: 1, dimmed: false)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(item.name).font(.system(size: 12, weight: .medium))
                    if store.save.count(item) > 0 {
                        Text("×\(store.save.count(item))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(effectText(item))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            priceColumn(item, state: state)
        }
    }

    // MARK: 장식 뽑기 — **누르는 순간에 결과가 있어야 한다**
    //
    // 처음 만든 건 뽑기가 아니라 영수증이었다: 상점에서 사고 → 가방 탭으로 옮겨서 →
    // 「사용」을 누르면 → 회색 글씨 한 줄. 상자도 안 열리고 장식 그림도 안 보인다.
    // "뭔지 모르겠다"는 말이 나온 게 당연하다.
    //
    // 셋을 고쳤다. 한 번에 뽑고(탭 이동 없음), 나온 걸 **그림으로** 보여주고,
    // 아직 없는 것을 실루엣으로 깔아 "저건 뭐지"를 남긴다.

    private var gachaLeft: [String] {
        DecorIcons.gachaKeys.filter { !store.save.decorations.contains($0) }
    }

    private var decorCollection: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let key = revealed {
                HStack(spacing: 7) {
                    DecorIcon(key: key, pixelSize: 2)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(DecorIcons.name(key))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.orange)
                        Text("정원에 놓았어요")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                .id(revealSeq)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }

            HStack(spacing: 2) {
                ForEach(DecorIcons.gachaKeys, id: \.self) { key in
                    let mine = store.save.decorations.contains(key)
                    DecorIcon(key: key, pixelSize: 1, silhouette: !mine)
                        .help(mine ? DecorIcons.name(key) : "아직 안 나온 장식")
                }
                Spacer(minLength: 4)
                Text("\(DecorIcons.gachaKeys.count - gachaLeft.count) / \(DecorIcons.gachaKeys.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 24)
    }

    /// 사고 여는 것을 **한 번에** 한다. 가방을 거치면 그게 곧 뽑기가 아니게 된다.
    private func drawDecor() {
        guard store.buy(.decorBox) == .ok else { return }
        guard case .ok = store.use(.decorBox), let key = store.lastDecorFound else { return }
        flash = nil
        revealSeq += 1
        withAnimation(.spring(response: 0.34, dampingFraction: 0.58)) { revealed = key }
    }

    /// 오른쪽 칸 = **값표**다. 모든 줄이 같은 모양이고, 바뀌는 건 살 수 있느냐뿐이다.
    ///
    ///     749.2M     ← 값 (파랑 = 지금 살 수 있음 / 회색 = 아직)
    ///     3.0일치     ← 내 하루 유입으로 며칠치인가
    ///     [구매]      ← 살 수 있을 때만
    ///
    /// 여기까지 세 번 고쳤고, 앞의 둘은 **내 해석을 값자리에 올려놓은** 게 문제였다.
    ///
    ///   1차: 값 · 며칠치 · "오늘 안에" · "113.0M 부족" — 숫자 넷, 라벨 없음.
    ///        249.7M 과 113.0M 중 뭐가 값인지 "부족"을 읽어야 알 수 있었다.
    ///   2차: "2일 더 쓰면" 을 크게, 값을 작게 — 줄마다 생김새가 달라져서 훑을 수가 없고,
    ///        무엇보다 **추정치를 값자리에 올렸다.** 14일 평균으로 만든 예측이라 날마다 바뀌는데,
    ///        제일 큰 글씨가 그거면 앱이 못 지킬 약속을 계속 하는 셈이다.
    ///   3차(지금): 상점은 값을 보여주는 곳이다. 값은 **사실**이고 며칠치는 그 사실의 단위다.
    ///        "언제 살 수 있나"는 예측이라 화면에서 내리고 툴팁으로 옮겼다.
    ///
    /// 기준이 화면에 없어서 큰 숫자가 안 읽히는 문제는 그대로 해결된다 —
    /// 머리말에 지갑(136.7M)과 하루 평균(249.7M)이 이미 있고, 값이 **지갑과 같은 단위**라
    /// 바로 견줄 수 있다. 거기에 "3.0일치"가 붙으면 크기가 시간으로도 읽힌다.
    @ViewBuilder
    private func priceColumn(_ item: ShopItem, state: PurchaseResult) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            switch state {
            case .alreadyOwned:
                Text("보유 중").font(.system(size: 10, weight: .medium)).foregroundStyle(.green)

            case .ok where item == .decorBox && gachaLeft.isEmpty:
                priceLines(item, affordable: true)
                // 다 모았는데 버튼이 살아 있으면 지갑만 나간다.
                Text("다 모았어요").font(.system(size: 10, weight: .medium)).foregroundStyle(.green)

            case .insufficientBalance(let short):
                // 값은 같은 자리에 그대로, 색만 회색으로 내린다. 버튼이 없는 것 자체가
                // "아직 못 산다"는 신호다 — 거기에 "N 부족"까지 쓰면 그 숫자가 커 보여서
                // 오히려 "영영 못 산다"로 읽혔다. 언제 살 수 있는지는 툴팁에 있다.
                priceLines(item, affordable: false)
                    .help("\(waitText(short)) 살 수 있어요 (하루 평균 \(TokenFormat.short(store.dailyRate)) 기준)")

            case .ok:
                priceLines(item, affordable: true)
                Button(item == .decorBox ? "뽑기" : "구매") {
                    if item == .decorBox {
                        drawDecor()
                    } else {
                        _ = store.buy(item)
                        if item.isDecoration {
                            flash = "\(item.name) — 정원에 놓았어요"
                        } else if item.isPassive {
                            flash = "\(item.name) — 바로 적용됐어요"
                        } else {
                            flash = "\(item.name) — 가방에 담았어요"
                        }
                    }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    /// 값 두 줄. 살 수 있든 없든 **같은 자리에 같은 크기**로 둔다 —
    /// 줄마다 생김새가 바뀌면 열 품목을 훑을 수가 없다.
    private func priceLines(_ item: ShopItem, affordable: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(TokenFormat.short(store.price(item)))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(affordable ? Color.blue : Color.secondary)
            Text(store.dayText(store.price(item)))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    /// "3시간 더 쓰면" / "하루 더 쓰면" / "2일 더 쓰면" — 부족분을 **할 일**로 번역한다.
    ///
    /// 이건 예측이라 **툴팁에만** 쓴다. 값자리에 올렸더니 두 가지가 나빠졌다:
    /// 줄마다 생김새가 달라져 훑을 수 없었고, 14일 평균으로 만든 추정이 제일 큰 글씨가 됐다.
    ///
    /// 문구 자체도 두 번 틀렸다. "2일 더"는 뭘 더 하라는 건지 안 적혀 있고,
    /// "2일 뒤"는 **시간이 지나면 저절로 생기는 것처럼** 읽힌다(실제로 그렇게 읽혔다).
    /// 지갑은 시계가 아니라 토큰을 써야 찬다 — 이틀 동안 안 켜면 이틀 뒤에도 그대로다.
    private func waitText(_ short: Int) -> String {
        let d = store.days(forRaw: short)
        if d < 0.5 {
            let hours = Int((d * 24).rounded())
            return hours <= 1 ? "조금만 더 쓰면" : "\(hours)시간 더 쓰면"
        }
        if d < 1.5 { return "하루 더 쓰면" }
        return "\(Int(d.rounded()))일 더 쓰면"
    }

    /// 성장 셋은 **같은 값을 물로 샀을 때와 비교**해서 보여준다.
    ///
    /// 회수량만 적으면 비교를 사용자가 해야 한다. 거름은 꾸준히 쓸 때만, 영양제는
    /// 초반에만 이득인데 — 그게 두 품목의 성격이라 숨기지 않고 손해면 손해라고 쓴다.
    /// 기준을 "물"로 잡은 이유: 셋 중 제일 단순하고, 언제 사도 값이 같아서 자가 없다.
    private func effectText(_ item: ShopItem) -> String {
        switch item {
        case .water:
            // "언제 써도 같아요" 는 사실이 아니었다 — `applyWater` 가
            // 스트릭·거름 보너스를 곱해서, 같은 물 한 개가 날마다 다른 양으로 들어간다.
            // (가방 문구는 보너스를 먹인 뒤 값을 찍어서 둘이 서로 달랐다.)
            // 여기 적는 건 보너스 전 기본량이고, 하루 상한도 같이 알려준다.
            return "기본 +\(store.waterML.formatted()) mL"
                 + " · 하루 \(PlantBalance.dailyWaterUses)번까지 (보너스만큼 더 들어가요)"

        case .fertilizer:
            let left = store.save.fertilizerDaysLeft(now: Date())
            if left > 0 {
                return "\(PlantBalance.fertilizerDays)일간 +\(PlantBalance.fertilizerBonusPercent)% · 사용 중 \(left)일"
            }
            // 7일간 들어올 물의 25% 가 회수량. 토큰을 계속 써야 성립한다.
            // 상수 환산이 아니라 기록에서 읽는다 — 안 그러면 회수량이 절반으로 보인다.
            let dailyML = store.measuredDailyWater ?? (store.dailyRate / PlantBalance.rawPerML)
            let back = dailyML * PlantBalance.fertilizerDays * PlantBalance.fertilizerBonusPercent / 100
            return "\(PlantBalance.fertilizerDays)일간 들어오는 물 +\(PlantBalance.fertilizerBonusPercent)%"
                 + " · 약 +\(back.formatted()) mL \(vsWater(item, back))"

        // 한 그루에 한 번이라는 걸 **살 때** 알려야 한다. 두 개를 사도 이번 사이클엔 못 쓴다.
        case .nutrient:
            // 퍼센트를 글로 박으면 상수를 고칠 때 화면만 옛말이 된다 —
            // 실제로 20% → 10% 로 내린 뒤 화면은 −20% 라고 계속 말하고 있었고,
            // 같은 문장 안의 mL 값은 10% 로 계산돼서 스스로 모순이었다.
            let pct = Nutrient.reducePercent
            guard let p = store.pot else { return "남은 거리 −\(pct)%" }
            let back = Nutrient.water(currentWater: p.water, cycle: p.cycleWater)
            return "남은 거리 −\(pct)% · 한 그루에 한 번"
                 + " · 지금 +\(back.formatted()) mL \(vsWater(item, back))"

        case .premiumSeed: return "다음 씨앗 희귀 이상 확정"
        case .legendarySeed: return "다음 씨앗 전설 확정"
        case .shinyCharm: return "반짝 확률 1/128 → 1/32 (영구)"
        case .potSlot: return "동시에 두 그루 (영구)"
        // 장식은 효과가 없다. 그걸 숨기지 않고 그대로 쓴다 —
        // 효과가 있는 줄 알고 사면 그 값이 그냥 사라진 게 된다.
        case .bench: return "정원에 벤치를 놓아요 (효과 없음)"
        case .feeder: return "정원에 새 모이통을 놓아요 (효과 없음)"
        case .lantern: return "정원에 석등을 놓아요 (효과 없음)"
        // 몇 개가 남았는지를 적는다. "랜덤"만 쓰면 이미 다 모은 사람이 또 산다.
        case .decorBox:
            let left = gachaLeft.count
            return left > 0 ? "누르면 아직 없는 장식 하나가 바로 나와요 (중복 없음)"
                            : "장식을 다 모았어요"
        }
    }

    /// 같은 값으로 물을 샀다면 얼마였는지와 견준다. 손해면 손해라고 쓴다 —
    /// 사고 나서 알게 하면 안 된다.
    private func vsWater(_ item: ShopItem, _ back: Int) -> String {
        let waterCount = item.priceDays / ShopItem.water.priceDays
        let alt = Int(waterCount * Double(store.waterML))
        let margin = back - alt
        return margin >= 0 ? "(물보다 +\(margin.formatted()))"
                           : "(물보다 −\(abs(margin).formatted()) 손해)"
    }
}

/// 가방 탭. 개수·지속 효과 남은 일수·씨앗 재고.
struct BagView: View {
    let store: PlantStore
    @State private var flash: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("소모품") {
                // 장식 뽑기는 상점에서 사는 즉시 열린다(`drawDecor`) — 가방을 거치지 않는다.
                // 걸러내지 않으면 영원히 `×0` 인 줄과 영원히 눌리지 않는 「사용」 버튼이 남는다.
                let items = ShopItem.allCases.filter {
                    !$0.isPassive && $0.seedGuarantee == nil && $0 != .decorBox
                }
                ForEach(items, id: \.self) { consumableRow($0) }
            }

            if store.save.fertilizerActive(now: Date()) {
                section("지속 중") { fertilizerRow }
            }

            section("씨앗") {
                ForEach([ShopItem.premiumSeed, .legendarySeed], id: \.self) { seedRow($0) }
                if let g = store.save.pendingSeedGuarantee {
                    Text("다음 씨앗 \(g.label) 확정 예약됨")
                        .font(.system(size: 10)).foregroundStyle(.green)
                }
            }

            if !store.save.passives.isEmpty {
                section("보유형") {
                    ForEach(store.save.passives, id: \.self) { raw in
                        if let item = ShopItem(rawValue: raw) {
                            HStack {
                                ShopItemIcon(item: item, pixelSize: 1)
                                Text(item.name).font(.system(size: 11))
                                Spacer()
                                Text(item.isDecoration ? "정원에 놓임" : "적용 중")
                                    .font(.system(size: 9)).foregroundStyle(.green)
                            }
                        }
                    }
                }
            }

            if let f = flash {
                Text(f).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
            content()
        }
    }

    private func consumableRow(_ item: ShopItem) -> some View {
        let n = store.save.count(item)
        let blocked = blockReason(item)
        return HStack(spacing: 8) {
            ShopItemIcon(item: item, pixelSize: 1, dimmed: n == 0)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(item.name) ×\(n)")
                    .font(.system(size: 11, weight: n > 0 ? .medium : .regular))
                    .foregroundStyle(n > 0 ? .primary : .secondary)
                if let b = blocked {
                    Text(b).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button("사용") {
                let r = store.use(item)
                switch r {
                case .ok(let w):
                    if let key = store.lastDecorFound {
                        flash = "\(DecorIcons.name(key)) 이(가) 나왔어요 — 컬렉션 탭 정원에 놓였어요"
                    } else {
                        flash = w > 0 ? "\(item.name) — 물 +\(w.formatted()) mL" : "\(item.name) 사용"
                    }
                case .noEffect(let why): flash = why
                case .notOwned: flash = "가진 게 없어요"
                }
            }
            .controlSize(.small)
            .disabled(n == 0 || blocked != nil)
        }
        .padding(.vertical, 2)
    }

    /// 쓸 수 없으면 이유를 적는다 — 회색 버튼만 두면 사용자가 왜인지 모른다.
    private func blockReason(_ item: ShopItem) -> String? {
        guard store.save.count(item) > 0 else { return nil }
        switch item {
        case .nutrient:
            guard let p = store.pot else { return nil }
            return Nutrient.water(currentWater: p.water, cycle: p.cycleWater) > 0 ? nil : "이미 다 자랐어요"
        case .fertilizer:
            // 중첩이 아니라 기간 갱신이라, 돌고 있는 동안 쓰면 남은 날이 날아간다.
            // "이미 돌고 있어요" 로 막았더니 사도 바로 못 쓰는 품목이 됐다.
            // 이제 이어 붙으므로, 천장(3주)에 닿았을 때만 막는다.
            return store.fertilizerDaysLeft >= PlantBalance.fertilizerMaxDays
                ? "\(PlantBalance.fertilizerMaxDays)일치까지 차 있어요" : nil
        default:
            return nil
        }
    }

    private var fertilizerRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("거름 +\(PlantBalance.fertilizerBonusPercent)%").font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(store.save.fertilizerDaysLeft(now: Date()))일 남음")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule().fill(Color.green.opacity(0.7))
                        .frame(width: geo.size.width
                               * Double(store.save.fertilizerDaysLeft(now: Date()))
                               / Double(PlantBalance.fertilizerDays))
                }
            }
            .frame(height: 5)
        }
    }

    private func seedRow(_ item: ShopItem) -> some View {
        HStack(spacing: 8) {
            ShopItemIcon(item: item, pixelSize: 1, dimmed: store.save.count(item) == 0)
            Text("\(item.name) ×\(store.save.count(item))")
                .font(.system(size: 11))
                .foregroundStyle(store.save.count(item) > 0 ? .primary : .secondary)
            Spacer()
            // 결과를 버리고 성공 문구를 덮어쓰고 있었다. 엔진이 거절해도(이미 같거나 높은
            // 등급이 예약돼 있을 때) 화면은 "예약됐어요" 라고 말해서, 아래 줄의
            // "전설 확정 예약됨" 과 정면으로 어긋났다.
            Button("예약") {
                switch store.use(item) {
                case .ok: flash = "\(item.name) 예약 — 다음 씨앗에 적용돼요"
                case .noEffect(let why): flash = why
                case .notOwned: flash = "가진 게 없어요"
                }
            }
                .controlSize(.small)
                .disabled(store.save.count(item) == 0)
        }
        .padding(.vertical, 2)
    }

}
