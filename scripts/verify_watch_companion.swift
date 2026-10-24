import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Watch companion verification failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
private struct WatchCompanionVerifier {
    static func main() {
        let snapshot = WatchPetSnapshot(
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            dayStamp: "2026-09-01",
            accountScopeID: "anonymous-scope",
            mood: .glowing,
            food: 108,
            feedCount: 7,
            feedLimit: 4,
            canFeed: true,
            canInteract: true,
            gentleMode: false,
            language: .korean
        )
        expect(snapshot.food == 100, "food must be clamped")
        expect(snapshot.feedCount == 4, "feed count must not exceed its limit")
        expect(!snapshot.canFeed, "a full star cannot be fed")

        let snapshotMessage = WatchPetMessageCodec.message(for: snapshot)
        expect(WatchPetMessageCodec.snapshot(from: snapshotMessage) == snapshot, "snapshot round-trip")

        let action = WatchPetAction(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            kind: .gentleInteraction,
            requestedAt: Date(timeIntervalSince1970: 1_800_000_100),
            dayStamp: "2026-09-01",
            accountScopeID: "anonymous-scope"
        )
        expect(WatchPetMessageCodec.action(from: WatchPetMessageCodec.message(for: action)) == action, "action round-trip")
        expect(WatchPetLanguage.traditionalChinese.text("今日", "오늘", "Today") == "今日", "Traditional Chinese copy")
        expect(WatchPetLanguage.korean.text("今日", "오늘", "Today") == "오늘", "Korean copy")
        expect(WatchPetLanguage.english.text("今日", "오늘", "Today") == "Today", "English copy")

        let quiet = WatchPetSnapshot(
            dayStamp: "2026-09-01",
            accountScopeID: "anonymous-scope",
            mood: .low,
            food: 40,
            feedCount: 0,
            feedLimit: 3,
            canFeed: true,
            canInteract: true,
            gentleMode: true,
            language: .english
        )
        expect(!quiet.canFeed, "gentle mode must suppress watch feeding")

        print("Watch snapshot codec, account scope, limits, and three languages verified")
    }
}
