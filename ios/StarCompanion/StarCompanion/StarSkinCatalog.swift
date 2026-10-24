import Foundation

/// Rarity is intentionally part of the generated catalog instead of being
/// inferred from array position. Reordering or adding artwork therefore never
/// changes the price of a look that somebody has already seen.
enum StarSkinRarity: String, CaseIterable, Identifiable, Codable, Hashable {
    case common
    case rare
    case epic
    case legendary

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .common: language.text("星光", "별빛", "Starlight")
        case .rare: language.text("稀有", "희귀", "Rare")
        case .epic: language.text("奇幻", "환상", "Epic")
        case .legendary: language.text("傳說", "전설", "Legendary")
        }
    }
}

/// One entry generated from `assets/pet/skins/collection`.
///
/// IDs are stable and namespaced (`collection.<source-slug>`), so the wardrobe
/// can safely persist ownership even when the catalog is sorted differently in
/// a future release.
struct StarSkinCatalogItem: Identifiable, Hashable {
    let id: String
    let sourceSlug: String
    let assetName: String
    let traditionalChineseName: String?
    let koreanName: String?
    let englishName: String
    let rarity: StarSkinRarity
    let price: Int

    func title(in language: AppLanguage) -> String {
        switch language {
        case .traditionalChinese:
            traditionalChineseName?.nilIfBlank ?? englishName
        case .korean:
            koreanName?.nilIfBlank ?? englishName
        case .english:
            englishName
        }
    }
}

enum StarSkinCatalog {
    static let all: [StarSkinCatalogItem] = generatedItems

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func item(id: String?) -> StarSkinCatalogItem? {
        guard let id else { return nil }
        return byID[id]
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
