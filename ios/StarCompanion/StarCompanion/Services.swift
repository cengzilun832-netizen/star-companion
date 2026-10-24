import Foundation
import UserNotifications

protocol WeChatAuthenticating {
    func login() async throws -> WeChatUser
}

/// Keeps the native UI runnable before a WeChat Open Platform AppID is configured.
struct MockWeChatAuthService: WeChatAuthenticating {
    func login() async throws -> WeChatUser {
        try await Task.sleep(for: .milliseconds(450))
        return WeChatUser(openID: "wechat-demo-user", displayName: "星河")
    }
}

struct UnconfiguredWeChatAuthService: WeChatAuthenticating {
    func login() async throws -> WeChatUser {
        throw WeChatSignInServiceError.notConfigured
    }
}

enum DefaultWeChatAuthService {
    static func make() -> any WeChatAuthenticating {
        #if DEBUG
        MockWeChatAuthService()
        #else
        UnconfiguredWeChatAuthService()
        #endif
    }
}

enum WeChatIntegration {
    /// Replace through an xcconfig value when the WeChat OpenSDK target is connected.
    static let appIDBuildSetting = "WECHAT_APP_ID"
    static let universalLinkBuildSetting = "WECHAT_UNIVERSAL_LINK"

    /// WeChat OpenSDK does not expose the user's complete friend list.
    /// The production app sends an invite card/link to WeChat, where the user
    /// chooses the recipient. The recipient joins via the Universal Link.
    static let friendListAccessIsSupported = false
}

enum ReminderSchedulingError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Notification permission was denied."
        }
    }
}

actor FortuneReminderService {
    static let shared = FortuneReminderService()

    private let identifier = "xingban.daily-fortune-reminder"

    func schedule(hour: Int, minute: Int, language: AppLanguage) async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        let isAuthorized: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        case .notDetermined:
            isAuthorized = try await center.requestAuthorization(options: [.alert, .sound])
        case .denied:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }

        guard isAuthorized else { throw ReminderSchedulingError.permissionDenied }

        let content = UNMutableNotificationContent()
        content.title = language.text("今天的星光到了", "오늘의 별빛이 도착했어요", "Today's starlight is here")
        content.body = language.text("推開魔法門，看看今天的運勢。", "마법의 문을 열고 오늘의 운세를 확인해 보세요.", "Open the magic gate and see what today holds.")
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: hour, minute: minute),
            repeats: true
        )
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        try await center.add(request)
    }

    func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
