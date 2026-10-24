import ActivityKit
import SwiftUI
import WidgetKit

struct StarPetActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let food: Int
        let status: String
        let languageCode: String?
    }

    let planetID: String
}

struct StarPetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StarPetActivityAttributes.self) { context in
            HStack(spacing: 12) {
                petImage(size: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(copy(for: context.state).companionTitle)
                        .font(.headline)
                    Text(context.state.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ProgressView(value: Double(context.state.food), total: 100)
                        .tint(Color.starRose)
                }

                Text("\(context.state.food)")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.starPlum)
                    .contentTransition(.numericText())
            }
            .padding()
            .activityBackgroundTint(.starPaper)
            .activitySystemActionForegroundColor(.starPlum)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    petImage(size: 36)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy(for: context.state).companionTitle)
                            .font(.headline)
                        Text(context.state.status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(spacing: 0) {
                        Text("\(context.state.food)")
                            .font(.title3.weight(.semibold))
                            .contentTransition(.numericText())
                        Text(copy(for: context.state).foodLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: Double(context.state.food), total: 100)
                        .tint(Color.starRose)
                }
            } compactLeading: {
                petImage(size: 22)
            } compactTrailing: {
                Text("\(context.state.food)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.starGold)
                    .contentTransition(.numericText())
            } minimal: {
                petImage(size: 22)
            }
            .keylineTint(Color.starRose)
        }
    }

    private func petImage(size: CGFloat) -> some View {
        Image("StarPetIsland")
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private func copy(for state: StarPetActivityAttributes.ContentState) -> LiveActivityCopy {
        LiveActivityCopy(languageCode: state.languageCode)
    }
}

private struct LiveActivityCopy {
    let languageCode: String?

    var companionTitle: String {
        text("小星正在陪你", "작은 별이 곁에 있어요", "Little Star is with you")
    }

    var foodLabel: String {
        text("星糧", "별빛", "Starlight")
    }

    private func text(_ traditionalChinese: String, _ korean: String, _ english: String) -> String {
        switch languageCode {
        case "ko": korean
        case "en": english
        default: traditionalChinese
        }
    }
}

private extension Color {
    static let starPaper = Color(red: 1.00, green: 0.992, blue: 0.976)
    static let starPlum = Color(red: 0.29, green: 0.21, blue: 0.28)
    static let starRose = Color(red: 0.63, green: 0.44, blue: 0.53)
    static let starGold = Color(red: 1.00, green: 0.84, blue: 0.47)
}

@main
struct StarPetLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        StarPetLiveActivity()
    }
}
