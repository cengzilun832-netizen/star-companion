import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct BondRitualCard: View {
    @EnvironmentObject private var store: AppStore
    @State private var checkInPresented = false
    @State private var historyPresented = false

    private var relationship: StarRelationship { store.planet.currentRelationship }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                HStack(spacing: -8) {
                    Image("StarPet")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 46, height: 46)
                    Image("LuckyStarCelebrate")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 46, height: 46)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Label(relationship.title(in: store.language), systemImage: relationship.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(relationship == .couple ? Color.celestialPink : Color.celestialGold)
                    Text(store.language.text("今日雙星時刻", "오늘의 두 별 시간", "Today's Two-Star Moment"))
                        .font(.headline)
                }
                Spacer()
            }

            Text(relationship.dailyPrompt(in: store.language))
                .font(.title3.weight(.semibold))
                .lineSpacing(3)

            Button {
                historyPresented = true
            } label: {
                BondConstellationStrip(showsDisclosure: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(store.language.text("打開雙星記憶", "두 별의 기억 열기", "Open your shared star memories"))

            if store.hasBondCheckInToday, let mood = store.planet.bondMood {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: mood.symbol)
                        .font(.title3)
                        .foregroundStyle(relationshipAccent)
                        .frame(width: 38, height: 38)
                        .celestialSurface(
                            Color.white.opacity(0.12),
                            in: Circle(),
                            reducedColor: .celestialSurfaceElevated
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(mood.title(in: store.language))
                            .font(.subheadline.weight(.semibold))
                        if let note = store.planet.bondNote, !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.celestialGold)
                }
                .padding(12)
                .celestialSurface(
                    Color.white.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 16),
                    reducedColor: .celestialSurfaceElevated
                )
            }

            Button {
                checkInPresented = true
            } label: {
                Label(
                    store.hasBondCheckInToday
                        ? store.language.text("更新今天的心情", "오늘의 마음 업데이트", "Update today's mood")
                        : store.language.text("留下今天的心情", "오늘의 마음 남기기", "Add today's mood"),
                    systemImage: store.hasBondCheckInToday ? "pencil" : "heart.text.square.fill"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
            }
            .celestialGlassButtonStyle(prominent: true)
            .tint(relationshipAccent)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background { CelestialCardBackground() }
        .clipShape(.rect(cornerRadius: 24))
        .shadow(color: Color.celestialPlum.opacity(0.18), radius: 18, y: 8)
        .sheet(isPresented: $checkInPresented) {
            BondCheckInSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $historyPresented) {
            BondMemoryHistorySheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.success, trigger: store.bondSavePulse)
        .accessibilityElement(children: .contain)
    }

    private var relationshipAccent: Color {
        relationship.bondAccent
    }
}

private struct BondConstellationStrip: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let showsDisclosure: Bool

    private var relationship: StarRelationship { store.planet.currentRelationship }
    private var days: [Date] {
        let calendar = Calendar.current
        return (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: .now) }
    }

    var body: some View {
        let completedIndexes = Set(days.enumerated().compactMap { index, date in
            store.bondMemory(on: date) == nil ? nil : index
        })

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(relationship.constellationTitle(in: store.language), systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption.weight(.semibold))
                Spacer()
                if store.bondStreak > 0 {
                    Text(store.language.text("連續 \(store.bondStreak) 天", "\(store.bondStreak)일 연속", "\(store.bondStreak)-day streak"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .celestialSurface(
                            relationship.bondAccent.opacity(0.22),
                            in: Capsule(),
                            reducedColor: .celestialSurfaceElevated,
                            reducedBoundaryColor: relationship.bondAccent.opacity(0.78)
                        )
                }
                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.48))
                }
            }

            ZStack(alignment: .top) {
                Canvas { context, size in
                    let step = size.width / CGFloat(max(days.count, 1))
                    let points = days.indices.compactMap { index -> CGPoint? in
                        guard completedIndexes.contains(index) else { return nil }
                        return CGPoint(x: step * (CGFloat(index) + 0.5), y: 17)
                    }

                    guard let first = points.first else { return }
                    var path = Path()
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                    context.stroke(
                        path,
                        with: .color(relationship.bondAccent.opacity(0.68)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 4])
                    )
                }
                .frame(height: 34)
                .accessibilityHidden(true)

                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { date in
                        dayNode(for: date)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            Text(store.currentBondMemories.isEmpty
                 ? store.language.text("留下一個心情，點亮今天這顆星。", "마음을 하나 남기고 오늘의 별을 밝혀 보세요.", "Leave a mood and light up today's star.")
                 : store.language.text("每次留下心情，星圖就會多亮一點。", "마음을 남길 때마다 별자리가 조금 더 빛나요.", "Every mood you leave makes the constellation a little brighter."))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(13)
        .celestialSurface(
            Color.white.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 17)
        )
        .contentShape(.rect(cornerRadius: 17))
    }

    private func dayNode(for date: Date) -> some View {
        let memory = store.bondMemory(on: date)
        let isToday = Calendar.current.isDateInToday(date)
        let weekday = date.formatted(.dateTime.weekday(.narrow).locale(store.language.locale))

        return VStack(spacing: 5) {
            Image(systemName: memory?.mood.symbol ?? "star")
                .font(.caption.weight(.bold))
                .foregroundStyle(memory == nil ? .white.opacity(0.42) : .white)
                .frame(width: 34, height: 34)
                .celestialSurface(
                    memory == nil ? Color.white.opacity(0.06) : relationship.bondAccent,
                    in: Circle(),
                    reducedColor: memory == nil ? .celestialSurfaceElevated : relationship.bondAccent
                )
                .overlay {
                    Circle().stroke(
                        isToday ? Color.celestialGold.opacity(0.95) : .white.opacity(0.16),
                        lineWidth: isToday ? 1.5 : 1
                    )
                }
                .modifier(BondSaveBounceModifier(
                    isEnabled: isToday && !reduceMotion,
                    value: store.bondSavePulse
                ))
            Text(weekday)
                .font(.system(size: 9, weight: isToday ? .bold : .medium))
                .foregroundStyle(isToday ? Color.celestialGold : .white.opacity(0.54))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayAccessibilityLabel(date: date, memory: memory))
    }

    private func dayAccessibilityLabel(date: Date, memory: BondMemory?) -> String {
        let dateText = date.formatted(.dateTime.month().day().weekday().locale(store.language.locale))
        guard let memory else {
            return store.language.text("\(dateText)，沒有紀錄", "\(dateText), 기록 없음", "\(dateText), no entry")
        }
        let separator = store.language == .traditionalChinese ? "，" : ", "
        return "\(dateText)\(separator)\(memory.mood.title(in: store.language))"
    }
}

private struct BondMemoryHistorySheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var shareItem: BondShareItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    BondConstellationStrip(showsDisclosure: false)
                        .foregroundStyle(.white)
                        .background { CelestialCardBackground() }
                        .clipShape(.rect(cornerRadius: 20))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if store.currentBondMemories.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label(store.language.text("還沒有亮起來", "아직 빛난 별이 없어요", "No stars are lit yet"), systemImage: "star")
                        } description: {
                            Text(store.language.text("完成今天的雙星時刻，第一顆星就會出現。", "오늘의 두 별 시간을 마치면 첫 번째 별이 나타나요.", "Complete today's two-star moment and your first star will appear."))
                        }
                    }
                } else {
                    Section {
                        ForEach(store.currentBondMemories) { memory in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: memory.mood.symbol)
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .background(store.planet.currentRelationship.bondAccent, in: .circle)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(memory.mood.title(in: store.language))
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text(dateText(for: memory.dateStamp))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let note = memory.note, !note.isEmpty {
                                        Text(note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            .accessibilityElement(children: .combine)
                        }
                    } header: {
                        Text(store.language.text("最近的心情", "최근의 마음", "Recent moods"))
                    } footer: {
                        Text(store.language.text(
                            "最多保留 90 天。正式帳號會同步，本機預覽只留在這部裝置。",
                            "최대 90일 동안 보관돼요. 정식 계정은 동기화하고, 기기 미리보기는 이 기기에만 남아요.",
                            "Up to 90 days are kept. Verified accounts sync them; local previews keep them on this device."
                        ))
                    }
                }
            }
            .navigationTitle(store.planet.currentRelationship.constellationTitle(in: store.language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let shareItem {
                        ShareLink(
                            item: shareItem,
                            preview: SharePreview(
                                store.planet.currentRelationship.constellationTitle(in: store.language),
                                image: previewImage(for: shareItem)
                            )
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(store.language.text("分享雙星紀念卡", "두 별 기념 카드 공유", "Share your two-star keepsake"))
                    } else if !store.currentBondMemories.isEmpty {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(store.language.text("正在準備紀念卡", "기념 카드 준비 중", "Preparing your keepsake"))
                    }
                    Button(store.language.text("完成", "완료", "Done"), action: dismiss.callAsFunction)
                }
            }
            .task(id: "\(store.planet.currentRelationship.rawValue)-\(store.bondSavePulse)") {
                renderShareCard()
            }
        }
    }

    @MainActor
    private func renderShareCard() {
        guard !store.currentBondMemories.isEmpty else {
            shareItem = nil
            return
        }

        let calendar = Calendar.current
        let days = (-6...0).enumerated().compactMap { index, offset -> BondShareDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: .now) else { return nil }
            return BondShareDay(
                id: index,
                weekday: date.formatted(.dateTime.weekday(.narrow).locale(store.language.locale)),
                moodSymbol: store.bondMemory(on: date)?.mood.symbol,
                isToday: calendar.isDateInToday(date)
            )
        }
        let snapshot = BondShareSnapshot(
            relationship: store.planet.currentRelationship,
            language: store.language,
            streak: store.bondStreak,
            dateText: Date.now.formatted(
                .dateTime.year().month(.wide).day().locale(store.language.locale)
            ),
            days: days
        )
        let renderer = ImageRenderer(content:
            BondShareCardView(snapshot: snapshot)
                .frame(width: 360, height: 450)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = 3
        guard let data = renderer.uiImage?.pngData() else { return }
        shareItem = BondShareItem(data: data)
    }

    private func previewImage(for item: BondShareItem) -> Image {
        guard let image = UIImage(data: item.data) else { return Image(systemName: "sparkles") }
        return Image(uiImage: image)
    }

    private func dateText(for stamp: String) -> String {
        let values = stamp.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3,
              let date = Calendar.current.date(from: DateComponents(
                year: values[0], month: values[1], day: values[2]
              ))
        else { return stamp }
        return date.formatted(.dateTime.month(.abbreviated).day().locale(store.language.locale))
    }
}

private struct BondShareItem: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.data
        }
    }
}

private struct BondShareDay: Identifiable {
    let id: Int
    let weekday: String
    let moodSymbol: String?
    let isToday: Bool
}

private struct BondShareSnapshot {
    let relationship: StarRelationship
    let language: AppLanguage
    let streak: Int
    let dateText: String
    let days: [BondShareDay]
}

private struct BondShareCardView: View {
    let snapshot: BondShareSnapshot

    private var accent: Color { snapshot.relationship.bondAccent }
    private var litCount: Int { snapshot.days.filter { $0.moodSymbol != nil }.count }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.celestialNight, Color.celestialIndigo, Color.celestialPlum],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [accent.opacity(0.46), .clear],
                center: UnitPoint(x: 0.18, y: 0.16),
                startRadius: 4,
                endRadius: 230
            )

            Canvas { context, size in
                for index in 0..<46 {
                    let x = CGFloat((index * 43 + 11) % 101) / 100 * size.width
                    let y = CGFloat((index * 71 + 17) % 103) / 102 * size.height
                    let radius = CGFloat(index % 7 == 0 ? 1.7 : 0.8)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)),
                        with: .color((index % 6 == 0 ? Color.celestialGold : .white).opacity(0.72))
                    )
                }
            }

            VStack(spacing: 0) {
                HStack {
                    Label(snapshot.language.text("星伴", "별동무", "Star Companion"), systemImage: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.3)
                    Spacer()
                    Text(snapshot.dateText)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                }

                VStack(spacing: 5) {
                    Text(snapshot.relationship.constellationTitle(in: snapshot.language))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Label(
                        snapshot.relationship.title(in: snapshot.language),
                        systemImage: snapshot.relationship.symbol
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.celestialGold)
                }
                .padding(.top, 24)

                HStack(spacing: -10) {
                    Image("StarPet")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 112, height: 112)
                    Image("LuckyStarCelebrate")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 112, height: 112)
                }
                .shadow(color: accent.opacity(0.38), radius: 18, y: 8)
                .padding(.top, 5)

                Text(snapshot.relationship.shareCardTitle(in: snapshot.language))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.top, 2)

                shareConstellation
                    .padding(.top, 16)

                HStack(spacing: 6) {
                    Image(systemName: snapshot.streak > 0 ? "flame.fill" : "star.fill")
                    Text(summaryCopy)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(accent.opacity(0.62), in: .capsule)
                .padding(.top, 15)

                Spacer(minLength: 14)

                Text(snapshot.language.text("把平常的日子連成星星", "평범한 날들을 별자리로 이어요", "Connect ordinary days into stars"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.54))
            }
            .foregroundStyle(.white)
            .padding(24)
        }
        .clipShape(.rect(cornerRadius: 30))
    }

    private var shareConstellation: some View {
        let completedIndexes = Set(snapshot.days.compactMap { $0.moodSymbol == nil ? nil : $0.id })

        return ZStack(alignment: .top) {
            Canvas { context, size in
                let step = size.width / CGFloat(max(snapshot.days.count, 1))
                let points = snapshot.days.indices.compactMap { index -> CGPoint? in
                    guard completedIndexes.contains(index) else { return nil }
                    return CGPoint(x: step * (CGFloat(index) + 0.5), y: 15)
                }
                guard let first = points.first else { return }
                var path = Path()
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                context.stroke(
                    path,
                    with: .color(accent.opacity(0.82)),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 3])
                )
            }
            .frame(height: 30)

            HStack(spacing: 0) {
                ForEach(snapshot.days) { day in
                    VStack(spacing: 5) {
                        Image(systemName: day.moodSymbol ?? "star")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(day.moodSymbol == nil ? .white.opacity(0.38) : .white)
                            .frame(width: 30, height: 30)
                            .background(
                                day.moodSymbol == nil ? Color.white.opacity(0.08) : accent,
                                in: .circle
                            )
                            .overlay {
                                Circle().stroke(
                                    day.isToday ? Color.celestialGold : .white.opacity(0.18),
                                    lineWidth: day.isToday ? 1.5 : 1
                                )
                            }
                        Text(day.weekday)
                            .font(.system(size: 8, weight: day.isToday ? .bold : .medium))
                            .foregroundStyle(day.isToday ? Color.celestialGold : .white.opacity(0.52))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var summaryCopy: String {
        if snapshot.streak > 0 {
            return snapshot.language.text("連續 \(snapshot.streak) 天", "\(snapshot.streak)일 연속", "\(snapshot.streak)-day streak")
        }
        return snapshot.language.text("這週亮了 \(litCount) 顆星", "이번 주 \(litCount)개의 별", "\(litCount) stars lit this week")
    }
}

private struct BondCheckInSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMood: BondMood?
    @State private var note = ""
    @State private var hydrated = false

    private var relationship: StarRelationship { store.planet.currentRelationship }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack {
                        CelestialCardBackground()
                        VStack(spacing: 10) {
                            HStack(spacing: -6) {
                                Image("StarPet")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 70, height: 70)
                                Image("LuckyStarCelebrate")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 70, height: 70)
                            }
                            Text(relationship.dailyPrompt(in: store.language))
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white)
                        }
                        .padding(18)
                    }
                    .clipShape(.rect(cornerRadius: 22))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .combine)
                }

                Section(store.language.text("今天的心情", "오늘의 마음", "Today's Mood")) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(BondMood.allCases) { mood in
                            moodButton(mood)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    TextField(
                        store.language.text("寫一句想讓對方看見的話…", "서로에게 보여 주고 싶은 한마디…", "Write something you'd like them to see…"),
                        text: $note,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .onChange(of: note) { _, value in
                        if value.count > 60 { note = String(value.prefix(60)) }
                    }
                    Text("\(note.count)/60")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } header: {
                    Text(store.language.text("留給彼此的一句話（選填）", "서로에게 남기는 한마디(선택)", "A note for each other (optional)"))
                } footer: {
                    Text(store.language.text(
                        "心情與留言會保存在目前帳號，正式帳號會同步到你自己的裝置。不會自動傳給對方；將來開啟雙方共享前，會先取得同意。",
                        "마음과 메시지는 현재 계정에 보관되고, 정식 계정은 본인의 기기들과 동기화합니다. 상대에게 자동으로 전송하지 않으며, 향후 두 사람이 공유하는 기능을 켜기 전에 동의를 먼저 받을 거예요.",
                        "Moods and notes are saved to the current account, and verified accounts sync them across your own devices. They aren't sent to the other person automatically; shared syncing will ask for consent before it turns on."
                    ))
                }
            }
            .navigationTitle(store.language.text("今日雙星時刻", "오늘의 두 별 시간", "Today's Two-Star Moment"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.language.text("取消", "취소", "Cancel"), action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.language.text("保存", "저장", "Save"), action: save)
                        .disabled(selectedMood == nil)
                }
            }
            .task { hydrateOnce() }
        }
    }

    private func moodButton(_ mood: BondMood) -> some View {
        let isSelected = selectedMood == mood

        return Button {
            selectedMood = mood
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mood.symbol)
                    .font(.title3)
                Text(mood.title(in: store.language))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? .white : Color.celestialPlum)
            .frame(maxWidth: .infinity, minHeight: 72)
            .celestialSurface(
                isSelected ? Color.celestialPlum : Color.celestialPink.opacity(0.16),
                in: RoundedRectangle(cornerRadius: 16),
                reducedColor: isSelected
                    ? .celestialPlum
                    : Color(red: 0.96, green: 0.90, blue: 0.94),
                reducedBoundaryColor: isSelected
                    ? Color.white.opacity(0.55)
                    : Color.celestialPlum.opacity(0.58)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func hydrateOnce() {
        guard !hydrated else { return }
        hydrated = true
        guard store.hasBondCheckInToday else { return }
        selectedMood = store.planet.bondMood
        note = store.planet.bondNote ?? ""
    }

    private func save() {
        guard let selectedMood else { return }
        store.saveBondCheckIn(mood: selectedMood, note: note)
        dismiss()
    }
}

private struct BondSaveBounceModifier: ViewModifier {
    let isEnabled: Bool
    let value: Int

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.symbolEffect(.bounce, value: value)
        } else {
            content
        }
    }
}

private extension StarRelationship {
    var bondAccent: Color {
        switch self {
        case .friend: Color(red: 0.55, green: 0.45, blue: 0.86)
        case .bestie: Color(red: 0.82, green: 0.42, blue: 0.72)
        case .couple: Color(red: 0.91, green: 0.36, blue: 0.53)
        }
    }

    func constellationTitle(in language: AppLanguage) -> String {
        switch self {
        case .friend: language.text("同路星圖", "함께 걷는 별자리", "Shared Path")
        case .bestie: language.text("閨蜜星圖", "베프 별자리", "Bestie Constellation")
        case .couple: language.text("心動星圖", "설렘 별자리", "Heartfelt Constellation")
        }
    }

    func shareCardTitle(in language: AppLanguage) -> String {
        switch self {
        case .friend: language.text("一起走過的這一週", "함께 걸어온 이번 주", "The week you walked through together")
        case .bestie: language.text("這週也有彼此", "이번 주도 서로의 곁에", "Another week with each other close")
        case .couple: language.text("把這週的心動收好", "이번 주의 설렘을 간직해요", "Keep this week's little heartbeats")
        }
    }
}
