import ActivityKit
import Foundation

struct StarPetActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let food: Int
        let status: String
        let languageCode: String?
    }

    let planetID: String
}

@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    /// ActivityKit updates are system work.  Keeping the latest payload lets us
    /// avoid waking the Live Activity for repeated taps that do not change it.
    private var lastState: StarPetActivityAttributes.ContentState?
    private var lastUpdateDate: Date?
    private var delayedUpdateTask: Task<Void, Never>?
    private let minimumUpdateInterval: TimeInterval = 15

    private init() {}

    func sync(food: Int, status: String, language: AppLanguage, allowsNewActivity: Bool) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = StarPetActivityAttributes.ContentState(
            food: food,
            status: status,
            languageCode: language.rawValue
        )
        guard state != lastState else { return }

        // iOS already rate-limits Live Activities.  Applying a small local
        // coalescing window prevents rapid taps from doing unnecessary work.
        if let lastUpdateDate {
            let elapsed = Date.now.timeIntervalSince(lastUpdateDate)
            if elapsed < minimumUpdateInterval {
                scheduleDelayedSync(
                    food: food,
                    status: status,
                    language: language,
                    allowsNewActivity: allowsNewActivity,
                    after: minimumUpdateInterval - elapsed
                )
                return
            }
        }
        let content = ActivityContent(state: state, staleDate: nil)

        if let current = Activity<StarPetActivityAttributes>.activities.first {
            await current.update(content)
            lastState = state
            lastUpdateDate = .now
            return
        }

        // Do not create a persistent Live Activity simply because the app
        // launches. It is started only by an intentional pet interaction.
        guard allowsNewActivity else { return }

        do {
            _ = try Activity.request(
                attributes: StarPetActivityAttributes(planetID: "demo-planet"),
                content: content,
                pushType: nil
            )
            lastState = state
            lastUpdateDate = .now
        } catch {
            // Live Activities can be disabled by the user or unavailable on a device.
        }
    }

    func end(language: AppLanguage) async {
        let finalState = StarPetActivityAttributes.ContentState(
            food: 0,
            status: language.text("小星回到星球休息了", "작은 별이 별로 돌아가 쉬고 있어요", "Little Star is back on the planet, resting"),
            languageCode: language.rawValue
        )
        let finalContent = ActivityContent(state: finalState, staleDate: nil)
        for activity in Activity<StarPetActivityAttributes>.activities {
            await activity.end(finalContent, dismissalPolicy: .immediate)
        }
        lastState = nil
        lastUpdateDate = nil
        delayedUpdateTask?.cancel()
        delayedUpdateTask = nil
    }

    private func scheduleDelayedSync(
        food: Int,
        status: String,
        language: AppLanguage,
        allowsNewActivity: Bool,
        after delay: TimeInterval
    ) {
        delayedUpdateTask?.cancel()
        delayedUpdateTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.sync(
                food: food,
                status: status,
                language: language,
                allowsNewActivity: allowsNewActivity
            )
        }
    }
}
