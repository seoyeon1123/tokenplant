import SwiftUI

/// 화분 탭의 화분. 스프라이트 + 게이지 + 연출.
///
/// 연출 길이의 근거: 팝오버는 사용자가 보려고 연 화면이라 조금 길어도 되지만,
/// 물 주고 2초를 기다리게 하면 다음부터 안 누른다. 그래서 전부 1초 안쪽으로 끝낸다.
/// `accessibilityReduceMotion` 이 켜져 있으면 결과 상태만 즉시 보여준다.
struct PotView: View {
    let store: PlantStore
    /// 0 = 첫 화분, 1 = 화분 슬롯으로 늘린 두 번째. 엔진은 이미 둘 다 키운다.
    var slot: Int = 0
    /// 좁은 팝오버에서 두 그루를 나란히 놓을 때 쓰는 축소판.
    var compact: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // 연출 상태
    @State private var particles: [Particle] = []
    @State private var squash: Double = 1
    @State private var soilWet: Double = 0
    @State private var sparkle: Double = 0
    @State private var glowY: Double = -1        // 분갈이 흙 — 줄기를 타고 오르는 빛
    @State private var fadeFrom: Int?
    @State private var fadeProgress: Double = 1
    @State private var shownWater: Double = 0
    @State private var lastCelebrationSeq = 0
    @State private var lastItemSeq = 0
    @State private var showStages = false
    /// 눌렀는데 막혔을 때의 이유. nil 이면 안 보인다.
    @State private var tapNote: String?
    /// 이름 붙이기 칸. `store.rename` 은 진작 있었는데 부르는 화면이 없어서
    /// 명패의 "붙인 이름"은 아무도 채울 수 없었다.
    @State private var renaming = false
    @State private var nameDraft = ""

    private var spriteSide: CGFloat { compact ? 68 : 96 }

    private var pot: PotState? { store.pot(slot) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 11) {
            if compact {
                // 두 그루를 나란히 놓을 때는 세로로 쌓는다 — 320pt 폭에 스프라이트+요약이 두 벌 안 들어간다.
                spriteBox.frame(maxWidth: .infinity, alignment: .center)
                summary
            } else {
                HStack(alignment: .top, spacing: 12) {
                    spriteBox
                    summary
                }
            }
            gauge
            if let tapNote {
                Text(tapNote).font(.system(size: 10)).foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 물은 양쪽 화분에 똑같이 들어가므로 퀵 슬롯은 한 벌이면 된다.
            // 축소판(두 그루)에서는 아래 홈 화면이 한 벌을 따로 그린다.
            if !compact {
                PotQuickSlots(store: store)
            }
        }
        .onAppear(perform: arm)
        // 창을 다시 열 때 `onAppear` 가 안 불려도 같은 일을 한다. 둘 다 불려도 괜찮다 —
        // 두 번째 `pickCelebration` 은 빈 대기열이라 아무것도 안 한다.
        .onChange(of: store.popoverOpenSeq) { _, _ in arm() }
        .onChange(of: store.celebrationSeq) { _, seq in
            guard seq != lastCelebrationSeq else { return }
            lastCelebrationSeq = seq
            playCelebration()
        }
        .onChange(of: store.itemEffectSeq) { _, seq in
            guard seq != lastItemSeq else { return }
            lastItemSeq = seq
            // 영양제는 한 그루에만 들어간다 — 두 화분이 같이 빛나면 둘 다 받은 것처럼 읽힌다.
            if store.itemEffect == .nutrient, store.itemEffectSlot != slot { return }
            playItemEffect(store.itemEffect)
        }
        .onChange(of: pot?.water ?? 0) { _, target in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) {
                shownWater = Double(target)
            }
        }
    }

    /// 열릴 때 할 일. 기준값을 잡은 **뒤에** 대기열을 비운다 — 순서가 뒤집히면 `onChange` 가
    /// 안 터져서, 닫아둔 동안 자란 결과를 영영 못 본다.
    private func arm() {
        // 팝오버를 다시 열면 지난 경고를 지운다. 뷰가 살아 있어서, 어젯밤의
        // "오늘 물은 다 줬어요" 가 다음 날 아침에도 주황색으로 남아 있었다.
        tapNote = nil
        shownWater = Double(pot?.water ?? 0)
        lastCelebrationSeq = store.celebrationSeq
        lastItemSeq = store.itemEffectSeq
        store.pickCelebration()
    }

    // MARK: 스프라이트

    private var spriteBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05))

            if let from = fadeFrom {
                PixelSpriteView(grid: PotSprites.grid(stageIndex: from, motif: store.species(slot).motif),
                                species: paletteSpecies, wilt: store.wilt, squash: squash)
                    .opacity(1 - fadeProgress)
            }
            PixelSpriteView(grid: currentGrid, species: paletteSpecies,
                            wilt: store.wilt, squash: squash)
                .opacity(fadeFrom == nil ? 1 : fadeProgress)

            soilOverlay
            glowOverlay
            particleLayer
            sparkleLayer
        }
        .frame(width: spriteSide, height: spriteSide)
        .contentShape(Rectangle())
        .onTapGesture { tapPlant() }
        // 탭 제스처는 VoiceOver 로는 안 눌린다 — 버튼으로 알리고 같은 동작을 붙인다.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pot?.nickname ?? store.species(slot).name) 화분")
        .accessibilityHint(tapHelp)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { tapPlant() }
        // 상한에 걸렸을 때도 "물 주기" 라고 적혀 있었다. 눌러도 아무 일이 안 일어나는데
        // 그렇게 쓰면 고장으로 읽힌다 — 옆 퀵 슬롯 버튼은 같은 상황에서 이미 비활성인데
        // 스프라이트만 누르면 되는 것처럼 보여서 둘이 서로 모순이었다.
        .help(tapHelp)
    }

    private var currentGrid: [[Character]] {
        PotSprites.grid(stageIndex: pot?.stageIndex ?? 0, motif: store.species(slot).motif)
    }

    /// 행운이면 잎만 금색으로 갈아끼운다.
    private var paletteSpecies: PlantSpecies {
        pot?.isShiny == true ? PlantSpecies.shinyPalette(of: store.species(slot)) : store.species(slot)
    }

    /// 젖은 흙 + 거름 알갱이. 거름은 7일간 흙에 점으로 남아 버프가 걸린 걸 보여준다 —
    /// 배지로만 표시하면 잊어버리고 두 개를 산다.
    private var soilOverlay: some View {
        GeometryReader { geo in
            let s = geo.size.width / CGFloat(PotSprites.size)
            let soilY = s * (CGFloat(PotSprites.plantRows) + 0.5)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.black.opacity(0.30 * soilWet))
                    .frame(width: s * 12, height: s)
                    .position(x: geo.size.width / 2, y: soilY)

                if store.save.fertilizerActive(now: Date()) {
                    ForEach(0..<6, id: \.self) { k in
                        Rectangle()
                            .fill(Color(red: 0.23, green: 0.16, blue: 0.09))
                            .frame(width: s * 0.8, height: s * 0.55)
                            .position(x: s * (7.5 + Double(k) * 2), y: soilY)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// 분갈이 흙 — 초록빛이 줄기를 타고 올라간다. 꼭대기에 닿는 순간 게이지가 차오른다.
    private var glowOverlay: some View {
        GeometryReader { geo in
            let s = geo.size.width / CGFloat(PotSprites.size)
            if glowY >= 0 {
                Rectangle()
                    .fill(Color(red: 0.75, green: 1.0, blue: 0.80))
                    .frame(width: s * 6, height: s * 1.4)
                    .position(x: geo.size.width / 2,
                              y: s * ((Double(PotSprites.plantRows) - 1) * (1 - glowY)))
                    .opacity(0.85)
            }
        }
        .allowsHitTesting(false)
    }

    private var particleLayer: some View {
        GeometryReader { geo in
            let s = geo.size.width / CGFloat(PotSprites.size)
            ForEach(particles) { p in
                Rectangle()
                    .fill(p.color)
                    .frame(width: s * p.w, height: s * p.h)
                    .position(x: s * (p.x + 0.5), y: s * (p.y + 0.5))
            }
        }
        .allowsHitTesting(false)
    }

    private var sparkleLayer: some View {
        GeometryReader { geo in
            let s = geo.size.width / CGFloat(PotSprites.size)
            ForEach(0..<10, id: \.self) { i in
                let angle = Double(i) / 10 * .pi * 2
                Rectangle()
                    .fill(Color(red: 0.96, green: 0.88, blue: 0.48))
                    .frame(width: s, height: s)
                    .position(x: geo.size.width / 2 + cos(angle) * s * 6 * sparkle,
                              y: geo.size.height * 0.38 + sin(angle) * s * 6 * sparkle)
                    .opacity(sparkle > 0 ? (1 - sparkle) : 0)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: 요약

    private var summary: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                // 붙인 이름이 있으면 그게 주인공이다 — 정원 명패와 같은 규칙.
                Text(pot?.nickname ?? store.species(slot).name).font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Button {
                    nameDraft = pot?.nickname ?? ""
                    renaming = true
                } label: {
                    Image(systemName: "pencil").font(.system(size: 9))
                }
                .accessibilityLabel("이름 붙이기")
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("이름 붙이기 — 정원으로 옮기면 명패에 남아요")
                .popover(isPresented: $renaming, arrowEdge: .bottom) { renameField }
                if pot?.isShiny == true {
                    Text("행운").font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.yellow.opacity(0.30)))
                }
                if !compact {
                    Text(store.species(slot).rarity.label).font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.green.opacity(0.20)))
                }
            }
            Text((pot?.nickname != nil ? "\(store.species(slot).name) · " : "")
                 + "Lv.\((pot?.stageIndex ?? 0) + 1) \(store.stageName(slot))")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            // 상태 문구는 저장 전체에 하나뿐이라(시듦·오늘 물) 축소판 두 벌에 같은 줄을 쓰면 중복이다.
            if !compact {
                Text(store.statusLine)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }


    private var renameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("이름 붙이기").font(.system(size: 11, weight: .semibold))
            TextField(store.species(slot).name, text: $nameDraft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit(commitName)
            HStack {
                Text("비우면 종 이름으로 돌아가요").font(.system(size: 9)).foregroundStyle(.tertiary)
                Spacer()
                Button("저장", action: commitName).controlSize(.small).keyboardShortcut(.defaultAction)
            }
        }
        .padding(10)
    }

    private func commitName() {
        store.rename(String(nameDraft.prefix(20)), slot: slot)
        renaming = false
    }

    // MARK: 게이지

    private var gauge: some View {
        VStack(alignment: .leading, spacing: 5) {
            // 두 그루(축소판)는 한 칸이 약 140pt 라 "총 36,848 mL" + "다음까지 3,000 mL" 가 한 줄에
            // 안 들어가서 줄이 바뀌거나 잘렸다. 축소판은 두 줄로 쌓고, 어느 쪽이든 넘치면 글자를 줄인다.
            Group {
                if compact {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(gaugeLeft)
                        Text(gaugeRight)
                    }
                } else {
                    HStack {
                        Text(gaugeLeft)
                        Spacer(minLength: 6)
                        Text(gaugeRight)
                    }
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(.secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule().fill(Color.green.opacity(0.75))
                        .frame(width: geo.size.width * store.stageProgress(slot))
                }
            }
            .frame(height: 7)
            // 지금 어디쯤인지 보고 싶을 때 — 게이지를 누르면 10단계 전체가 열린다.
            .contentShape(Rectangle())
            .onTapGesture { showStages.toggle() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("성장 게이지")
            .accessibilityValue("다음 단계까지 \(Int((store.stageProgress(slot) * 100).rounded()))%")
            .accessibilityHint("10단계 전체 보기")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { showStages.toggle() }
            // 눌리는 줄 아무 데도 안 적혀 있었다 — 10단계 표가 우연히만 열렸다.
            .help("눌러서 10단계 전체 보기")
            .popover(isPresented: $showStages, arrowEdge: .bottom) { stageList }

            // 이식은 슬롯마다 따로다 — 물·아이템과 달리 이 버튼은 화분별로 있어야 한다.
            if pot?.isReadyToTransplant == true {
                Button("정원으로 옮기기") { _ = store.transplant(slot: slot) }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            } else if let days = store.daysToTransplant(slot), days > 0 {
                Text("이식까지 약 \(days)일")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }

    // 막대와 **같은 것**을 말해야 한다.
    //
    // 예전엔 왼쪽이 `322,550 mL`(누적), 오른쪽이 `/ 476,892`(다음 단계 문턱)였다.
    // 나란히 놓이니 분수로 읽혀서 "68% 찼다"로 보이는데, 막대는 이번 **단계** 진행도라
    // 11% 였다. 둘 다 각자는 맞는데 같이 놓으니 틀린 말이 됐고, 화면은 결국
    // "토큰을 쓰는데 물이 안 찬다"로 읽혔다. (실제로는 사이클의 42%가 차 있었다.)
    //
    // 그래서 `/` 를 없앤다. 분수로 안 보이면 오해할 여지가 없다.
    // 누적은 이 앱의 보람이라 남기고, 오른쪽은 문턱 대신 **남은 양**을 말한다.
    private var gaugeLeft: String { "총 \(Int(shownWater).formatted()) mL" }

    private var gaugeRight: String {
        guard let left = store.waterToNext(slot) else { return "만렙" }
        return "다음까지 \(left.formatted()) mL"
    }

    /// 이 화분의 목표. 아직 안 심었으면 지금 심으면 잡힐 목표를 미리 보여준다.
    private var shownCycle: Int {
        pot?.cycleWater ?? PlantBalance.cycleWater(dailyRaw: store.dailyRate)
    }

    private var stageList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(0..<PlantBalance.stageCount, id: \.self) { i in
                let cur = i == (pot?.stageIndex ?? 0)
                let done = i < (pot?.stageIndex ?? 0)
                HStack(spacing: 6) {
                    Text(done ? "●" : (cur ? "◉" : "○"))
                        .font(.system(size: 9))
                        // `.tertiary` 는 ShapeStyle 전용이라 Color 타입이 아니다.
                        // 삼항으로 묶으면 한 타입으로 통일돼야 해서 Color 로만 쓴다.
                        .foregroundStyle(done ? Color.green
                                              : (cur ? Color.primary : Color.secondary.opacity(0.55)))
                    Text("Lv.\(i + 1) \(PotSprites.stages[i].name)")
                        .font(.system(size: 11, weight: cur ? .semibold : .regular))
                    Spacer()
                    Text(PlantBalance.threshold(stage: i, cycle: shownCycle).formatted())
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Divider().padding(.vertical, 2)
            HStack(spacing: 6) {
                Text("→").font(.system(size: 9)).foregroundStyle(.tertiary)
                Text("정원 이식").font(.system(size: 11))
                Spacer()
                Text(shownCycle.formatted())
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 220)
    }

    // MARK: 연출 재생

    /// 스프라이트를 눌러도 물이 간다 — 버튼을 못 찾아도 화분을 두드리면 된다.
    /// 가진 게 없으면 아무 일도 안 한다. 헛연출이 제일 나쁘다.
    /// 연출은 여기서 직접 돌리지 않고 `store.itemEffectSeq` 신호를 따른다 —
    /// 직접 돌리면 화분이 두 개일 때 누른 쪽만 움직인다.
    private var tapHelp: String {
        if store.save.count(.water) <= 0 { return "토큰을 쓰면 저절로 자라요" }
        if let why = store.blockReason(.water) { return why }
        return "물 주기 — 오늘 \(store.waterUsesLeftToday)번 더 (창고에 \(store.save.count(.water))개)"
    }

    /// 눌러서 아무 일이 안 일어나면 고장으로 읽힌다. 막힌 이유를 **화면에** 남긴다 —
    /// 툴팁은 마우스를 올려야 보이고, 메뉴바 팝오버에서는 그러기도 전에 닫는다.
    private func tapPlant() {
        guard store.save.count(.water) > 0 else {
            tapNote = "물이 없어요 — 상점에서 살 수 있어요"
            return
        }
        switch store.use(.water) {
        case .ok: tapNote = nil
        case .noEffect(let why): tapNote = why
        case .notOwned: tapNote = "물이 없어요 — 상점에서 살 수 있어요"
        }
    }

    /// 물방울이 떨어지고 흙이 젖고 잎이 한 번 부푼다. 0.9초.
    private func pourWater(count: Int) {
        guard !reduceMotion else { return }
        particles = (0..<count).map { i in
            Particle(x: Double.random(in: 6...17), y: -2 - Double(i) * 0.9,
                     w: 0.9, h: 1.7, color: Color(red: 0.50, green: 0.77, blue: 0.91))
        }
        withAnimation(.linear(duration: 0.55)) {
            for i in particles.indices { particles[i].y = Double(PotSprites.plantRows) }
        }
        withAnimation(.easeOut(duration: 0.25).delay(0.5)) { soilWet = 1 }
        withAnimation(.easeIn(duration: 1.6).delay(0.8)) { soilWet = 0 }
        bounceLeaves(delay: 0.5)
        clearParticles(after: 0.9)
    }

    /// 거름 — 알갱이가 흙에 흩뿌려진다. 0.7초.
    private func scatterFertilizer() {
        guard !reduceMotion else { return }
        particles = (0..<16).map { i in
            Particle(x: Double.random(in: 6.5...17), y: -1 - Double(i) * 0.4,
                     w: 0.7, h: 0.7, color: Color(red: 0.42, green: 0.29, blue: 0.16))
        }
        withAnimation(.easeIn(duration: 0.5)) {
            for i in particles.indices { particles[i].y = Double(PotSprites.plantRows) - 0.2 }
        }
        clearParticles(after: 0.7)
    }

    /// 분갈이 흙 — 빛이 줄기를 타고 오른다. 0.9초.
    private func riseGlow() {
        guard !reduceMotion else { return }
        glowY = 0
        withAnimation(.easeOut(duration: 0.75)) { glowY = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            glowY = -1
            burstSparkle()
        }
    }

    private func bounceLeaves(delay: Double = 0) {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.45).delay(delay)) { squash = 1.10 }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.55).delay(delay + 0.22)) { squash = 1 }
    }

    private func burstSparkle() {
        guard !reduceMotion else { return }
        sparkle = 0.01
        withAnimation(.easeOut(duration: 0.9)) { sparkle = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { sparkle = 0 }
    }

    private func clearParticles(after seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { particles = [] }
    }

    private func playItemEffect(_ item: ShopItem?) {
        guard let item else { return }
        switch item {
        case .water: pourWater(count: 12)
        case .fertilizer: scatterFertilizer()
        case .nutrient: riseGlow()           // 남은 거리가 당겨지는 건 빛이 줄기를 타고 오르는 걸로
        case .premiumSeed, .legendarySeed, .shinyCharm, .potSlot,
             .bench, .feeder, .lantern, .decorBox:
            // 장식 뽑기의 연출은 화분이 아니라 **결과 문구**가 맡는다 —
            // 화분 위에 뭘 뿌리면 성장에 영향이 있는 것처럼 읽힌다.
            break
        }
    }

    // 연속 사용 줄은 `TokenPlantApp.footnote` 하나로 합쳤다.
    // 여기와 오늘 블록에 각각 두면 같은 내용이 두 줄로 뜬다 —
    // 실제로 어제 그렇게 넣었다가 화면에서 겹쳤다.

    private func playCelebration() {
        // 여기서 store.consumeCelebration() 을 부르면 안 된다 —
        // 화분이 두 개일 때 먼저 그려진 쪽이 이벤트를 먹어버려 다른 쪽만 조용히 자란다.
        // 재생 여부는 `celebrationSeq` 로 이미 한 번만 걸러진다.
        guard let event = store.celebration else { return }
        guard !reduceMotion else { return }

        switch event {
        case .levelUp(let stage):
            fadeFrom = max(0, stage - 1)
            fadeProgress = 0
            withAnimation(.easeInOut(duration: 0.6)) { fadeProgress = 1 }
            bounceLeaves()
            burstSparkle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { fadeFrom = nil }
        case .newSeed, .transplanted:
            fadeFrom = nil
            bounceLeaves()
        case .fruitHarvest, .readyToTransplant:
            burstSparkle()
        case .windowBurned, .decorFound, .streakGift:
            // 둘 다 화분에 들어온 게 아니다(지갑 · 정원). 잎은 안 흔들고 반짝임만 터뜨린다 —
            // 게이지가 안 움직이는데 잎이 부풀면 자란 것처럼 읽힌다.
            burstSparkle()
        case .thirsty:
            break   // 색 변화가 이미 상태를 말해준다
        }
    }

    struct Particle: Identifiable {
        let id = UUID()
        var x: Double
        var y: Double
        var w: Double
        var h: Double
        var color: Color
    }
}

/// 화분 탭의 행동 줄 — 창고에 있는 가속 아이템 세 칸.
///
/// 화분이 두 개여도 한 벌이면 된다: 물은 나뉘지 않고 양쪽에 똑같이 들어간다.
/// 여기 없으면 상점에서 사야 한다는 뜻이라, 0개일 때도 칸은 남겨 둔다 —
/// 칸이 사라지면 그런 게 있다는 걸 영영 모른다.
struct PotQuickSlots: View {
    let store: PlantStore

    private let items: [ShopItem] = [.water, .fertilizer, .nutrient]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                slotButton(item)
                .controlSize(.small)
                .buttonStyle(.bordered)
                // 물만 색을 준다. `.borderedProminent` 를 삼항으로 고르면 두 스타일이
                // 서로 다른 타입이라 안 섞이므로, 스타일은 하나로 두고 tint 로만 강조한다.
                .tint(item == .water && store.save.count(.water) > 0 ? .accentColor : .secondary)
                .disabled(store.save.count(item) == 0 || blocked(item))
                .help(help(item))
            }

            waterAllowance
            Spacer()
        }
    }

    /// 영양제는 그루에 기록되는 품목이라, 화분이 둘이면 **어느 그루에** 줄지 고른다.
    /// 물·거름은 저장 전체에 걸려서 한 번 누르면 된다.
    @ViewBuilder
    private func slotButton(_ item: ShopItem) -> some View {
        let content = HStack(spacing: 3) {
            ShopItemIcon(item: item, pixelSize: 1, dimmed: store.save.count(item) == 0)
            Text(label(item)).font(.system(size: 10))
        }
        if item == .nutrient, store.slotCount == 2 {
            Menu {
                ForEach(store.nutrientSlots, id: \.self) { slot in
                    Button("\(slot + 1)번 · \(store.species(slot).name) +\((store.nutrientGain(slot) ?? 0).formatted()) mL") {
                        _ = store.use(.nutrient, slot: slot)
                    }
                }
            } label: { content }
            // 기본 메뉴 모양은 `.bordered` 가 안 먹고 화살표만큼 넓어서, 옆 버튼들과 모양·폭이 달랐다.
            // 버튼 모양 메뉴로 두면 바깥의 버튼 스타일을 그대로 받는다.
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
        } else {
            Button { _ = store.use(item) } label: { content }
        }
    }

    private func label(_ item: ShopItem) -> String {
        if item == .fertilizer {
            let left = store.save.fertilizerDaysLeft(now: Date())
            if left > 0 { return "\(left)일" }
        }
        return "\(item.name) \(store.save.count(item))"
    }

    /// 물은 **오늘 남은 횟수**를 버튼 옆에 붙인다. 가진 개수만 보여주면
    /// 상한에 걸린 걸 눌러보고 나서야 알게 된다.
    ///
    /// `오늘 0/2` 로 쓰다가 고쳤다. 앞 숫자가 **쓴 횟수**였는데 "남은 0" 으로 읽혀서,
    /// 아직 두 번 줄 수 있는 아침에 다 쓴 것처럼 보였다. 다 쓴 날은 `2/2` 가 되어
    /// 이번엔 거꾸로 "둘 다 가능"으로 읽혔다. 분수를 버리고 말로 쓴다.
    private var waterAllowance: some View {
        let left = store.waterUsesLeftToday
        return Text(left > 0 ? "오늘 \(left)번 더" : "오늘은 끝")
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(left > 0 ? Color.secondary : Color.orange)
            .help(left > 0 ? "오늘 \(left)번 더 줄 수 있어요"
                           : "오늘은 다 줬어요 — 안 쓴 토큰은 지갑에 그대로 남습니다")
    }

    /// 지금 못 쓰는 품목. 판정은 창고와 **같은 곳**(`PlantStore.blockReason`)에서 온다 —
    /// 두 화면이 따로 판정하던 때는 한쪽만 켜져 있다가 누르면 거절되는 일이 반복됐다.
    private func blocked(_ item: ShopItem) -> Bool { store.blockReason(item) != nil }

    private func help(_ item: ShopItem) -> String {
        guard store.save.count(item) > 0 else { return "\(item.name) — 상점에서 살 수 있어요" }
        switch item {
        case .water:
            if let why = store.blockReason(item) { return why }
            return "+\(store.waterML.formatted()) mL · 오늘 \(store.waterUsesLeftToday)번 남음"
        case .fertilizer:
            if let why = store.blockReason(item) { return why }
            return "\(PlantBalance.fertilizerDays)일간 들어오는 물 +\(PlantBalance.fertilizerBonusPercent)%"
        case .nutrient:
            let slots = store.nutrientSlots
            guard !slots.isEmpty else {
                return "줄 수 있는 그루가 없어요 — 그루마다 한 번이고, 다 자란 그루엔 안 들어가요"
            }
            if store.slotCount == 2 { return "어느 화분에 줄지 골라요 · 한 그루에 한 번뿐이에요" }
            return "지금 쓰면 +\((store.nutrientGain(0) ?? 0).formatted()) mL · 한 그루에 한 번뿐이에요"
        default: return item.name
        }
    }
}
