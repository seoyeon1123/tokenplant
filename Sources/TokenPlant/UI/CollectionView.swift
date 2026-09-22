import SwiftUI

/// 컬렉션 탭 — 정원 미니뷰 + 종 도감 + 기록.
///
/// 좁은 팝오버에 정원을 다 넣으면 아무것도 안 보이므로 여기선 미니뷰만 보여주고,
/// 전체는 별도 창으로 넘긴다(작은 화단 = 3그루부터 활성).
struct CollectionView: View {
    let store: PlantStore
    let openGarden: () -> Void

    private var layout: SceneLayout { SceneLayout.byKey(store.save.gardenTier.key) }
    /// 미니뷰는 팝오버 폭(292pt)에 맞춘 정수 배율. 픽셀이 깨지면 안 된다.
    private var miniScale: CGFloat {
        max(1, floor(292 / CGFloat(layout.width)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            gardenSection
            Divider()
            dexSection
            Divider()
            recordSection
        }
    }

    // MARK: 정원 미니뷰

    private var gardenSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("정원 · \(store.save.gardenTier.name)")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(store.gardenCountText)
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }

            // 정원 창과 **같은** 조립 함수를 쓴다 — 미니뷰가 큰 창과 달라 보이면 버그처럼 읽힌다.
            PixelGridCanvas(grid: GardenComposer.compose(
                layout: layout,
                season: store.save.gardenCount >= 10 ? .current : .byKey("spring"),
                entries: store.save.garden,
                decorations: store.save.decorations,
                currentPotStage: store.pot?.stageIndex,
                currentSpecies: store.species,
                // 옮겨둔 자리를 미니뷰도 따라야 한다 — 안 그러면 큰 창과 달라 보인다.
                positions: store.save.decorPositions), scale: miniScale)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                if let next = GardenTier.next(afterCount: store.save.gardenCount) {
                    Text("\(next.name)까지 \(next.need - store.save.gardenCount)그루")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                } else {
                    Text("정원 만렙").font(.system(size: 10, weight: .medium)).foregroundStyle(.pink)
                }
                Spacer()
                Button("크게 보기") { openGarden() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(store.save.gardenCount < 3)
            }
            if store.save.gardenCount < 3 {
                Text("작은 화단(3그루)부터 정원 창이 열려요.")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: 도감

    /// 실루엣 3종 × 팔레트 — 흔함/보통/희귀/전설 15종 각각 일반·반짝 두 칸.
    /// 1차 목표는 흔함+보통 9종의 일반 칸이다.
    private var dexSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("종 도감").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(collected.count) / \(PlantSpecies.catalog.count)")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 5),
                      spacing: 5) {
                ForEach(PlantSpecies.catalog) { sp in
                    dexCell(sp)
                }
            }

            // "반짝은 명패에만" 이라고 적어뒀는데 바로 위 도감 칸이 반짝 팔레트로 그리고
            // ✨ 배지까지 붙인다. 화면이 하는 일을 화면이 부정하고 있었다.
            Text("미획득 칸은 실루엣만 보여요. 반짝은 ✨ 로 표시됩니다.")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
        }
    }

    private var collected: Set<String> {
        Set(store.save.garden.map(\.speciesID))
    }

    private var shinyCollected: Set<String> {
        Set(store.save.garden.filter(\.isShiny).map(\.speciesID))
    }

    private func dexCell(_ sp: PlantSpecies) -> some View {
        let got = collected.contains(sp.id)
        let shiny = shinyCollected.contains(sp.id)
        // 미획득이면 실루엣만 — 아웃라인 색으로 통째로 칠한 그리드를 만든다.
        let palette = shiny ? PlantSpecies.shinyPalette(of: sp) : sp
        return VStack(spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(got ? Color.green.opacity(0.12) : Color.primary.opacity(0.05))
                if got {
                    PixelSpriteView(grid: GardenSprites.grid(sp.shape, motif: sp.motif),
                                    species: palette, pixelSize: 2, potRow: GardenSprites.size)
                } else {
                    PixelSpriteView(grid: GardenSprites.grid(sp.shape, motif: sp.motif),
                                    species: silhouette, pixelSize: 2, potRow: GardenSprites.size)
                        .opacity(0.28)
                }
                if shiny {
                    Text("✨").font(.system(size: 8))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(2)
                }
            }
            .frame(height: 40)
            Text(got ? sp.name : "???")
                .font(.system(size: 8))
                // `.tertiary` 는 Color 가 아니라 ShapeStyle 이다 — 삼항에서는 못 섞는다.
                .foregroundStyle(got ? Color.secondary : Color.secondary.opacity(0.55))
                .lineLimit(1)
        }
        .help(got ? "\(sp.name) · \(sp.rarity.label)" : "아직 못 만난 종")
    }

    /// 미획득 칸용 단색 팔레트.
    private var silhouette: PlantSpecies {
        var s = PlantSpecies.catalog[0]
        s.leaf = "#7c8a80"; s.leafLight = "#7c8a80"; s.leafShade = "#7c8a80"; s.petal = "#7c8a80"
        return s
    }

    // MARK: 기록

    private var recordSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("기록").font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
            row("완주한 그루", "\(store.save.gardenCount)")
            if let fastest = store.save.garden.map(\.daysToGrow).min() {
                row("가장 빨리 키운 그루", "\(fastest)일")
            }
            row("부은 총 물", "\(store.save.waterSinceInstall.formatted()) mL")
            row("누적 원시 토큰", TokenFormat.short(store.save.rawSinceInstall))
            if store.save.streakDays > 0 {
                row("연속 사용", "\(store.save.streakDays)일 (+\(PlantBalance.streakBonusPercent(days: store.save.streakDays))%)")
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.system(size: 10, design: .monospaced))
        }
    }

}
