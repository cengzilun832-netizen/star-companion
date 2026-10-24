import Combine
import Foundation
import StoreKit

enum MembershipNotice: Identifiable, Equatable {
    case pending
    case verificationFailed
    case restored(hasActiveSubscription: Bool)
    case failed(message: String)

    var id: String {
        switch self {
        case .pending: "pending"
        case .verificationFailed: "verification-failed"
        case .restored(let isActive): "restored-\(isActive)"
        case .failed(let message): "failed-\(message)"
        }
    }
}

enum AllLooksPurchaseNotice: Identifiable, Equatable {
    case pending
    case verificationFailed
    case purchased
    case restored(hasEntitlement: Bool)
    case failed(message: String)

    var id: String {
        switch self {
        case .pending: "all-looks-pending"
        case .verificationFailed: "all-looks-verification-failed"
        case .purchased: "all-looks-purchased"
        case .restored(let hasEntitlement): "all-looks-restored-\(hasEntitlement)"
        case .failed(let message): "all-looks-failed-\(message)"
        }
    }
}

@MainActor
final class MembershipStore: ObservableObject {
    static let monthlyProductID = configuredProductID(
        infoKey: "StarlightMonthlyProductID",
        suffix: ".starlight.monthly"
    )
    static let yearlyProductID = configuredProductID(
        infoKey: "StarlightYearlyProductID",
        suffix: ".starlight.yearly"
    )
    static let allStarLooksProductID = configuredProductID(
        infoKey: "AllStarLooksProductID",
        suffix: ".looks.all"
    )
    static let productIDs = [monthlyProductID, yearlyProductID]
    private static let allProductIDs = productIDs + [allStarLooksProductID]

    @Published private(set) var hasActiveSubscription = false
    @Published private(set) var hasAllLooksUnlocked = false
    @Published private(set) var hasCheckedEntitlements = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var allLooksProduct: Product?
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isRestoring = false
    @Published private(set) var isPurchasingAllLooks = false
    @Published private(set) var notice: MembershipNotice?
    @Published private(set) var allLooksNotice: AllLooksPurchaseNotice?
    @Published var lastErrorDescription: String?

    var monthlyProduct: Product? {
        products.first(where: { $0.id == Self.monthlyProductID })
    }

    var yearlyProduct: Product? {
        products.first(where: { $0.id == Self.yearlyProductID })
    }

    /// Calculated from the prices returned by the current App Store
    /// storefront. This avoids hard-coding a currency or claiming a discount
    /// that is not actually available in the user's region.
    var yearlySavingsPercentage: Int? {
        guard let monthlyProduct, let yearlyProduct else { return nil }
        let monthlyYear = NSDecimalNumber(decimal: monthlyProduct.price * 12).doubleValue
        let yearly = NSDecimalNumber(decimal: yearlyProduct.price).doubleValue
        guard monthlyYear > 0, yearly < monthlyYear else { return nil }
        return Int(((monthlyYear - yearly) / monthlyYear * 100).rounded())
    }

    private var updatesTask: Task<Void, Never>?
    private var hasPrepared = false

    private static func configuredProductID(infoKey: String, suffix: String) -> String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String {
            let value = configured.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, !value.contains("$(") {
                return value
            }
        }

        return (Bundle.main.bundleIdentifier ?? "com.example.StarCompanion") + suffix
    }

    init() {
        updatesTask = Task { [weak self] in
            await self?.listenForTransactionUpdates()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func prepare() async {
        guard !hasPrepared else { return }
        hasPrepared = true
        async let products: Void = loadProducts()
        async let entitlements: Void = refreshEntitlements()
        _ = await (products, entitlements)
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        lastErrorDescription = nil
        defer { isLoadingProducts = false }

        do {
            let loadedProducts = try await Product.products(for: Self.allProductIDs)
            products = loadedProducts
                .filter { Self.productIDs.contains($0.id) && $0.type == .autoRenewable }
                .sorted(by: { $0.price < $1.price })
            allLooksProduct = loadedProducts.first {
                $0.id == Self.allStarLooksProductID && $0.type == .nonConsumable
            }
        } catch {
            products = []
            allLooksProduct = nil
            lastErrorDescription = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var hasSubscriptionEntitlement = false
        var hasAllLooksEntitlement = false
        let now = Date()

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.allProductIDs.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded
            else { continue }

            if Self.productIDs.contains(transaction.productID) {
                guard transaction.productType == .autoRenewable,
                      transaction.expirationDate.map({ $0 > now }) == true
                else { continue }
                hasSubscriptionEntitlement = true
            } else if transaction.productID == Self.allStarLooksProductID {
                guard transaction.productType == .nonConsumable,
                      transaction.expirationDate == nil
                else { continue }
                hasAllLooksEntitlement = true
            }
        }

        hasActiveSubscription = hasSubscriptionEntitlement
        hasAllLooksUnlocked = hasAllLooksEntitlement
        hasCheckedEntitlements = true
    }

    func restorePurchases() async {
        guard !isRestoring else { return }
        isRestoring = true
        lastErrorDescription = nil
        notice = nil
        defer { isRestoring = false }

        do {
            try await StoreKit.AppStore.sync()
            await refreshEntitlements()
            notice = .restored(hasActiveSubscription: hasActiveSubscription)
        } catch {
            lastErrorDescription = error.localizedDescription
            notice = .failed(message: error.localizedDescription)
        }
    }

    /// Purchases the one-time, non-consumable entitlement that unlocks every
    /// star look. Passing a stable UUID lets App Store associate the purchase
    /// with the signed-in app account without exposing that account's ID.
    func purchaseAllLooks(appAccountToken: UUID? = nil) async {
        guard !isPurchasingAllLooks else { return }
        isPurchasingAllLooks = true
        allLooksNotice = nil
        defer { isPurchasingAllLooks = false }

        guard let allLooksProduct else {
            let message = String(
                localized: "The all-looks purchase is unavailable right now. Check your connection and try again."
            )
            allLooksNotice = .failed(message: message)
            return
        }

        do {
            let result: Product.PurchaseResult
            if let appAccountToken {
                result = try await allLooksProduct.purchase(options: [.appAccountToken(appAccountToken)])
            } else {
                result = try await allLooksProduct.purchase()
            }

            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification,
                      transaction.productID == Self.allStarLooksProductID,
                      transaction.productType == .nonConsumable,
                      transaction.revocationDate == nil,
                      transaction.expirationDate == nil
                else {
                    allLooksNotice = .verificationFailed
                    return
                }

                await transaction.finish()
                await refreshEntitlements()
                allLooksNotice = hasAllLooksUnlocked ? .purchased : .verificationFailed

            case .pending:
                allLooksNotice = .pending

            case .userCancelled:
                break

            @unknown default:
                allLooksNotice = .verificationFailed
            }
        } catch {
            allLooksNotice = .failed(message: error.localizedDescription)
        }
    }

    func restoreAllLooksPurchase() async {
        guard !isRestoring else { return }
        isRestoring = true
        allLooksNotice = nil
        defer { isRestoring = false }

        do {
            try await StoreKit.AppStore.sync()
            await refreshEntitlements()
            allLooksNotice = .restored(hasEntitlement: hasAllLooksUnlocked)
        } catch {
            allLooksNotice = .failed(message: error.localizedDescription)
        }
    }

    func purchaseFinished(_ result: Result<Product.PurchaseResult, any Error>) async {
        notice = nil
        lastErrorDescription = nil

        switch result {
        case .success(let purchaseResult):
            switch purchaseResult {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    guard Self.productIDs.contains(transaction.productID),
                          transaction.productType == .autoRenewable,
                          transaction.revocationDate == nil,
                          transaction.expirationDate.map({ $0 > Date() }) == true
                    else {
                        notice = .verificationFailed
                        return
                    }
                    await transaction.finish()
                    await refreshEntitlements()
                case .unverified:
                    notice = .verificationFailed
                }
            case .pending:
                notice = .pending
            case .userCancelled:
                break
            @unknown default:
                notice = .verificationFailed
            }
        case .failure(let error):
            lastErrorDescription = error.localizedDescription
            notice = .failed(message: error.localizedDescription)
        }
    }

    func dismissNotice() {
        notice = nil
    }

    func dismissAllLooksNotice() {
        allLooksNotice = nil
    }

    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            guard !Task.isCancelled else { return }

            if case .verified(let transaction) = result,
               Self.allProductIDs.contains(transaction.productID) {
                await transaction.finish()
            }
            await refreshEntitlements()
        }
    }
}
