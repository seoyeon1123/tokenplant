import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 씬을 픽셀 격자(hex 문자열)로 한 번 조립한다.
///
/// Canvas 와 PNG 내보내기가 **같은 함수**를 쓰게 하려고 그리기와 조립을 분리했다.
/// 두 곳에 그리기 코드를 따로 두면 내보낸 PNG 가 화면과 달라지는 게 시간문제다.
enum GardenComposer {
    /// `positions` 는 사용자가 끌어다 놓은 자리(키 → [x, 바닥y]). 없으면 기본 자리를 쓴다.
    /// `hiding` 은 **지금 끌고 있는 장식** — 격자에서 빼야 손가락을 따라오는 유령과 겹치지 않는다.
    static func compose(layout: SceneLayout,
                        season: SeasonPalette,
                        entries: [GardenEntry],
                        decorations: [String],
                        currentPotStage: Int?,
                        currentSpecies: PlantSpecies?,
                        positions: [String: [Int]] = [:],
                        hiding: String? = nil) -> [[String?]] {
        var grid = [[String?]](repeating: [String?](repeating: nil, count: layout.width),
                               count: layout.height)

        func put(_ x: Int, _ y: Int, _ hex: String?) {
            guard let hex, x >= 0, x < layout.width, y >= 0, y < layout.height else { return }
            grid[y][x] = hex
        }

        let horizon = layout.horizon

        // 하늘 · 잔디
        for y in 0..<layout.height {
            for x in 0..<layout.width {
                put(x, y, y < horizon ? season.sky : (((x + y) % 4 < 2) ? season.grass : season.grass2))
            }
        }

        if layout.features.contains(.glass) {
            for y in 0..<horizon {
                for x in 0..<layout.width {
                    put(x, y, ((x % 14 == 0) || (y % 12 == 0)) ? "#8fa8ad" : "#cfe0e4")
                }
            }
            for x in 0..<layout.width { put(x, horizon - 1, PlantSpriteBuilder.outlineHex) }
        }

        if layout.features.contains(.fence) {
            let top = max(0, horizon - 10)
            for y in top..<horizon {
                for x in 0..<layout.width {
                    put(x, y, (x % 6 < 4) ? season.fence : season.fence2)
                }
            }
            for x in 0..<layout.width { put(x, top, PlantSpriteBuilder.outlineHex) }
        }

        if layout.features.contains(.sill) {
            for y in horizon..<min(horizon + 6, layout.height) {
                for x in 0..<layout.width {
                    put(x, y, y < horizon + 4 ? season.fence : season.fence2)
                }
            }
            for x in 0..<layout.width { put(x, horizon, PlantSpriteBuilder.outlineHex) }
        }

        if layout.features.contains(.path) {
            for y in max(0, layout.height - 8)..<layout.height {
                for x in 0..<layout.width {
                    put(x, y, ((x * 3 + y) % 5 != 0) ? season.path : "#ad8f63")
                }
            }
        }

        if layout.features.contains(.pond) {
            let cx = Int(Double(layout.width) * 0.78), cy = layout.height - 13
            let rx = 15.0, ry = 6.0
            for y in (cy - 7)...(cy + 7) {
                for x in (cx - 16)...(cx + 16) {
                    let d = pow(Double(x - cx) / rx, 2) + pow(Double(y - cy) / ry, 2)
                    if d <= 1 { put(x, y, season.water) }
                    else if d <= 1.35 { put(x, y, PlantSpriteBuilder.outlineHex) }
                }
            }
            for k in 0..<4 { put(cx - 6 + k * 2, cy - 2, "#dff0f8") }
        }

        // 장식 — **모든 티어에** 그린다. 앞쪽 바닥에 두므로 그루와 겹치지 않는다.
        //
        // 예전엔 뒷마당(6그루)부터만 그렸다. 장식이 셋뿐이고 전부 직접 사는 것이었을 때는
        // 그래도 됐는데, 뽑기가 생기면서 깨졌다: 이틀째에 뽑아서 "정원에 놓았어요"라고
        // 띄우는데 실제로 보이는 건 6그루를 채운 **석 달 뒤**다. 약속을 깨는 셈이다.
        // (정원 창은 3그루부터지만 컬렉션 탭의 미니뷰는 처음부터 보인다 — 거기서 바로 보인다.)
        // 그루와 같은 규칙으로 **최근 것부터** 놓는다. 앞에서 자르면 창가(자리 3개)에서
        // 넷째로 뽑은 장식이 안 보이는데 화면은 "정원에 놓았어요" 라고 말한다.
        // 열두 개를 다 모을 수 있는데 초반 티어의 자리는 3~5개뿐이라 늘 걸리는 구간이다.
        for (key, spot) in layout.decorPlacements(decorations, positions: positions) {
            guard key != hiding, let art = DecorIcons.grid(key) else { continue }
            for (gy, row) in art.enumerated() {
                for (gx, ch) in row.enumerated() where ch != "." {
                    put(spot.x + gx, spot.y + gy - DecorIcons.size, IconPalette.color(ch))
                }
            }
        }

        // 창가·베란다에는 지금 키우는 화분이 함께 놓인다 — 빈 씬을 보여주지 않는다.
        if let stage = currentPotStage, let sp = currentSpecies,
           layout.key == "sill" || layout.key == "balc" {
            // `sp` 가 이미 이 종이다. `compose` 는 순수 함수라 store 가 없다.
            let art = PotSprites.grid(stageIndex: stage, motif: sp.motif)
            let potX = layout.key == "balc" ? 6 : (layout.width - PotSprites.size) / 2
            let potY = horizon + 6 - PotSprites.size
            for (gy, row) in art.enumerated() {
                for (gx, ch) in row.enumerated() where ch != "." {
                    put(potX + gx, potY + gy, PlantSpriteBuilder.color(ch, species: sp, wilt: 0))
                }
            }
        }

        // 그루 — 뒷줄부터 그려 앞줄이 겹친다.
        //
        // 자리보다 그루가 많으면 **최근 것부터** 그린다. 앞에서 자르면 오래된 30그루가
        // 영원히 박혀서, 그 뒤에 심은 건 정원에 한 번도 안 나타난다.
        // 자리가 없다고 이식을 막는 건 더 나쁘다 — 게임이 그 자리에서 멈춘다.
        let shown = entries.count > layout.slotCount
            ? Array(entries.suffix(layout.slotCount))
            : entries

        let rowCount = max(1, layout.rows.count)
        var idx = 0
        for (ri, row) in layout.rows.enumerated() {
            var haze = rowCount > 1 ? 0.22 * (1 - Double(ri) / Double(rowCount - 1)) : 0
            if season.extraHaze > 0 { haze = season.extraHaze + haze * 0.6 }

            for x in row.xs {
                guard idx < shown.count else { return grid }
                let e = shown[idx]
                idx += 1
                let art = GardenSprites.grid(e.species.shape, motif: e.species.motif)
                let palette = e.isShiny ? PlantSpecies.shinyPalette(of: e.species) : e.species
                for (gy, gridRow) in art.enumerated() {
                    for (gx, ch) in gridRow.enumerated() where ch != "." {
                        guard let hex = PlantSpriteBuilder.color(ch, species: palette, wilt: 0) else { continue }
                        put(x + gx, row.baseline + gy - GardenSprites.size,
                            haze > 0 ? PlantSpriteBuilder.blend(hex, season.sky, haze) : hex)
                    }
                }
            }
        }

        return grid
    }

    /// PNG 내보내기 — 수목원(18그루)부터 해금. 화면과 같은 조립 결과를 쓴다.
    static func image(_ grid: [[String?]], scale: Int) -> NSImage {
        let h = grid.count, w = grid.first?.count ?? 0
        let size = NSSize(width: w * scale, height: h * scale)
        guard w > 0, h > 0 else { return NSImage(size: .init(width: 1, height: 1)) }

        let image = NSImage(size: size)
        image.lockFocusFlipped(true)
        for y in 0..<h {
            for x in 0..<w {
                guard let hex = grid[y][x], let c = NSColor(hex: hex) else { continue }
                c.setFill()
                NSRect(x: CGFloat(x * scale), y: CGFloat(y * scale),
                       width: CGFloat(scale), height: CGFloat(scale)).fill()
            }
        }
        image.unlockFocus()
        return image
    }
}

extension SceneLayout {
    /// 장식마다 최종 자리. 사용자가 옮겨둔 게 있으면 그걸, 없으면 기본 자리를 준다.
    ///
    /// **그리기·클릭 판정·끌기가 전부 이 함수 하나를 본다.** 정원 나무에서 그리는 창과
    /// 클릭 판정이 갈려서 엉뚱한 명패가 뜬 적이 있어서, 여기서는 처음부터 한 곳으로 모은다.
    func decorPlacements(_ keys: [String],
                         positions: [String: [Int]]) -> [(key: String, spot: (x: Int, y: Int))] {
        let spots = decorSpots
        // 자리를 옮긴 장식은 기본 자리를 안 먹는다 — 그래야 옮긴 만큼 남은 장식이 앞으로 당겨진다.
        var freeIndex = 0
        var out: [(String, (Int, Int))] = []
        for key in keys {
            if let p = positions[key], p.count == 2 {
                out.append((key, (p[0], p[1])))
                continue
            }
            guard freeIndex < spots.count else { continue }   // 자리가 모자라면 안 그린다
            out.append((key, spots[freeIndex]))
            freeIndex += 1
        }
        return out
    }

    /// 장식 자리 — 캔버스 너비에서 **계산**한다. 좌표를 셋만 박아뒀을 때는
    /// 장식이 열두 개가 되자 넷째부터 조용히 안 그려졌다(`i < decorSpots.count` 에서 잘린다).
    ///
    /// 앞쪽 바닥 한 줄에 18px 간격으로 들어가는 만큼 만든다. 그루보다 먼저 그려지므로
    /// 앞줄 나무에 일부 가리는데, 그게 오히려 겹쳐 보여서 자연스럽다.
    var decorSpots: [(x: Int, y: Int)] {
        let baseY = height - 2
        let step = DecorIcons.size + 2
        let count = max(1, (width - 6) / step)
        return (0..<count).map { (x: 3 + $0 * step, y: baseY) }
    }
}

/// 정원 씬 창. 팝오버(320pt)에 서른 그루를 넣으면 아무것도 안 보이므로 별도 창이다.
struct GardenView: View {
    let store: PlantStore
    @State private var selected: GardenEntry?
    @State private var seasonOverride: String?
    @State private var exportNote: String?
    /// 지금 끌고 있는 장식 키. 격자에서 빼고 유령을 대신 그린다.
    @State private var dragKey: String?
    /// 끌기 시작점부터의 이동량(포인트). 픽셀로 바꿀 땐 `scale` 로 나눈다.
    @State private var dragBy: CGSize = .zero

    private var layout: SceneLayout { SceneLayout.byKey(store.save.gardenTier.key) }

    /// 계절은 온실(10그루)부터 시스템 시간을 따라간다. 그전엔 항상 봄.
    private var season: SeasonPalette {
        if let k = seasonOverride { return SeasonPalette.byKey(k) }
        return store.save.gardenCount >= 10 ? .current : .byKey("spring")
    }

    private var grid: [[String?]] {
        GardenComposer.compose(layout: layout, season: season,
                               entries: store.save.garden,
                               decorations: store.save.decorations,
                               currentPotStage: store.pot?.stageIndex,
                               currentSpecies: store.species,
                               positions: store.save.decorPositions,
                               hiding: dragKey)
    }

    /// 내보내는 PNG 는 **끌던 것도 포함**해야 한다 — 화면과 달라 보이면 버그로 읽힌다.
    private var exportGrid: [[String?]] {
        GardenComposer.compose(layout: layout, season: season,
                               entries: store.save.garden,
                               decorations: store.save.decorations,
                               currentPotStage: store.pot?.stageIndex,
                               currentSpecies: store.species,
                               positions: store.save.decorPositions)
    }

    private var decorPlacements: [(key: String, spot: (x: Int, y: Int))] {
        layout.decorPlacements(store.save.decorations, positions: store.save.decorPositions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            scene
            controls
            if let e = selected { nameplate(e) } else { hint }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 460)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(store.save.gardenTier.name).font(.system(size: 20, weight: .semibold))
            Text(store.gardenCountText)
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
            Spacer()
            if let next = GardenTier.next(afterCount: store.save.gardenCount) {
                Text("\(next.name)까지 \(next.need - store.save.gardenCount)그루 · \(next.unlock) 해금")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            } else {
                Text("정원 만렙").font(.system(size: 11, weight: .medium)).foregroundStyle(.pink)
            }
        }
    }

    private var scene: some View {
        GeometryReader { geo in
            let scale = max(1, floor(min(geo.size.width / CGFloat(layout.width),
                                         geo.size.height / CGFloat(layout.height))))
            ZStack(alignment: .topLeading) {
                PixelGridCanvas(grid: grid, scale: scale)
                ForEach(Array(placements.enumerated()), id: \.offset) { _, p in
                    Button { selected = p.entry } label: {
                        Rectangle().fill(.clear)
                            .frame(width: CGFloat(GardenSprites.size) * scale,
                                   height: CGFloat(GardenSprites.size) * scale)
                    }
                    .buttonStyle(.plain)
                    .offset(x: CGFloat(p.x) * scale,
                            y: CGFloat(p.baseline - GardenSprites.size) * scale)
                    .help(p.entry.nickname ?? p.entry.species.name)
                }

                // 장식 — **끌어서 옮긴다.** 나무는 뒷줄·앞줄이 있어서 아무 데나 놓으면
                // 서로 가리거나 공중에 뜨지만, 장식은 앞쪽 바닥에 놓이는 물건이라 자유롭다.
                ForEach(decorPlacements, id: \.key) { d in
                    let moving = dragKey == d.key
                    DecorIcon(key: d.key, pixelSize: scale)
                        .opacity(moving ? 0.85 : 0.001)   // 쉬는 동안은 격자가 그린다
                        .frame(width: CGFloat(DecorIcons.size) * scale,
                               height: CGFloat(DecorIcons.size) * scale)
                        .contentShape(Rectangle())
                        .offset(x: CGFloat(d.spot.x) * scale + (moving ? dragBy.width : 0),
                                y: CGFloat(d.spot.y - DecorIcons.size) * scale
                                   + (moving ? dragBy.height : 0))
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { v in
                                    dragKey = d.key
                                    dragBy = v.translation
                                }
                                .onEnded { v in
                                    store.moveDecor(d.key,
                                                    x: d.spot.x + Int((v.translation.width / scale).rounded()),
                                                    y: d.spot.y + Int((v.translation.height / scale).rounded()),
                                                    in: layout)
                                    dragKey = nil
                                    dragBy = .zero
                                }
                        )
                        .help("\(DecorIcons.name(d.key)) — 끌어서 옮기세요")
                }
            }
            .frame(width: CGFloat(layout.width) * scale,
                   height: CGFloat(layout.height) * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(minHeight: 220)
    }

    /// 클릭 판정과 명패가 **그려진 것과 같은 창**을 봐야 한다.
    ///
    /// `GardenComposer` 는 자리가 모자라면 `entries.suffix(slotCount)` 를 그리는데
    /// 여기서는 0번부터 셌다. 그래서 자리보다 그루가 많은 구간(2, 4~5, 7~9, 11~17, …)에서
    /// **화면의 세 번째 나무를 누르면 첫 번째 나무의 명패가 떴다.**
    private var shownEntries: [GardenEntry] {
        let all = store.save.garden
        return all.count > layout.slotCount ? Array(all.suffix(layout.slotCount)) : all
    }

    private var placements: [(entry: GardenEntry, x: Int, baseline: Int)] {
        var out: [(GardenEntry, Int, Int)] = []
        let shown = shownEntries
        var i = 0
        for row in layout.rows {
            for x in row.xs {
                guard i < shown.count else { return out }
                out.append((shown[i], x, row.baseline))
                i += 1
            }
        }
        return out
    }

    private var controls: some View {
        HStack(spacing: 8) {
            if store.save.gardenCount >= 10 {
                Text("계절").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                ForEach(SeasonPalette.all, id: \.key) { p in
                    Button(p.name) { seasonOverride = p.key }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .tint(season.key == p.key ? .accentColor : .secondary)
                }
                Button("자동") { seasonOverride = nil }
                    .controlSize(.small).disabled(seasonOverride == nil)
            }

            Spacer()

            if let note = exportNote {
                Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
            }

            if !store.save.decorPositions.isEmpty {
                // 끌다가 겹쳐놓고 못 찾을 때 빠져나갈 길. 이게 없으면 되돌릴 방법이 없다.
                Button("장식 자리 초기화") { store.resetDecorPositions() }
                    .controlSize(.small)
            }

            Button("PNG 내보내기") { exportPNG() }
                .controlSize(.small)
                .disabled(store.save.gardenCount < 18)
                .help(store.save.gardenCount < 18 ? "수목원(18그루)부터 해금" : "정원을 8배로 저장합니다")
        }
    }

    private func exportPNG() {
        let image = GardenComposer.image(exportGrid, scale: 8)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.png]
        panel.nameFieldStringValue = "garden-\(store.save.gardenCount)그루.png"
        guard panel.runModal() == .OK, let url = panel.url,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            exportNote = "저장하지 못했어요"
            return
        }
        do {
            try data.write(to: url)
            exportNote = "저장했어요"
        } catch {
            exportNote = "저장하지 못했어요"
        }
    }

    private func nameplate(_ e: GardenEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(e.nickname ?? e.species.name).font(.system(size: 14, weight: .semibold))
                if e.isShiny {
                    Text("반짝").font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.yellow.opacity(0.3)))
                }
                Text(e.species.rarity.label).font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.green.opacity(0.2)))
                Spacer()
                Button("닫기") { selected = nil }.controlSize(.small)
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 3) {
                GridRow {
                    label("심은 날"); value(dateText(e.plantedAt))
                    label("완성"); value(dateText(e.transplantedAt))
                }
                GridRow {
                    label("걸린 일수"); value("\(e.daysToGrow)일")
                    label("부은 물"); value("\(e.totalWater.formatted()) mL")
                }
            }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private var hint: some View {
        Text(store.save.garden.isEmpty
             ? "아직 이식한 그루가 없어요. 거목까지 키우면 여기로 옮겨집니다."
             : "그루를 클릭하면 명패가 열립니다.")
            .font(.system(size: 11)).foregroundStyle(.tertiary)
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
    }

    private func value(_ s: String) -> some View {
        Text(s).font(.system(size: 11, design: .monospaced))
    }

    private func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

}

/// hex 격자를 그대로 칠한다. 조립은 `GardenComposer` 가 이미 끝냈다.
struct PixelGridCanvas: View {
    let grid: [[String?]]
    let scale: CGFloat

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, _ in
            for (y, row) in grid.enumerated() {
                for (x, hex) in row.enumerated() {
                    guard let hex, let c = Color(hex: hex) else { continue }
                    ctx.fill(Path(CGRect(x: CGFloat(x) * scale, y: CGFloat(y) * scale,
                                         width: scale, height: scale)), with: .color(c))
                }
            }
        }
        .frame(width: CGFloat(grid.first?.count ?? 0) * scale,
               height: CGFloat(grid.count) * scale)
    }
}
