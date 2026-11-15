import Foundation

// Mirrors the backend DTOs (backend/src/models.ts). Timestamps stay ISO strings like in the web app;
// formatting happens in L10n.

nonisolated struct User: Codable, Hashable, Sendable {
  let id: String
  let email: String
  let displayName: String
}

nonisolated struct AuthResponse: Codable, Sendable {
  let token: String
  let user: User
}

nonisolated struct Wishlist: Codable, Hashable, Identifiable, Sendable {
  let id: String
  var title: String
  var description: String?
  var eventDate: String?
  var shareToken: String
  var itemCount: Int?
  var createdAt: String
  var updatedAt: String
}

/// Someone else's list the user follows via its share link.
nonisolated struct FollowedWishlist: Codable, Hashable, Identifiable, Sendable {
  let id: String
  var title: String
  var description: String?
  var eventDate: String?
  var shareToken: String
  var itemCount: Int?
  var ownerName: String
  var followedAt: String
}

nonisolated struct Purchase: Codable, Hashable, Identifiable, Sendable {
  let id: String
  var quantity: Int
  var buyerName: String
  var createdAt: String
  var revertedAt: String?
  var revertedByName: String?
  var isMine: Bool

  /// Someone undid a purchase they didn't make themselves – worth a second look.
  var isSuspicious: Bool {
    guard let revertedByName else { return false }
    return revertedByName.lowercased() != buyerName.lowercased()
  }
}

/// A wish. Purchase fields are only present in the shared view and never for the list's owner.
nonisolated struct Item: Codable, Hashable, Identifiable, Sendable {
  let id: String
  var wishlistId: String
  var title: String
  var notes: String?
  /// What the owner entered; edit this.
  var imageUrl: String?
  /// Cached copy of imageUrl when available; render this.
  var displayImageUrl: String?
  var price: Double?
  var currency: String?
  var priority: Int
  var quantity: Int
  var links: [String]
  var createdAt: String
  var updatedAt: String
  var purchasedQuantity: Int?
  var purchases: [Purchase]?

  var remaining: Int { max(0, quantity - (purchasedQuantity ?? 0)) }
  var isFullyBought: Bool { (purchasedQuantity ?? 0) >= quantity }
}

nonisolated struct WishlistWithItems: Codable, Hashable, Sendable {
  let id: String
  var title: String
  var description: String?
  var eventDate: String?
  var shareToken: String
  var itemCount: Int?
  var createdAt: String
  var updatedAt: String
  /// How many people follow the list through its share link.
  var followerCount: Int?
  var items: [Item]
}

nonisolated struct Follower: Codable, Hashable, Identifiable, Sendable {
  let userId: String
  var displayName: String
  var followedAt: String
  var id: String { userId }
}

nonisolated struct SharedWishlist: Codable, Hashable, Sendable {
  struct Header: Codable, Hashable, Sendable {
    let id: String
    var title: String
    var description: String?
    var eventDate: String?
    var ownerName: String
  }

  var wishlist: Header
  var isOwner: Bool
  var isFollowing: Bool?
  var items: [Item]
}

nonisolated struct FollowState: Codable, Sendable {
  let isFollowing: Bool
}

nonisolated struct HealthResponse: Codable, Sendable {
  let ok: Bool
  let version: String?
}

nonisolated struct UploadResponse: Codable, Sendable {
  let url: String
}

// MARK: - Scraping

nonisolated enum ScrapeSource: String, Codable, Sendable {
  case structuredData = "structured-data"
  case productPage = "product-page"
  case previewTags = "preview-tags"
  case productMarkup = "product-markup"
  case pageTitle = "page-title"
  case page
  case linkAddress = "link-address"
  case pastedText = "pasted-text"
  case linkItself = "link-itself"

  /// Titles taken from the URL slug or the pasted text are only a best guess.
  var isGuess: Bool { self == .linkAddress || self == .pastedText }
}

nonisolated struct ScrapeMessage: Codable, Hashable, Sendable {
  let code: String
  var params: [String: JSONScalar]?
  /// English fallback for codes the app doesn't know yet.
  let message: String
}

nonisolated struct ScrapeResult: Codable, Hashable, Sendable {
  enum Status: String, Codable, Sendable { case ok, partial, failed }

  struct Sources: Codable, Hashable, Sendable {
    // Unknown future sources decode as nil instead of failing the whole result.
    var title: ScrapeSource?
    var image: ScrapeSource?
    var price: ScrapeSource?

    init(title: ScrapeSource? = nil, image: ScrapeSource? = nil, price: ScrapeSource? = nil) {
      self.title = title
      self.image = image
      self.price = price
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      title = try? container.decodeIfPresent(ScrapeSource.self, forKey: .title)
      image = try? container.decodeIfPresent(ScrapeSource.self, forKey: .image)
      price = try? container.decodeIfPresent(ScrapeSource.self, forKey: .price)
    }
  }

  let input: String
  var url: String?
  var finalUrl: String?
  var status: Status
  var title: String?
  var image: String?
  var price: Double?
  var currency: String?
  var siteName: String?
  var sources: Sources
  var messages: [ScrapeMessage]
}

// MARK: - Request bodies

/// The backend uses PATCH semantics on keys, so nil values must be sent as explicit `null`.
nonisolated struct WishlistInput: Encodable, Sendable {
  var title: String
  var description: String?
  var eventDate: String?

  enum CodingKeys: String, CodingKey { case title, description, eventDate }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(title, forKey: .title)
    try container.encode(description, forKey: .description)
    try container.encode(eventDate, forKey: .eventDate)
  }
}

nonisolated struct ItemInput: Encodable, Equatable, Sendable {
  var title: String
  var notes: String?
  var imageUrl: String?
  var price: Double?
  var currency: String?
  var priority: Int
  var quantity: Int
  var links: [String]

  enum CodingKeys: String, CodingKey { case title, notes, imageUrl, price, currency, priority, quantity, links }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(title, forKey: .title)
    try container.encode(notes, forKey: .notes)
    try container.encode(imageUrl, forKey: .imageUrl)
    try container.encode(price, forKey: .price)
    try container.encode(currency, forKey: .currency)
    try container.encode(priority, forKey: .priority)
    try container.encode(quantity, forKey: .quantity)
    try container.encode(links, forKey: .links)
  }
}

// MARK: - Helpers

/// String or number parameter from API error/scrape messages.
nonisolated enum JSONScalar: Codable, Hashable, Sendable, CustomStringConvertible {
  case string(String)
  case number(Double)

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let number = try? container.decode(Double.self) {
      self = .number(number)
    } else {
      self = .string(try container.decode(String.self))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    }
  }

  var description: String {
    switch self {
    case .string(let value): value
    case .number(let value):
      value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
  }
}
