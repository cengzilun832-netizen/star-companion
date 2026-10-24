import Foundation
import SwiftUI

struct PersonalizationSetupView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isOnboarding: Bool

    @State private var step = 0
    @State private var displayName = ""
    @State private var birthDate = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? .now
    @State private var hasBirthTime = false
    @State private var birthTime = Calendar.current.date(from: DateComponents(hour: 12, minute: 0)) ?? .now
    @State private var birthPlace = ""
    @State private var focuses: Set<FortuneFocus> = [.wellbeing]
    @State private var hydrated = false

    var body: some View {
        NavigationStack {
            Form {
                if step == 0 {
                    identityStep
                } else {
                    detailStep
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.profilePaper)
            .navigationTitle(step == 0
                             ? store.language.text("認識你", "당신을 알아가기", "About You")
                             : store.language.text("你的關注", "당신의 관심사", "Your Interests"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isOnboarding
                           ? store.language.text("稍後", "나중에", "Later")
                           : store.language.text("取消", "취소", "Cancel"),
                           action: dismiss.callAsFunction)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: advance) {
                    Label(
                        step == 0
                            ? store.language.text("下一步", "다음", "Next")
                            : store.language.text("完成設定", "설정 완료", "Finish setup"),
                        systemImage: step == 0 ? "arrow.right" : "sparkles"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .celestialGlassButtonStyle(prominent: true)
                .tint(Color.profilePlum)
                .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .task { hydrateOnce() }
        }
    }

    private var identityStep: some View {
        Group {
            Section {
                HStack(spacing: 16) {
                    Image("LuckyStarSleep")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 84, height: 84)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.language.text("先留下兩個線索", "두 가지 단서부터 남겨 주세요", "Start with two little clues"))
                            .font(.headline)
                        Text(store.language.text("稱呼用於 App 內文案，生日用來推算太陽星座。", "이름은 앱 안의 문구에, 생일은 태양 별자리를 계산하는 데 사용해요.", "Your name personalizes the app, and your birthday determines your sun sign."))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .foregroundStyle(.white)
                .padding(16)
                .background { CelestialCardBackground() }
                .clipShape(.rect(cornerRadius: 20))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section(store.language.text("稱呼", "이름", "Name")) {
                TextField(store.language.text("希望小星怎麼稱呼你？", "작은 별이 뭐라고 부르면 좋을까요?", "What should Little Star call you?"), text: $displayName)
                    .textContentType(.nickname)
                    .submitLabel(.done)
            }

            Section {
                DatePicker(
                    store.language.text("出生日期", "생년월일", "Date of birth"),
                    selection: $birthDate,
                    in: ...Date.now,
                    displayedComponents: .date
                )
                LabeledContent(
                    store.language.text("太陽星座", "태양 별자리", "Sun sign"),
                    value: ZodiacSign.sign(for: birthDate).symbol + " " + ZodiacSign.sign(for: birthDate).title(in: store.language)
                )
            } header: {
                Text(store.language.text("生日", "생일", "Birthday"))
            } footer: {
                Text(store.language.text("出生日期會保存在目前帳號；正式帳號會同步到其他裝置，本機預覽只留在這部裝置。你可隨時修改或刪除。", "생년월일은 현재 계정에 보관됩니다. 정식 계정은 다른 기기와 동기화하고, 기기 미리보기는 이 기기에만 남아요. 언제든 수정하거나 삭제할 수 있어요.", "Your date of birth is saved to the current account. Verified accounts sync it to other devices; local previews keep it on this device. You can change or delete it at any time."))
            }
        }
    }

    private var detailStep: some View {
        Group {
            Section {
                Toggle(
                    store.language.text("加入出生時間", "출생 시간 추가", "Add birth time"),
                    isOn: reduceMotion ? $hasBirthTime : $hasBirthTime.animation()
                )
                if hasBirthTime {
                    DatePicker(
                        store.language.text("出生時間", "출생 시간", "Birth time"),
                        selection: $birthTime,
                        displayedComponents: .hourAndMinute
                    )
                }
                TextField(store.language.text("出生城市（選填）", "출생 도시 (선택)", "Birth city (optional)"), text: $birthPlace)
                    .textContentType(.addressCity)
            } header: {
                Text(store.language.text("更多線索（選填）", "추가 단서(선택)", "More Clues (Optional)"))
            } footer: {
                Text(store.language.text("這些資料目前只用於未來的月亮與上升星座計算。", "이 정보는 향후 달 별자리와 상승궁 계산에만 사용될 예정이에요.", "These details are reserved for future moon and rising sign calculations."))
            }

            Section {
                ForEach(FortuneFocus.allCases) { focus in
                    Button {
                        toggle(focus)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: focus.symbol)
                                .foregroundStyle(Color.profileRose)
                                .frame(width: 26)
                            Text(focus.title(in: store.language))
                            Spacer()
                            Image(systemName: focuses.contains(focus) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(focuses.contains(focus) ? Color.profilePlum : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(focuses.contains(focus) ? .isSelected : [])
                }
            } header: {
                Text(store.language.text("最近想關注什麼？最多三項", "요즘 무엇이 궁금한가요? 최대 3개", "What matters to you lately? Choose up to three."))
            }

            Section {
                Label {
                    Text(store.language.text(
                        "出生資料用來產生個人化運勢。正式帳號會跟著帳號同步；本機預覽只保存在這部裝置。",
                        "출생 정보는 개인화된 운세를 만드는 데 사용됩니다. 정식 계정은 계정을 따라 동기화하고, 기기 미리보기는 이 기기에만 보관합니다.",
                        "Birth details are used to create personalized fortunes. Verified accounts sync them with the account; local previews keep them on this device."
                    ))
                } icon: {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(Color.profilePlum)
                }
            }
        }
    }

    private func hydrateOnce() {
        guard !hydrated else { return }
        hydrated = true

        guard let profile = store.profile else {
            displayName = store.user?.displayName ?? ""
            return
        }

        displayName = profile.displayName
        birthDate = profile.birthDate
        birthPlace = profile.birthPlace
        focuses = Set(profile.focuses)

        if let minutes = profile.birthTimeMinutes {
            hasBirthTime = true
            birthTime = Calendar.current.date(
                from: DateComponents(hour: minutes / 60, minute: minutes % 60)
            ) ?? birthTime
        }
    }

    private func toggle(_ focus: FortuneFocus) {
        if focuses.contains(focus) {
            focuses.remove(focus)
        } else if focuses.count < 3 {
            focuses.insert(focus)
        }
    }

    private func advance() {
        if step == 0 {
            if reduceMotion {
                step = 1
            } else {
                withAnimation(.easeInOut(duration: 0.22)) { step = 1 }
            }
            return
        }

        let timeParts = Calendar.current.dateComponents([.hour, .minute], from: birthTime)
        let minutes = hasBirthTime ? (timeParts.hour ?? 0) * 60 + (timeParts.minute ?? 0) : nil
        store.saveProfile(BirthProfile(
            displayName: displayName,
            birthDate: birthDate,
            birthTimeMinutes: minutes,
            birthPlace: birthPlace,
            focuses: FortuneFocus.allCases.filter(focuses.contains)
        ))
        dismiss()
    }
}

struct ProfileSummaryCard: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 16) {
            Image("LuckyStarSleep")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                if let profile = store.profile {
                    Text(profile.zodiac.symbol + " " + profile.zodiac.title(in: store.language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.celestialGold)
                    Text(profile.displayName)
                        .font(.title2.bold())
                    Text(store.language.text("你的星象資料已保存在目前帳號", "별자리 정보가 현재 계정에 저장되어 있어요", "Your astrology details are saved to the current account"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                } else {
                    Text(store.language.text("等待與你相遇", "당신을 기다리고 있어요", "Waiting to meet you"))
                        .font(.title3.bold())
                    Text(store.language.text("完成出生資料，打開個人運勢。", "출생 정보를 입력하고 개인 운세를 열어 보세요.", "Add your birth details to unlock personalized fortunes."))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background { CelestialCardBackground() }
        .clipShape(.rect(cornerRadius: 20))
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}

private extension Color {
    static let profilePaper = Color(red: 0.985, green: 0.965, blue: 0.975)
    static let profilePlum = Color(red: 0.45, green: 0.25, blue: 0.48)
    static let profileRose = Color(red: 0.69, green: 0.39, blue: 0.53)
}
