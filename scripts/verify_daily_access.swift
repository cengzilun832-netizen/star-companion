import Foundation

@main
struct VerifyDailyAccess {
    static func main() {
        let today = "2026-08-30"
        let yesterday = "2026-08-29"

        precondition(DailyAccessPolicy.canUse(isMember: false, lastUsedStamp: nil, todayStamp: today))
        precondition(DailyAccessPolicy.canUse(isMember: false, lastUsedStamp: yesterday, todayStamp: today))
        precondition(!DailyAccessPolicy.canUse(isMember: false, lastUsedStamp: today, todayStamp: today))
        precondition(DailyAccessPolicy.canUse(isMember: true, lastUsedStamp: today, todayStamp: today))
        precondition(!DailyAccessPolicy.canUse(isMember: false, lastUsedStamp: "2026-09-01", todayStamp: today))

        precondition(DailyAccessPolicy.canReserve(
            isMember: false,
            lastUsedStamp: yesterday,
            todayStamp: today,
            hasMatchingReservation: false
        ))
        precondition(!DailyAccessPolicy.canReserve(
            isMember: false,
            lastUsedStamp: yesterday,
            todayStamp: today,
            hasMatchingReservation: true
        ))
        precondition(DailyAccessPolicy.canReserve(
            isMember: true,
            lastUsedStamp: today,
            todayStamp: today,
            hasMatchingReservation: true
        ))

        precondition(
            DailyAccessPolicy.stampAfterRecording(
                isMember: false,
                lastUsedStamp: yesterday,
                todayStamp: today
            ) == today
        )
        precondition(
            DailyAccessPolicy.stampAfterRecording(
                isMember: true,
                lastUsedStamp: yesterday,
                todayStamp: today
            ) == yesterday
        )

        let reservation = DailyAccessReservation(
            id: UUID(),
            kind: .tarot,
            accountID: "account-a",
            originatingDayStamp: yesterday,
            wasMemberWhenReserved: false
        )
        precondition(reservation.originatingDayStamp == yesterday)
        precondition(reservation.accountID != "account-b")

        print("Daily access policy and reservation identity verified")
    }
}
