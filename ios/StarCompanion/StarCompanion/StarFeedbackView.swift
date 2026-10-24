import SwiftUI

struct StarFeedbackView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("xingban.ios.feedback-draft.v1") private var draft = ""
    @AppStorage("xingban.ios.feedback-category.v1") private var categoryValue = FeedbackCategory.idea.rawValue
    @FocusState private var editorFocused: Bool

    private var category: FeedbackCategory {
        FeedbackCategory(rawValue: categoryValue) ?? .idea
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image("StarPetCelebrate")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 76, height: 76)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.language.text("你的想法，小星會好好看", "당신의 생각을 꼬꼬마 별이 잘 읽을게요", "Little Star is listening"))
                            .font(.headline)
                        Text(store.language.text("想加什麼、哪裡不順手，都可以直接說。", "추가하고 싶은 기능이나 불편한 점을 편하게 알려 주세요.", "Tell us what you'd like to add or what isn't working well."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(store.language.text("這次想說什麼？", "어떤 얘기를 남길까요?", "What's on your mind?")) {
                Picker(store.language.text("類別", "종류", "Category"), selection: $categoryValue) {
                    ForEach(FeedbackCategory.allCases) { item in
                        Label(item.title(in: store.language), systemImage: item.symbol)
                            .tag(item.rawValue)
                    }
                }
            }

            Section {
                TextEditor(text: $draft)
                    .focused($editorFocused)
                    .frame(minHeight: 180)
                    .onChange(of: draft) { _, newValue in
                        if newValue.count > 500 {
                            draft = String(newValue.prefix(500))
                        }
                    }

                HStack {
                    Text(store.language.text("例如：我希望情侶星球可以一起養第二隻星寵。", "예: 커플 행성에서 두 번째 별친구를 함께 키우고 싶어요.", "For example: I'd love to raise a second star pet together."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text("\(draft.count)/500")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(store.language.text("留給我們的話", "우리에게 남길 말", "Your message"))
            }

            Section {
                if trimmedDraft.isEmpty {
                    Label(store.language.text("寫完就可以傳送", "작성하면 보낼 수 있어요", "Write something to send it"), systemImage: "paperplane.fill")
                        .foregroundStyle(.secondary)
                } else {
                    ShareLink(item: shareText) {
                        Label(store.language.text("選擇傳送方式", "보낼 방법 선택", "Choose how to send"), systemImage: "paperplane.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.celestialPlum)
                }
            } footer: {
                Text(store.language.text(
                    "只有你按下傳送後，內容才會交給你選的 App。星伴不會在背景上傳，草稿只存在這部裝置。",
                    "보내기를 누른 후에만 내용이 선택한 앱으로 전달됩니다. 별친구는 백그라운드에서 업로드하지 않으며, 초안은 이 기기에만 저장됩니다.",
                    "Your message only leaves this device after you tap Send and choose an app. Star Companion never uploads it in the background."
                ))
            }
        }
        .scrollContentBackground(.hidden)
        .background { CelestialBackdrop().opacity(0.12).ignoresSafeArea() }
        .navigationTitle(store.language.text("給小星的回饋", "꼬꼬마 별에게 남기기", "Feedback for Little Star"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(store.language.text("完成", "완료", "Done")) {
                    editorFocused = false
                }
            }
        }
    }

    private var shareText: String {
        store.language.text(
            """
            給星伴團隊的回饋

            類別：\(category.title(in: store.language))
            \(trimmedDraft)

            — 從星伴 iOS App 傳送
            """,
            """
            별친구 팀에 보내는 피드백

            종류: \(category.title(in: store.language))
            \(trimmedDraft)

            — 별친구 iOS 앱에서 보냄
            """,
            """
            Feedback for the Star Companion team

            Category: \(category.title(in: store.language))
            \(trimmedDraft)

            — Sent from the Star Companion iOS app
            """
        )
    }
}

private enum FeedbackCategory: String, CaseIterable, Identifiable {
    case idea
    case friction
    case fortune
    case companionship
    case other

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .idea: language.text("想加一個功能", "새 기능 제안", "Feature idea")
        case .friction: language.text("有點不順手", "불편한 점", "Something feels off")
        case .fortune: language.text("運勢與塔羅", "운세와 타로", "Fortunes & tarot")
        case .companionship: language.text("星寵、情侶與閨蜜", "별친구·커플·절친", "Star pets, couples & besties")
        case .other: language.text("其他想說的", "기타", "Something else")
        }
    }

    var symbol: String {
        switch self {
        case .idea: "lightbulb.fill"
        case .friction: "wrench.and.screwdriver.fill"
        case .fortune: "sparkles"
        case .companionship: "heart.fill"
        case .other: "ellipsis.bubble.fill"
        }
    }
}
