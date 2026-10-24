import SwiftUI

struct SavedGuidesView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            if store.savedGuides.isEmpty {
                ZStack {
                    CelestialBackdrop().ignoresSafeArea()
                    ContentUnavailableView {
                        Label(store.language.text("還沒有收藏", "아직 저장한 메시지가 없어요", "Nothing saved yet"), systemImage: "bookmark")
                    } description: {
                        Text(store.language.text(
                            "每天翻開今日指引後，可以把想留下的那一張收藏在這裡。",
                            "매일 오늘의 메시지를 펼친 뒤 간직하고 싶은 카드를 여기에 저장할 수 있어요.",
                            "After revealing today's guidance, save any card you'd like to keep here."
                        ))
                    }
                    .foregroundStyle(.white)
                }
            } else {
                List {
                    Section {
                        ForEach(store.savedGuides) { guide in
                            NavigationLink {
                                SavedGuideDetailView(guide: guide)
                            } label: {
                                SavedGuideRow(guide: guide)
                            }
                            .listRowBackground(Color.white.opacity(0.94))
                        }
                        .onDelete(perform: store.removeSavedGuides)
                    } footer: {
                        Text(store.language.text(
                            "收藏最多保留 30 張。正式帳號會同步，本機預覽只留在這部裝置；向左滑動可以刪除。",
                            "저장한 카드는 최대 30개까지 보관돼요. 정식 계정은 동기화하고, 기기 미리보기는 이 기기에만 남아요. 왼쪽으로 밀어 삭제할 수 있어요.",
                            "Up to 30 saved cards are kept. Verified accounts sync them; local previews keep them on this device. Swipe left to delete."
                        ))
                        .foregroundStyle(.white.opacity(0.68))
                    }
                }
                .scrollContentBackground(.hidden)
                .background { CelestialBackdrop().ignoresSafeArea() }
            }
        }
        .navigationTitle(store.language.text("收藏的指引", "저장한 메시지", "Saved Guidance"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct SavedGuideRow: View {
    @EnvironmentObject private var store: AppStore
    let guide: DailyGuide

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(Color.celestialPlum)
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.celestialGold)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(guide.localizedTitle(in: store.language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.celestialNight)
                    .lineLimit(2)
                Text(
                    "\(guide.dateStamp) · \(guide.localizedZodiacName(in: store.language))"
                        + " · \(guide.localizedCardName(in: store.language))"
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

private struct SavedGuideDetailView: View {
    @EnvironmentObject private var store: AppStore
    let guide: DailyGuide

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image("LuckyStarTarot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 190)
                    .accessibilityHidden(true)

                Text("\(guide.dateStamp) · \(guide.localizedZodiacName(in: store.language))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.celestialGold)
                Text(guide.localizedTitle(in: store.language))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(guide.localizedMessage(in: store.language))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .foregroundStyle(.white.opacity(0.78))

                HStack(spacing: 10) {
                    detailChip(
                        store.language.text(
                            "幸運色：\(guide.localizedLuckyColor(in: store.language))",
                            "행운색: \(guide.localizedLuckyColor(in: store.language))",
                            "Lucky color: \(guide.localizedLuckyColor(in: store.language))"
                        ),
                        symbol: "paintpalette.fill"
                    )
                    detailChip(store.language.text("幸運時刻：\(guide.luckyTime)", "행운의 시간: \(guide.luckyTime)", "Lucky time: \(guide.luckyTime)"), symbol: "clock.fill")
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: 620)
            .padding(24)
        }
        .background { CelestialBackdrop().ignoresSafeArea() }
        .navigationTitle(store.language.text("收藏指引", "저장한 메시지", "Saved Guidance"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func detailChip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(.white.opacity(0.12), in: .rect(cornerRadius: 15))
    }
}
