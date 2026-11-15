#if DEBUG
import Foundation
import UIKit

/// Set up when the app is launched by the UI tests (`-ui-testing`): an in-memory backend, a throwaway
/// session and settings, so tests are deterministic and need no server – locally and on Xcode Cloud.
///
/// Launch environment:
/// - `UITEST_SCENARIO`: `standard` (default), `empty` or `many` (a list with 20 pictures).
/// - `UITEST_LOGIN`: `ada` or `bob` to start signed in.
struct UITestEnvironment {
  static let current: UITestEnvironment? =
    ProcessInfo.processInfo.arguments.contains("-ui-testing") ? UITestEnvironment() : nil

  let config = AppConfig(serverURL: URL(string: "https://wishlist.test")!, urlScheme: "whateverwishlist")
  let session: URLSession
  let defaults: UserDefaults
  let login: AuthResponse?

  private init() {
    let environment = ProcessInfo.processInfo.environment
    MockBackend.shared.reset(scenario: environment["UITEST_SCENARIO"] ?? "standard")

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    session = URLSession(configuration: configuration)

    defaults = UserDefaults(suiteName: "ui-testing")!
    defaults.removePersistentDomain(forName: "ui-testing")

    login = environment["UITEST_LOGIN"].flatMap { MockBackend.shared.session(for: $0) }
    UIView.setAnimationsEnabled(environment["UITEST_ANIMATIONS"] == "1")
  }
}

nonisolated final class MockURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  /// `UITEST_LATENCY_MS` delays every answer like a real network, so data arrives during transitions.
  private static let latency = Double(ProcessInfo.processInfo.environment["UITEST_LATENCY_MS"] ?? "") ?? 0

  override func startLoading() {
    guard Self.latency > 0 else { return respond() }
    DispatchQueue.global().asyncAfter(deadline: .now() + Self.latency / 1000) { [self] in respond() }
  }

  private func respond() {
    let response = MockBackend.shared.handle(request, body: Self.body(of: request))
    let http = HTTPURLResponse(
      url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": response.contentType])!
    client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: response.body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private static func body(of request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 16_384)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count <= 0 { break }
      data.append(buffer, count: count)
    }
    return data
  }
}

/// In-memory version of the backend API (backend/src/routes) with the same rules and error codes.
nonisolated final class MockBackend: @unchecked Sendable {
  static let shared = MockBackend()

  struct Response {
    var status = 200
    var contentType = "application/json"
    var body = Data()
  }

  private struct Account {
    let user: User
    let password: String
  }

  private struct Record {
    var wishlist: Wishlist
    let ownerID: String
    var items: [Item]
    var followers: [Follower]
  }

  private struct StoredPurchase {
    var purchase: Purchase
    let buyerID: String?
  }

  private let lock = NSLock()
  private var accounts: [Account] = []
  private var records: [Record] = []
  private var storedPurchases: [String: [StoredPurchase]] = [:]
  private var counter = 0
  private var images: [String: Data] = [:]

  // MARK: Scenarios

  func reset(scenario: String) {
    lock.withLock {
      counter = 0
      storedPurchases = [:]
      let ada = User(id: "user-ada", email: "ada@example.com", displayName: "Ada")
      let bob = User(id: "user-bob", email: "bob@example.com", displayName: "Bob")
      accounts = [Account(user: ada, password: "password123"), Account(user: bob, password: "password123")]
      records = []
      guard scenario != "empty" else { return }

      var christmas = Record(
        wishlist: Wishlist(
          id: "list-christmas", title: "Christmas 2026", description: "Thank you for thinking of me!",
          eventDate: "2026-12-24", shareToken: "christmasToken2026", itemCount: nil,
          createdAt: "2026-10-01T10:00:00.000Z", updatedAt: "2026-10-01T10:00:00.000Z"),
        ownerID: ada.id, items: [],
        followers: [Follower(userId: bob.id, displayName: "Bob", followedAt: "2026-10-02T10:00:00.000Z")])
      christmas.items = [
        item(
          "item-book", "list-christmas", "Cookbook", price: 34.99, priority: 5, quantity: 1,
          links: ["https://shop.example/cookbook"], image: "https://images.test/cookbook.png",
          created: "2026-10-01T10:01:00.000Z", notes: "The English edition, please"),
        item(
          "item-cups", "list-christmas", "Espresso cups", price: 24.5, priority: 3, quantity: 4,
          links: ["https://shop.example/cups"], image: "https://images.test/cups.png",
          created: "2026-10-01T10:02:00.000Z",
          purchases: [purchase("p-cups", 2, "Bob", by: bob.id, at: "2026-10-03T09:00:00.000Z")]),
        item(
          "item-socks", "list-christmas", "Wool socks", price: nil, priority: 2, quantity: 1, links: [],
          image: nil, created: "2026-10-01T10:03:00.000Z",
          purchases: [purchase("p-socks", 1, "Grandma", by: nil, at: "2026-10-04T09:00:00.000Z")]),
      ]
      records.append(christmas)

      if scenario == "many" {
        var big = Record(
          wishlist: Wishlist(
            id: "list-big", title: "Big list", description: nil, eventDate: nil, shareToken: "bigListToken2026",
            itemCount: nil, createdAt: "2026-10-01T09:00:00.000Z", updatedAt: "2026-10-01T09:00:00.000Z"),
          ownerID: ada.id, items: [],
          followers: [Follower(userId: bob.id, displayName: "Bob", followedAt: "2026-10-02T10:00:00.000Z")])
        big.items = (1...20).map { index in
          item(
            "item-big-\(index)", "list-big", "Wish \(index)", price: Double(index) * 9.99,
            priority: index % 5 + 1, quantity: 1, links: ["https://shop.example/\(index)"],
            image: "https://images.test/big-\(index).png",
            created: String(format: "2026-10-01T11:%02d:00.000Z", index))
        }
        records.append(big)
      }
    }
  }

  func session(for name: String) -> AuthResponse? {
    lock.withLock {
      accounts.first { $0.user.displayName.lowercased() == name.lowercased() }
        .map { AuthResponse(token: "token-\($0.user.id)", user: $0.user) }
    }
  }

  private func item(
    _ id: String, _ list: String, _ title: String, price: Double?, priority: Int, quantity: Int, links: [String],
    image: String?, created: String, notes: String? = nil, purchases: [StoredPurchase] = []
  ) -> Item {
    storedPurchases[id] = purchases
    return Item(
      id: id, wishlistId: list, title: title, notes: notes, imageUrl: image, displayImageUrl: image, price: price,
      currency: price == nil ? nil : "EUR", priority: priority, quantity: quantity, links: links, createdAt: created,
      updatedAt: created, purchasedQuantity: nil, purchases: nil)
  }

  private func purchase(_ id: String, _ quantity: Int, _ name: String, by buyer: String?, at date: String)
    -> StoredPurchase
  {
    StoredPurchase(
      purchase: Purchase(
        id: id, quantity: quantity, buyerName: name, createdAt: date, revertedAt: nil, revertedByName: nil,
        isMine: false),
      buyerID: buyer)
  }

  // MARK: Routing

  func handle(_ request: URLRequest, body: Data) -> Response {
    lock.withLock {
      guard let url = request.url else { return error(400, "BAD_REQUEST") }
      if url.host() == "images.test" || url.path().hasPrefix("/uploads/") || url.path().hasPrefix("/_cache/") {
        return Response(contentType: "image/png", body: image(for: url.lastPathComponent))
      }
      let parts = url.pathComponents.filter { $0 != "/" }
      guard parts.first == "api" else { return error(404, "NOT_FOUND") }
      let route = Array(parts.dropFirst())
      let method = request.httpMethod ?? "GET"
      let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
      let header = request.value(forHTTPHeaderField: "Authorization")
      let viewer = header.flatMap { header in accounts.first { "Bearer token-\($0.user.id)" == header }?.user }
      if header != nil, viewer == nil { return error(401, "AUTH_REQUIRED") }

      switch (method, route.first) {
      case ("GET", "health"): return ok(["ok": true, "version": "mock"])
      case (_, "auth"): return auth(method, Array(route.dropFirst()), json, viewer)
      case (_, "wishlists"):
        guard let viewer else { return error(401, "AUTH_REQUIRED") }
        return wishlists(method, Array(route.dropFirst()), json, viewer)
      case (_, "shared"): return shared(method, Array(route.dropFirst()), json, viewer)
      case ("POST", "scrape"):
        guard viewer != nil else { return error(401, "AUTH_REQUIRED") }
        return scrape(json["input"] as? String ?? "")
      case ("POST", "uploads"):
        guard viewer != nil else { return error(401, "AUTH_REQUIRED") }
        return ok(["url": "/uploads/\(UUID().uuidString.lowercased()).png"], status: 201)
      default: return error(404, "NOT_FOUND")
      }
    }
  }

  private func auth(_ method: String, _ route: [String], _ json: [String: Any], _ viewer: User?) -> Response {
    let email = (json["email"] as? String ?? "").trimmed.lowercased()
    let password = json["password"] as? String ?? ""
    switch (method, route.first) {
    case ("POST", "login"):
      guard let account = accounts.first(where: { $0.user.email == email && $0.password == password }) else {
        return error(401, "INVALID_CREDENTIALS")
      }
      return encode(AuthResponse(token: "token-\(account.user.id)", user: account.user))
    case ("POST", "register"):
      let name = (json["displayName"] as? String ?? "").trimmed
      guard email.contains("@"), password.count >= 8, !name.isEmpty else { return error(400, "VALIDATION_FAILED") }
      guard !accounts.contains(where: { $0.user.email == email }) else { return error(409, "EMAIL_TAKEN") }
      let user = User(id: "user-\(nextID())", email: email, displayName: name)
      accounts.append(Account(user: user, password: password))
      return encode(AuthResponse(token: "token-\(user.id)", user: user), status: 201)
    case ("GET", "me"):
      guard let viewer else { return error(401, "AUTH_REQUIRED") }
      return encode(viewer)
    default:
      return error(404, "NOT_FOUND")
    }
  }

  private func wishlists(_ method: String, _ route: [String], _ json: [String: Any], _ viewer: User) -> Response {
    switch (method, route.count) {
    case ("GET", 0):
      let own = records.filter { $0.ownerID == viewer.id }.map(summary)
      return encode(own.sorted { $0.updatedAt > $1.updatedAt })
    case ("GET", 1) where route[0] == "followed":
      let followed = records.filter { record in record.followers.contains { $0.userId == viewer.id } }.map { record in
        let owner = accounts.first { $0.user.id == record.ownerID }!.user
        let summary = summary(record)
        return FollowedWishlist(
          id: summary.id, title: summary.title, description: summary.description, eventDate: summary.eventDate,
          shareToken: summary.shareToken, itemCount: summary.itemCount, ownerName: owner.displayName,
          followedAt: record.followers.first { $0.userId == viewer.id }!.followedAt)
      }
      return encode(followed)
    case ("POST", 0):
      guard let title = (json["title"] as? String)?.trimmed, !title.isEmpty else {
        return error(400, "VALIDATION_FAILED")
      }
      let id = "list-\(nextID())"
      let wishlist = Wishlist(
        id: id, title: title, description: json["description"] as? String, eventDate: json["eventDate"] as? String,
        shareToken: "token\(id.replacingOccurrences(of: "-", with: ""))share", itemCount: 0, createdAt: now(),
        updatedAt: now())
      records.append(Record(wishlist: wishlist, ownerID: viewer.id, items: [], followers: []))
      return encode(wishlist, status: 201)
    default:
      break
    }

    guard let index = records.firstIndex(where: { $0.wishlist.id == route.first && $0.ownerID == viewer.id }) else {
      return error(404, "WISHLIST_NOT_FOUND")
    }
    switch (method, Array(route.dropFirst())) {
    case ("GET", []):
      let record = records[index]
      let full = WishlistWithItems(
        id: record.wishlist.id, title: record.wishlist.title, description: record.wishlist.description,
        eventDate: record.wishlist.eventDate, shareToken: record.wishlist.shareToken, itemCount: record.items.count,
        createdAt: record.wishlist.createdAt, updatedAt: record.wishlist.updatedAt,
        followerCount: record.followers.count, items: record.items)
      return encode(full)
    case ("PATCH", []):
      if let title = json["title"] as? String { records[index].wishlist.title = title }
      if json.keys.contains("description") { records[index].wishlist.description = json["description"] as? String }
      if json.keys.contains("eventDate") { records[index].wishlist.eventDate = json["eventDate"] as? String }
      records[index].wishlist.updatedAt = now()
      return encode(summary(records[index]))
    case ("DELETE", []):
      records.remove(at: index)
      return Response(status: 204)
    case ("POST", ["share-token"]):
      records[index].wishlist.shareToken = "newToken\(nextID())share"
      if json["keepFollowers"] as? Bool != true { records[index].followers = [] }
      return encode(summary(records[index]))
    case ("GET", ["followers"]):
      return encode(records[index].followers)
    case ("DELETE", let path) where path.count == 2 && path[0] == "followers":
      guard records[index].followers.contains(where: { $0.userId == path[1] }) else {
        return error(404, "FOLLOWER_NOT_FOUND")
      }
      records[index].followers.removeAll { $0.userId == path[1] }
      return Response(status: 204)
    case ("POST", ["items"]):
      guard let title = (json["title"] as? String)?.trimmed, !title.isEmpty else {
        return error(400, "VALIDATION_FAILED")
      }
      var item = Item(
        id: "item-\(nextID())", wishlistId: records[index].wishlist.id, title: title, notes: nil, imageUrl: nil,
        displayImageUrl: nil, price: nil, currency: nil, priority: 3, quantity: 1, links: [], createdAt: now(),
        updatedAt: now(), purchasedQuantity: nil, purchases: nil)
      apply(json, to: &item)
      records[index].items.append(item)
      return encode(item, status: 201)
    case ("PATCH", let path) where path.count == 2 && path[0] == "items":
      guard let itemIndex = records[index].items.firstIndex(where: { $0.id == path[1] }) else {
        return error(404, "ITEM_NOT_FOUND")
      }
      apply(json, to: &records[index].items[itemIndex])
      return encode(records[index].items[itemIndex])
    case ("DELETE", let path) where path.count == 2 && path[0] == "items":
      guard records[index].items.contains(where: { $0.id == path[1] }) else { return error(404, "ITEM_NOT_FOUND") }
      records[index].items.removeAll { $0.id == path[1] }
      return Response(status: 204)
    default:
      return error(404, "NOT_FOUND")
    }
  }

  private func shared(_ method: String, _ route: [String], _ json: [String: Any], _ viewer: User?) -> Response {
    guard let index = records.firstIndex(where: { $0.wishlist.shareToken == route.first }) else {
      return error(404, "WISHLIST_NOT_FOUND")
    }
    let record = records[index]
    let isOwner = viewer?.id == record.ownerID
    let typedName = (json["name"] as? String)?.trimmed ?? ""
    let name = typedName.isEmpty ? viewer?.displayName : typedName

    switch (method, Array(route.dropFirst())) {
    case ("GET", []):
      let owner = accounts.first { $0.user.id == record.ownerID }!.user
      let header = SharedWishlist.Header(
        id: record.wishlist.id, title: record.wishlist.title, description: record.wishlist.description,
        eventDate: record.wishlist.eventDate, ownerName: owner.displayName)
      let items = record.items.sorted {
        $0.priority != $1.priority ? $0.priority > $1.priority : $0.createdAt < $1.createdAt
      }
      return encode(
        SharedWishlist(
          wishlist: header, isOwner: isOwner,
          isFollowing: isOwner ? false : record.followers.contains { $0.userId == viewer?.id },
          items: isOwner ? items : items.map { sharedItem($0, viewer: viewer) }))
    case ("PUT", ["follow"]):
      guard let viewer else { return error(401, "AUTH_REQUIRED") }
      guard !isOwner else { return error(403, "OWN_WISHLIST") }
      if !record.followers.contains(where: { $0.userId == viewer.id }) {
        records[index].followers.append(Follower(userId: viewer.id, displayName: viewer.displayName, followedAt: now()))
      }
      return ok(["isFollowing": true])
    case ("DELETE", ["follow"]):
      guard let viewer else { return error(401, "AUTH_REQUIRED") }
      records[index].followers.removeAll { $0.userId == viewer.id }
      return ok(["isFollowing": false])
    case ("POST", let path) where path.count == 3 && path[0] == "items" && path[2] == "purchases":
      guard !isOwner else { return error(403, "OWN_WISHLIST") }
      guard let item = record.items.first(where: { $0.id == path[1] }) else { return error(404, "ITEM_NOT_FOUND") }
      guard let name else { return error(400, "NAME_REQUIRED") }
      let quantity = json["quantity"] as? Int ?? 1
      let remaining = item.quantity - active(item.id)
      if remaining <= 0 { return error(409, "ALREADY_BOUGHT") }
      if quantity > remaining { return error(409, "NOT_ENOUGH_REMAINING", ["remaining": remaining]) }
      storedPurchases[item.id, default: []].append(
        purchase("purchase-\(nextID())", quantity, name, by: viewer?.id, at: now()))
      return encode(sharedItem(item, viewer: viewer), status: 201)
    case ("POST", let path) where path.count == 3 && path[0] == "purchases" && path[2] == "revert":
      guard !isOwner else { return error(403, "OWN_WISHLIST") }
      guard let name else { return error(400, "NAME_REQUIRED") }
      for item in record.items {
        guard let purchaseIndex = storedPurchases[item.id]?.firstIndex(where: { $0.purchase.id == path[1] }) else {
          continue
        }
        if storedPurchases[item.id]![purchaseIndex].purchase.revertedAt != nil { return error(409, "ALREADY_UNDONE") }
        storedPurchases[item.id]![purchaseIndex].purchase.revertedAt = now()
        storedPurchases[item.id]![purchaseIndex].purchase.revertedByName = name
        return encode(sharedItem(item, viewer: viewer))
      }
      return error(404, "PURCHASE_NOT_FOUND")
    default:
      return error(404, "NOT_FOUND")
    }
  }

  private func scrape(_ input: String) -> Response {
    let link = input.range(of: "https?://\\S+", options: .regularExpression).map { String(input[$0]) }
    guard let link else {
      return encode(
        ScrapeResult(
          input: input, url: nil, finalUrl: nil, status: .partial, title: input.trimmed, image: nil, price: nil,
          currency: nil, siteName: nil, sources: .init(title: .pastedText),
          messages: [ScrapeMessage(code: "NO_LINK_FOUND", params: nil, message: "No link found")]))
    }
    return encode(
      ScrapeResult(
        input: input, url: link, finalUrl: link, status: .ok, title: "Wireless Headphones",
        image: "https://images.test/headphones.png", price: 79.99, currency: "EUR", siteName: "Shop",
        sources: .init(title: .structuredData, image: .previewTags, price: .structuredData), messages: []))
  }

  // MARK: Helpers

  private func summary(_ record: Record) -> Wishlist {
    var wishlist = record.wishlist
    wishlist.itemCount = record.items.count
    return wishlist
  }

  private func active(_ itemID: String) -> Int {
    (storedPurchases[itemID] ?? []).filter { $0.purchase.revertedAt == nil }.reduce(0) { $0 + $1.purchase.quantity }
  }

  private func sharedItem(_ item: Item, viewer: User?) -> Item {
    var item = item
    item.purchasedQuantity = active(item.id)
    item.purchases = (storedPurchases[item.id] ?? []).map { entry in
      var purchase = entry.purchase
      purchase.isMine = viewer != nil && entry.buyerID == viewer?.id
      return purchase
    }
    return item
  }

  private func apply(_ json: [String: Any], to item: inout Item) {
    if let title = json["title"] as? String { item.title = title }
    if json.keys.contains("notes") { item.notes = json["notes"] as? String }
    if json.keys.contains("imageUrl") {
      item.imageUrl = json["imageUrl"] as? String
      item.displayImageUrl = item.imageUrl
    }
    if json.keys.contains("price") { item.price = (json["price"] as? NSNumber)?.doubleValue }
    if json.keys.contains("currency") { item.currency = json["currency"] as? String }
    if let priority = json["priority"] as? Int { item.priority = priority }
    if let quantity = json["quantity"] as? Int { item.quantity = quantity }
    if let links = json["links"] as? [String] { item.links = links }
    item.updatedAt = now()
  }

  private func nextID() -> Int {
    counter += 1
    return counter
  }

  private func now() -> String {
    Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
  }

  private func ok(_ object: [String: Any], status: Int = 200) -> Response {
    Response(status: status, body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
  }

  private func encode(_ value: some Encodable, status: Int = 200) -> Response {
    Response(status: status, body: (try? JSONEncoder().encode(value)) ?? Data())
  }

  private func error(_ status: Int, _ code: String, _ params: [String: Any] = [:]) -> Response {
    ok(["code": code, "message": code, "params": params], status: status)
  }

  private func image(for name: String) -> Data {
    if let data = images[name] { return data }
    let hue = CGFloat(name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 360) / 360
    let data = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600)).pngData { context in
      UIColor(hue: hue, saturation: 0.45, brightness: 0.95, alpha: 1).setFill()
      context.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
      UIColor.white.withAlphaComponent(0.8).setFill()
      context.cgContext.fillEllipse(in: CGRect(x: 150, y: 150, width: 300, height: 300))
    }
    images[name] = data
    return data
  }
}
#endif
