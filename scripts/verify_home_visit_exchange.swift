import Foundation

@main
enum VerifyHomeVisitExchange {
    static func main() throws {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_788_134_400)
        let hostID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let card = HomeVisitCard(
            version: 1,
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            hostShareID: hostID,
            createdAt: now,
            expiresAt: now.addingTimeInterval(7 * 86_400),
            hostAlias: "Moon Friend",
            appearance: StarAppearanceSnapshot(
                personaID: StarPersona.moonveil.rawValue,
                auraID: StarAura.moonlit.rawValue,
                accessoryID: StarAccessory.none.rawValue,
                roomThemeID: StarRoomTheme.observatoryGarden.rawValue,
                moodID: "happy"
            ),
            furnitureIDs: [StarFurniture.telescope.rawValue]
        )

        let cardURL = try require(HomeVisitLinkCodec.url(for: card))
        guard case let .card(decodedCard) = try require(HomeVisitLinkCodec.decode(cardURL)) else {
            preconditionFailure("Visit URL did not decode as a card")
        }
        precondition(decodedCard == card)
        precondition(cardURL.absoluteString.count < 4_096)

        let secret = Data(repeating: 7, count: 32)
        let visitorKey = HomeVisitLinkCodec.visitorKey(secret: secret, hostShareID: hostID)
        precondition(visitorKey == HomeVisitLinkCodec.visitorKey(secret: secret, hostShareID: hostID))
        precondition(visitorKey != HomeVisitLinkCodec.visitorKey(secret: secret, hostShareID: UUID()))
        precondition(HomeVisitLinkCodec.sanitizedAlias("  Moon\nFriend  ") == "Moon Friend")

        let digest = try require(HomeVisitLinkCodec.digest(for: card))
        let receipt = HomeVisitReceipt(
            version: 1,
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
            cardID: card.id,
            hostShareID: hostID,
            cardDigest: digest,
            visitorKey: visitorKey,
            visitorAlias: nil,
            reaction: .moonHug,
            createdAt: now.addingTimeInterval(60)
        )
        let receiptURL = try require(HomeVisitLinkCodec.url(for: receipt))
        guard case let .receipt(decodedReceipt) = try require(HomeVisitLinkCodec.decode(receiptURL)) else {
            preconditionFailure("Receipt URL did not decode as a receipt")
        }
        precondition(decodedReceipt == receipt)

        precondition(HomeVisitRewardPolicy.decision(for: receipt, redemptions: [], now: now, calendar: calendar) == .accepted(reward: 8))
        let accepted = HomeVisitRedemption(id: receipt.id, cardID: card.id, visitorKey: visitorKey, acceptedAt: now, reward: 8)
        precondition(HomeVisitRewardPolicy.decision(for: receipt, redemptions: [accepted], now: now, calendar: calendar) == .alreadyAccepted)

        let anotherReceipt = HomeVisitReceipt(
            version: 1,
            id: UUID(),
            cardID: card.id,
            hostShareID: hostID,
            cardDigest: digest,
            visitorKey: visitorKey,
            visitorAlias: nil,
            reaction: .tinyCheer,
            createdAt: now
        )
        precondition(HomeVisitRewardPolicy.decision(for: anotherReceipt, redemptions: [accepted], now: now, calendar: calendar) == .alreadyVisitedToday)

        let threeVisitors = (0..<3).map { index in
            HomeVisitRedemption(
                id: UUID(),
                cardID: card.id,
                visitorKey: "visitor-\(index)",
                acceptedAt: now,
                reward: 8
            )
        }
        precondition(HomeVisitRewardPolicy.decision(for: anotherReceipt, redemptions: threeVisitors, now: now, calendar: calendar) == .acceptedWithoutReward)

        let dailyLimitLedger = (0..<HomeVisitRewardPolicy.maximumAcceptedVisitsPerDay).map { index in
            HomeVisitRedemption(
                id: UUID(),
                cardID: card.id,
                visitorKey: "daily-visitor-\(index)",
                acceptedAt: now,
                reward: 0
            )
        }
        let overDailyLimitReceipt = HomeVisitReceipt(
            version: 1,
            id: UUID(),
            cardID: card.id,
            hostShareID: hostID,
            cardDigest: digest,
            visitorKey: "daily-limit-new-visitor",
            visitorAlias: nil,
            reaction: .warmWave,
            createdAt: now
        )
        precondition(
            HomeVisitRewardPolicy.decision(
                for: overDailyLimitReceipt,
                redemptions: dailyLimitLedger,
                now: now,
                calendar: calendar
            ) == .dailyLimitReached
        )

        let replayProtectedID = UUID()
        let overflowLedger = (0..<513).map { index in
            HomeVisitRedemption(
                id: index == 512 ? replayProtectedID : UUID(),
                cardID: card.id,
                visitorKey: "overflow-visitor-\(index)",
                acceptedAt: now.addingTimeInterval(TimeInterval(-index)),
                reward: 0
            )
        }
        let retainedOverflow = HomeVisitRewardPolicy.retainedRedemptions(
            to: overflowLedger,
            issuedCards: [IssuedHomeVisitCard(id: card.id, digest: digest, expiresAt: card.expiresAt)],
            now: now,
            calendar: calendar
        )
        precondition(retainedOverflow.count == 513)
        let replayReceipt = HomeVisitReceipt(
            version: 1,
            id: replayProtectedID,
            cardID: card.id,
            hostShareID: hostID,
            cardDigest: digest,
            visitorKey: "overflow-visitor-512",
            visitorAlias: nil,
            reaction: .warmWave,
            createdAt: now
        )
        precondition(
            HomeVisitRewardPolicy.decision(
                for: replayReceipt,
                redemptions: retainedOverflow,
                now: now,
                calendar: calendar
            ) == .alreadyAccepted
        )

        // Calendar-day grace must survive the 25-hour day when daylight
        // saving time ends. A fixed 24-hour duration would evict this replay
        // ID half an hour before the app still accepts the receipt.
        var dstCalendar = Calendar(identifier: .gregorian)
        dstCalendar.timeZone = try require(TimeZone(identifier: "America/New_York"))
        let dstExpiry = try require(dstCalendar.date(from: DateComponents(
            year: 2026,
            month: 10,
            day: 31,
            hour: 12
        )))
        let dstCard = IssuedHomeVisitCard(id: UUID(), digest: "dst", expiresAt: dstExpiry)
        let dstReplayID = UUID()
        let dstOverflowLedger = (0..<513).map { index in
            HomeVisitRedemption(
                id: index == 512 ? dstReplayID : UUID(),
                cardID: dstCard.id,
                visitorKey: "dst-overflow-\(index)",
                acceptedAt: dstExpiry.addingTimeInterval(TimeInterval(-index)),
                reward: 0
            )
        }
        let dstNow = dstExpiry.addingTimeInterval(24.5 * 60 * 60)
        precondition(
            HomeVisitRewardPolicy.redemptionGraceEnd(for: dstCard, calendar: dstCalendar) > dstNow
        )
        let dstRetained = HomeVisitRewardPolicy.retainedRedemptions(
            to: dstOverflowLedger,
            issuedCards: [dstCard],
            now: dstNow,
            calendar: dstCalendar
        )
        precondition(dstRetained.count == 513)
        let dstReplayReceipt = HomeVisitReceipt(
            version: 1,
            id: dstReplayID,
            cardID: dstCard.id,
            hostShareID: hostID,
            cardDigest: dstCard.digest,
            visitorKey: "dst-overflow-512",
            visitorAlias: nil,
            reaction: .tinyCheer,
            createdAt: dstExpiry
        )
        precondition(
            HomeVisitRewardPolicy.decision(
                for: dstReplayReceipt,
                redemptions: dstRetained,
                now: dstNow,
                calendar: dstCalendar
            ) == .alreadyAccepted
        )

        let legacyVisit = #"{"id":"40000000-0000-0000-0000-000000000004","visitorAlias":"Xiaoyu","visitedAt":0,"stardustAmount":8}"#.data(using: .utf8)!
        let decodedLegacyVisit = try JSONDecoder().decode(HomeVisitRecord.self, from: legacyVisit)
        precondition(decodedLegacyVisit.receiptID == nil && decodedLegacyVisit.reactionID == nil)

        let migrated = StarLifeState(
            schemaVersion: 1,
            wishes: [],
            weeklyStory: .current(for: now, calendar: calendar),
            home: .starter,
            gentleDay: GentleDayState()
        ).migrated(now: now, calendar: calendar)
        precondition(migrated.schemaVersion == 2)
        precondition(migrated.visitExchange?.visitorSecret?.count == 32)

        if CommandLine.arguments.contains("--emit-card-url") {
            let previewNow = Date()
            let previewCard = HomeVisitCard(
                version: card.version,
                id: card.id,
                hostShareID: card.hostShareID,
                createdAt: previewNow,
                expiresAt: previewNow.addingTimeInterval(7 * 86_400),
                hostAlias: card.hostAlias,
                appearance: card.appearance,
                furnitureIDs: card.furnitureIDs
            )
            print(try require(HomeVisitLinkCodec.url(for: previewCard)).absoluteString)
            return
        }
        print("Home visit card round-trip, privacy IDs, 513-entry and DST replay protection, total daily caps, and v1 migration verified")
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw VerificationError.missingValue }
        return value
    }

    private enum VerificationError: Error { case missingValue }
}
