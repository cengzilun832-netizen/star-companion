import SwiftUI

struct ReadingHistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""

    private var filteredReadings: [TarotReadingRecord] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return store.readingHistory
        }
        return store.readingHistory.filter { reading in
            [
                reading.localizedTopicTitle(in: store.language),
                reading.localizedQuestion(in: store.language),
                reading.cardTitle(in: store.language),
                reading.localizedAnswer(in: store.language),
                reading.localizedDetail(in: store.language),
                reading.localizedKeywords(in: store.language) ?? "",
            ].contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        Group {
            if store.readingHistory.isEmpty {
                emptyState
            } else if filteredReadings.isEmpty {
                noSearchResults
            } else {
                readingList
            }
        }
        .navigationTitle(store.language.text("抽牌紀錄", "카드 기록", "Card History"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: store.language.text("搜尋問題、牌或回信", "질문, 카드 또는 답장 검색", "Search questions, cards, or replies")
        )
    }

    private var readingList: some View {
        List {
            Section {
                ForEach(filteredReadings) { reading in
                    NavigationLink {
                        ReadingDetailView(reading: reading)
                    } label: {
                        ReadingHistoryRow(reading: reading)
                    }
                    .listRowBackground(Color.white.opacity(0.94))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.deleteReading(id: reading.id)
                        } label: {
                            Label(store.language.text("刪除", "삭제", "Delete"), systemImage: "trash")
                        }
                    }
                }
            } footer: {
                Text(store.language.text(
                    "回信最多保留 50 封。正式帳號會同步，本機預覽只留在這部裝置。",
                    "답장은 최대 50개까지 보관돼요. 정식 계정은 동기화하고, 기기 미리보기는 이 기기에만 남아요.",
                    "Up to 50 replies are kept. Verified accounts sync them; local previews keep them on this device."
                ))
                .foregroundStyle(.white.opacity(0.68))
            }
        }
        .scrollContentBackground(.hidden)
        .background { CelestialBackdrop().ignoresSafeArea() }
    }

    private var emptyState: some View {
        ZStack {
            CelestialBackdrop().ignoresSafeArea()
            ContentUnavailableView {
                Label(store.language.text("還沒有抽牌紀錄", "아직 뽑은 카드가 없어요", "No card readings yet"), systemImage: "rectangle.portrait.on.rectangle.portrait")
            } description: {
                Text(store.language.text(
                    "選一個主題，再抽一張牌。完成後會自動存到這裡。",
                    "주제를 고르고 카드를 한 장 뽑아 보세요. 완료하면 여기에 자동으로 저장돼요.",
                    "Choose a topic and draw a card. Your reading will appear here when you're done."
                ))
            }
            .foregroundStyle(.white)
        }
    }

    private var noSearchResults: some View {
        ZStack {
            CelestialBackdrop().ignoresSafeArea()
            ContentUnavailableView.search(text: searchText)
                .foregroundStyle(.white)
        }
    }
}

private struct ReadingHistoryRow: View {
    @EnvironmentObject private var store: AppStore
    let reading: TarotReadingRecord

    var body: some View {
        HStack(spacing: 13) {
            if let snapshot = reading.appearanceSnapshot {
                SnapshotStarView(snapshot: snapshot, size: 46)
            } else {
                ZStack {
                    Circle().fill(Color.celestialPlum)
                    Image(systemName: reading.cardSymbol ?? "sparkles")
                        .foregroundStyle(Color.celestialGold)
                }
                .frame(width: 46, height: 46)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(reading.localizedAnswer(in: store.language))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.celestialNight)
                    .lineLimit(1)
                Text(reading.localizedQuestion(in: store.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(
                    "\(reading.localizedTopicTitle(in: store.language))"
                        + " · \(reading.cardTitle(in: store.language)) · \(dateText)"
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var dateText: String {
        reading.createdAt.formatted(.dateTime.month().day().locale(store.language.locale))
    }
}

struct SnapshotStarView: View {
    let snapshot: StarAppearanceSnapshot
    let size: CGFloat

    private var assetName: String {
        if let collectionSkin = StarSkinCatalog.item(id: snapshot.personaID) {
            return collectionSkin.assetName
        }
        let persona = snapshot.personaID.flatMap(StarPersona.init(rawValue:)) ?? .classic
        return persona.assetName
    }

    private var aura: StarAura {
        snapshot.auraID.flatMap(StarAura.init(rawValue:)) ?? .classic
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(auraColor.opacity(0.22))
                .blur(radius: size * 0.07)
            Image(assetName)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var auraColor: Color {
        switch aura {
        case .classic: .celestialGold
        case .moonlit: .celestialLavender
        case .sunrise: .orange
        case .rose: .celestialPink
        case .nebula: .purple
        }
    }
}

struct ReadingDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var deleteConfirmationPresented = false

    let reading: TarotReadingRecord

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let snapshot = reading.appearanceSnapshot {
                    SnapshotStarView(snapshot: snapshot, size: 220)
                } else {
                    Image("LuckyStarCelebrate")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220)
                        .shadow(color: Color.celestialPink.opacity(0.22), radius: 22, y: 10)
                        .accessibilityHidden(true)
                }

                Image(systemName: reading.cardSymbol ?? "sparkles")
                    .font(.title2)
                    .foregroundStyle(Color.celestialGold)
                    .accessibilityHidden(true)
                Text(reading.cardTitle(in: store.language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.celestialGold)
                if let keywords = reading.localizedKeywords(in: store.language) {
                    Text(keywords)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.09), in: .capsule)
                }
                Text(reading.localizedTopicTitle(in: store.language))
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.60))
                Text("「\(reading.localizedQuestion(in: store.language))」")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.72))
                Text(reading.localizedAnswer(in: store.language))
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(reading.localizedDetail(in: store.language))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .foregroundStyle(.white.opacity(0.78))

                Label(
                    store.language.text(
                        "抽牌運算在本機完成。正式帳號只會把完成後的塔羅紀錄同步到帳號服務。",
                        "카드 뽑기 연산은 기기에서 완료됩니다. 정식 계정은 완료된 타로 기록만 계정 서비스와 동기화합니다.",
                        "The card draw is calculated on your device. Verified accounts sync only the completed tarot record to the account service."
                    ),
                    systemImage: "lock.shield.fill"
                )
                .font(.caption)
                .foregroundStyle(.white.opacity(0.68))
                .padding(16)
                .background(.white.opacity(0.09), in: .rect(cornerRadius: 17))

                ShareLink(item: reading.shareText(in: store.language)) {
                    Label(store.language.text("分享這封回信", "이 답장 공유하기", "Share this reading"), systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.celestialPlum)

                Text(store.language.text(
                    "內容僅供娛樂與自我探索，不代替醫療、法律或投資等專業建議。",
                    "내용은 오락과 자기 탐색을 위한 것이며 의료, 법률, 투자 등의 전문 조언을 대신하지 않아요.",
                    "For entertainment and self-reflection only. Not a substitute for medical, legal, or financial advice."
                ))
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.50))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: 640)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .background { CelestialBackdrop().ignoresSafeArea() }
        .navigationTitle(store.language.text("牌義", "카드 해석", "Card Meaning"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: reading.shareText(in: store.language)) {
                    Image(systemName: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    deleteConfirmationPresented = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog(
            store.language.text("刪除這封回信？", "이 답장을 삭제할까요?", "Delete this reading?"),
            isPresented: $deleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(store.language.text("刪除", "삭제", "Delete"), role: .destructive) {
                store.deleteReading(id: reading.id)
                dismiss()
            }
            Button(store.language.text("取消", "취소", "Cancel"), role: .cancel) {}
        }
    }
}
