import SwiftUI
import UIKit

@main
struct StarCompanionApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var membershipStore = MembershipStore()
    @State private var handledPreviewURL = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(membershipStore)
                .onOpenURL(perform: store.handleIncomingURL)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { store.handleIncomingURL(url) }
                }
                .task {
                    StarPetWatchSyncController.shared.connect(to: store)
                    store.startAccountCloudSync()
                    await membershipStore.prepare()
                    store.updateMembership(membershipStore.hasActiveSubscription)
                    store.updateAllLooksEntitlement(membershipStore.hasAllLooksUnlocked)
                    store.refreshDailyContext()
                    handlePreviewURLIfNeeded()
                }
                .task {
                    for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                        store.refreshDailyContext()
                    }
                }
                .task {
                    for await _ in NotificationCenter.default.notifications(named: .NSSystemTimeZoneDidChange) {
                        store.refreshDailyContext()
                    }
                }
                .task {
                    for await _ in NotificationCenter.default.notifications(
                        named: UIApplication.significantTimeChangeNotification
                    ) {
                        store.refreshDailyContext()
                    }
                }
                .onChange(of: membershipStore.hasActiveSubscription) { _, isActive in
                    store.updateMembership(isActive)
                }
                .onChange(of: membershipStore.hasAllLooksUnlocked) { _, isUnlocked in
                    store.updateAllLooksEntitlement(isUnlocked)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.refreshDailyContext()
                        store.startAccountCloudSync()
                        Task {
                            await membershipStore.refreshEntitlements()
                        }
                    }
                }
        }
    }

    private func handlePreviewURLIfNeeded() {
        #if DEBUG
        guard !handledPreviewURL else { return }
        handledPreviewURL = true

        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--preview-incoming-url"),
              arguments.indices.contains(flagIndex + 1),
              let url = URL(string: arguments[flagIndex + 1])
        else { return }

        store.handleIncomingURL(url)
        #endif
    }
}
