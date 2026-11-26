import Foundation
import Testing

@testable import Wishlist

private func item(
  _ id: String, created: String, priority: Int = 3, price: Double? = nil, title: String? = nil, quantity: Int = 1,
  bought: Int? = nil
) -> Item {
  Item(
    id: id, wishlistId: "w", title: title ?? id, notes: nil, imageUrl: nil, displayImageUrl: nil, price: price,
    currency: "EUR", priority: priority, quantity: quantity, links: [], createdAt: created, updatedAt: created,
    purchasedQuantity: bought, purchases: nil)
}

@Suite struct ItemSortingTests {
  let items = [
    item("a", created: "2026-01-01T10:00:00.000Z", priority: 2, price: 30, title: "Zebra"),
    item("b", created: "2026-01-03T10:00:00.000Z", priority: 5, price: nil, title: "Äpfel"),
    item("c", created: "2026-01-02T10:00:00.000Z", priority: 5, price: 10, title: "Buch", quantity: 2, bought: 2),
  ]
  let locale = Locale(identifier: "de_DE")

  func ids(_ sort: ItemSort, boughtLast: Bool = false) -> [String] {
    ItemSorter.sorted(items, by: sort, locale: locale, boughtLast: boughtLast).map(\.id)
  }

  @Test func newestAndOldest() {
    #expect(ids(.newest) == ["b", "c", "a"])
    #expect(ids(.oldest) == ["a", "c", "b"])
  }

  @Test func priorityBreaksTiesByNewest() {
    #expect(ids(.priority) == ["b", "c", "a"])
  }

  @Test func itemsWithoutPriceAlwaysGoLast() {
    #expect(ids(.priceAsc) == ["c", "a", "b"])
    #expect(ids(.priceDesc) == ["a", "c", "b"])
  }

  @Test func titleUsesLocaleAwareComparison() {
    #expect(ids(.title) == ["b", "c", "a"])
  }

  @Test func boughtItemsSinkForGuests() {
    #expect(ids(.newest, boughtLast: true) == ["b", "a", "c"])
  }

  @Test func filters() {
    #expect(items.filter(ItemFilter.open.includes).map(\.id) == ["a", "b"])
    #expect(items.filter(ItemFilter.bought.includes).map(\.id) == ["c"])
  }
}

@Suite struct DeepLinkTests {
  let token = "AbC_123-xyzTOKEN456789"

  @Test func webLinks() {
    #expect(DeepLink.shareToken(from: URL(string: "https://wishlist.hein.cx/s/\(token)")!, scheme: "whateverwishlist") == token)
    #expect(DeepLink.shareToken(from: URL(string: "https://example.com/wishlists")!, scheme: "whateverwishlist") == nil)
  }

  @Test func customScheme() {
    #expect(DeepLink.shareToken(from: URL(string: "whateverwishlist://s/\(token)")!, scheme: "whateverwishlist") == token)
    #expect(DeepLink.shareToken(from: URL(string: "whateverwishlist:///s/\(token)")!, scheme: "whateverwishlist") == token)
  }

  @Test func destinations() {
    let scheme = "whateverwishlist"
    #expect(DeepLink.destination(from: URL(string: "https://wishlist.hein.cx/s/\(token)")!, scheme: scheme) == .wishlist(token: token))
    #expect(DeepLink.destination(from: URL(string: "https://wishlist.hein.cx/wishlists")!, scheme: scheme) == .overview)
    #expect(DeepLink.destination(from: URL(string: "https://wishlist.hein.cx/status")!, scheme: scheme) == .status)
    #expect(DeepLink.destination(from: URL(string: "whateverwishlist://status")!, scheme: scheme) == .status)
    #expect(DeepLink.destination(from: URL(string: "whateverwishlist://wishlists")!, scheme: scheme) == .overview)
    #expect(DeepLink.destination(from: URL(string: "https://wishlist.hein.cx/login")!, scheme: scheme) == nil)
    #expect(DeepLink.destination(from: URL(string: "mailto:someone@example.com")!, scheme: scheme) == nil)
  }

  @Test func pastedMessagesAndBareTokens() {
    let message = "My wishlist: Christmas https://wishlist.hein.cx/s/\(token) – see you!"
    #expect(DeepLink.shareToken(fromText: message, scheme: "whateverwishlist") == token)
    #expect(DeepLink.shareToken(fromText: "  \(token)\n", scheme: "whateverwishlist") == token)
    #expect(DeepLink.shareToken(fromText: "hello world", scheme: "whateverwishlist") == nil)
  }
}

@Suite struct L10nTests {
  func l10n(_ language: Language) -> L10n {
    L10n(language: language)
  }

  @Test func followsSystemLanguage() {
    #expect(L10n.detect(preferred: ["fr-FR", "de-AT", "en"]) == .de)
    #expect(L10n.detect(preferred: ["en-GB", "de-DE"]) == .en)
    #expect(L10n.detect(preferred: ["fr"]) == .en)
  }

  @Test func appIsLocalizedForBothLanguages() {
    #expect(Set(Bundle.main.localizations).isSuperset(of: ["de", "en"]))
  }

  @Test func everyKeyIsTranslatedInBothLanguages() {
    for key in TKey.allCases {
      #expect(Translations.en[key] != nil, "missing en \(key.rawValue)")
      #expect(Translations.de[key] != nil, "missing de \(key.rawValue)")
    }
  }

  @Test func interpolatesAndPluralizes() {
    let en = l10n(.en)
    #expect(en.t(.wishlistsGreeting, ["name": "Ada"]) == "Hi Ada!")
    #expect(en.t(.wishlistsWishCount, count: 1) == "1 wish")
    #expect(en.t(.wishlistsWishCount, count: 3) == "3 wishes")
    #expect(l10n(.de).t(.wishlistsWishCount, count: 0) == "0 Wünsche")
  }

  @Test func translatesApiErrors() {
    let de = l10n(.de)
    let error = APIError.server(status: 409, code: "NOT_ENOUGH_REMAINING", message: nil, params: ["remaining": .number(2)])
    #expect(de.errorMessage(error) == "Nur noch 2 offen.")
    #expect(de.errorMessage(APIError.offline) == "Der Server ist nicht erreichbar. Bist du online?")
    let unknown = APIError.server(status: 500, code: "SOMETHING_NEW", message: nil, params: [:])
    #expect(de.errorMessage(unknown) == de.t(.errorsUNKNOWN))
  }

  @Test func eventDatesAreCalendarDays() {
    let date = L10n.parseDate("2026-12-24")!
    #expect(Calendar.current.component(.day, from: date) == 24)
    #expect(L10n.dateOnlyString(date) == "2026-12-24")
    #expect(L10n.parseDate("2026-11-06T05:47:36.940Z") != nil)
    #expect(L10n.parseDate("2026-11-06T05:47:36Z") != nil)
  }
}

@Suite struct APIModelTests {
  @Test func decodesSharedWishlistWithPurchases() throws {
    let json = """
      {"wishlist":{"id":"w","title":"Xmas","description":null,"eventDate":"2026-12-24","ownerName":"Ada"},
       "isOwner":false,"isFollowing":true,
       "items":[{"id":"i","wishlistId":"w","title":"Book","notes":null,"imageUrl":"https://x.y/a.jpg",
         "displayImageUrl":"/_cache/0123456789abcdef","price":12.5,"currency":"EUR","priority":4,"quantity":2,
         "links":["https://x.y"],"createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z",
         "purchasedQuantity":1,"purchases":[{"id":"p","quantity":1,"buyerName":"Bob","createdAt":"2026-01-02T00:00:00.000Z",
         "revertedAt":"2026-01-03T00:00:00.000Z","revertedByName":"Eve","isMine":false}]}]}
      """
    let shared = try JSONDecoder().decode(SharedWishlist.self, from: Data(json.utf8))
    #expect(shared.items[0].remaining == 1)
    #expect(shared.items[0].purchases?[0].isSuspicious == true)
    let config = AppConfig(serverURL: URL(string: "https://wishlist.example.com")!)
    #expect(config.assetURL(shared.items[0].displayImageUrl)?.absoluteString == "https://wishlist.example.com/_cache/0123456789abcdef")
  }

  @Test func ownerViewHasNoPurchaseData() throws {
    let json = """
      {"wishlist":{"id":"w","title":"Xmas","ownerName":"Ada"},"isOwner":true,"isFollowing":false,
       "items":[{"id":"i","wishlistId":"w","title":"Book","priority":3,"quantity":1,"links":[],
         "createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z"}]}
      """
    let shared = try JSONDecoder().decode(SharedWishlist.self, from: Data(json.utf8))
    #expect(shared.items[0].purchases == nil)
    #expect(!shared.items[0].isFullyBought)
  }

  @Test func toleratesUnknownScrapeSources() throws {
    let json = """
      {"input":"x","url":null,"finalUrl":null,"status":"partial","title":"T","image":null,"price":null,
       "currency":null,"siteName":null,"sources":{"title":"something-new"},
       "messages":[{"code":"HTTP_ERROR","params":{"status":403},"message":"x"}]}
      """
    let result = try JSONDecoder().decode(ScrapeResult.self, from: Data(json.utf8))
    #expect(result.sources.title == nil)
    #expect(result.messages[0].params?["status"]?.description == "403")
  }

  @Test func itemInputSendsExplicitNulls() throws {
    let input = ItemInput(
      title: "T", notes: nil, imageUrl: nil, price: nil, currency: nil, priority: 3, quantity: 1, links: [])
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as! [String: Any]
    #expect(object["notes"] is NSNull)
    #expect(object["price"] is NSNull)
    #expect(object.keys.count == 8)
  }

  @Test func serverOriginIsNormalized() {
    #expect(AppConfig.origin("https://wishlist.hein.cx/ ")?.absoluteString == "https://wishlist.hein.cx")
    #expect(AppConfig.origin("ftp://example.com") == nil)
    let config = AppConfig(serverURL: URL(string: "https://a.example")!, webURL: URL(string: "https://b.example")!)
    #expect(config.apiURL.absoluteString == "https://a.example/api")
    #expect(config.shareURL(token: "abc").absoluteString == "https://b.example/s/abc")
    #expect(config.assetURL("/uploads/x.jpg")?.absoluteString == "https://a.example/uploads/x.jpg")
    #expect(config.assetURL("javascript:alert(1)") == nil)
  }
}

@Suite struct InputParsingTests {
  @Test func prices() {
    let de = Locale(identifier: "de_DE")
    #expect(PriceParser.parse("12,99", locale: de) == 12.99)
    #expect(PriceParser.parse("12.99 €", locale: de) == 12.99)
    #expect(PriceParser.parse("1.234,56", locale: de) == 1234.56)
    #expect(PriceParser.parse("1,234.56", locale: de) == 1234.56)
    #expect(PriceParser.parse("", locale: de) == nil)
    #expect(PriceParser.parse("abc", locale: de) == nil)
  }

  @Test func detectsUploadableImages() {
    #expect(ImagePreparer.detect(Data([0xFF, 0xD8, 0xFF, 0xE0]))?.ext == "jpg")
    #expect(ImagePreparer.detect(Data("GIF89a......".utf8))?.ext == "gif")
    #expect(ImagePreparer.detect(Data("RIFF\0\0\0\0WEBP".utf8))?.ext == "webp")
    #expect(ImagePreparer.detect(Data("....ftypheic".utf8)) == nil)
  }
}
