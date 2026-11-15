import Foundation

nonisolated enum APIError: Error, Equatable, Sendable {
  /// The server could not be reached (the web app's HTTP status 0).
  case offline
  /// The API answered with an error; `code` is stable and translated by the app.
  case server(status: Int, code: String?, message: String?, params: [String: JSONScalar])
  case invalidResponse

  var status: Int? {
    if case .server(let status, _, _, _) = self { return status }
    return nil
  }

  var code: String? {
    if case .server(_, let code, _, _) = self { return code }
    return nil
  }
}

/// An error whose message is one of the shared translations.
nonisolated struct LocalizedAppError: Error, Equatable, Sendable {
  let key: TKey
}

private nonisolated struct ErrorBody: Decodable {
  let code: String?
  let message: String?
  let params: [String: JSONScalar]?
}

nonisolated struct EmptyResponse: Decodable, Sendable {}

/// Thin async client for the WhateverWishlist REST API (see backend/src/routes).
final class APIClient {
  let config: AppConfig
  /// JWT of the signed-in user; only ever sent to the configured API.
  var token: String?
  /// Called when the API rejects the stored token (expired, revoked or signed with another secret).
  var onUnauthorized: (() -> Void)?

  private let session: URLSession
  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()

  init(config: AppConfig, session: URLSession = .shared) {
    self.config = config
    self.session = session
  }

  // MARK: Auth

  func health() async throws -> HealthResponse {
    try await send("GET", "/health", timeout: 10, authenticated: false)
  }

  func register(email: String, password: String, displayName: String) async throws -> AuthResponse {
    try await send("POST", "/auth/register", body: ["email": email, "password": password, "displayName": displayName])
  }

  func login(email: String, password: String) async throws -> AuthResponse {
    try await send("POST", "/auth/login", body: ["email": email, "password": password])
  }

  func me() async throws -> User {
    try await send("GET", "/auth/me")
  }

  // MARK: Own wishlists

  func listWishlists() async throws -> [Wishlist] {
    try await send("GET", "/wishlists")
  }

  func listFollowedWishlists() async throws -> [FollowedWishlist] {
    try await send("GET", "/wishlists/followed")
  }

  func createWishlist(_ input: WishlistInput) async throws -> Wishlist {
    try await send("POST", "/wishlists", body: input)
  }

  func getWishlist(id: String) async throws -> WishlistWithItems {
    try await send("GET", "/wishlists/\(segment(id))")
  }

  func updateWishlist(id: String, _ input: WishlistInput) async throws -> Wishlist {
    try await send("PATCH", "/wishlists/\(segment(id))", body: input)
  }

  func deleteWishlist(id: String) async throws {
    let _: EmptyResponse = try await send("DELETE", "/wishlists/\(segment(id))")
  }

  func regenerateShareToken(id: String, keepFollowers: Bool) async throws -> Wishlist {
    try await send("POST", "/wishlists/\(segment(id))/share-token", body: ["keepFollowers": keepFollowers])
  }

  func listFollowers(id: String) async throws -> [Follower] {
    try await send("GET", "/wishlists/\(segment(id))/followers")
  }

  func removeFollower(wishlistID: String, userID: String) async throws {
    let _: EmptyResponse = try await send("DELETE", "/wishlists/\(segment(wishlistID))/followers/\(segment(userID))")
  }

  func createItem(wishlistID: String, _ input: ItemInput) async throws -> Item {
    try await send("POST", "/wishlists/\(segment(wishlistID))/items", body: input)
  }

  func updateItem(wishlistID: String, itemID: String, _ input: ItemInput) async throws -> Item {
    try await send("PATCH", "/wishlists/\(segment(wishlistID))/items/\(segment(itemID))", body: input)
  }

  func deleteItem(wishlistID: String, itemID: String) async throws {
    let _: EmptyResponse = try await send("DELETE", "/wishlists/\(segment(wishlistID))/items/\(segment(itemID))")
  }

  // MARK: Adding items

  func scrape(_ input: String) async throws -> ScrapeResult {
    try await send("POST", "/scrape", body: ["input": input], timeout: 45)
  }

  func uploadImage(_ image: PreparedImage) async throws -> UploadResponse {
    let boundary = "wishlist-\(UUID().uuidString)"
    var body = Data()
    body.append(Data("--\(boundary)\r\n".utf8))
    body.append(Data("Content-Disposition: form-data; name=\"image\"; filename=\"image.\(image.fileExtension)\"\r\n".utf8))
    body.append(Data("Content-Type: \(image.mimeType)\r\n\r\n".utf8))
    body.append(image.data)
    body.append(Data("\r\n--\(boundary)--\r\n".utf8))
    var request = makeRequest("POST", "/uploads", timeout: 60, authenticated: true)
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    return try await perform(request)
  }

  // MARK: Shared (public) wishlists

  func getShared(token: String) async throws -> SharedWishlist {
    try await send("GET", "/shared/\(segment(token))")
  }

  func follow(token: String) async throws -> FollowState {
    try await send("PUT", "/shared/\(segment(token))/follow", body: [String: String]())
  }

  func unfollow(token: String) async throws -> FollowState {
    try await send("DELETE", "/shared/\(segment(token))/follow")
  }

  func markPurchased(token: String, itemID: String, name: String, quantity: Int) async throws -> Item {
    struct Body: Encodable {
      let name: String
      let quantity: Int
    }
    return try await send(
      "POST", "/shared/\(segment(token))/items/\(segment(itemID))/purchases", body: Body(name: name, quantity: quantity))
  }

  func revertPurchase(token: String, purchaseID: String, name: String) async throws -> Item {
    try await send("POST", "/shared/\(segment(token))/purchases/\(segment(purchaseID))/revert", body: ["name": name])
  }

  // MARK: Plumbing

  private func segment(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? value
  }

  private func makeRequest(_ method: String, _ path: String, timeout: TimeInterval, authenticated: Bool) -> URLRequest {
    var request = URLRequest(url: URL(string: config.apiURL.absoluteString + path)!)
    request.httpMethod = method
    request.timeoutInterval = timeout
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if authenticated, let token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    return request
  }

  private func send<Response: Decodable>(
    _ method: String, _ path: String, timeout: TimeInterval = 30, authenticated: Bool = true
  ) async throws -> Response {
    try await perform(makeRequest(method, path, timeout: timeout, authenticated: authenticated))
  }

  private func send<Response: Decodable>(
    _ method: String, _ path: String, body: some Encodable, timeout: TimeInterval = 30
  ) async throws -> Response {
    var request = makeRequest(method, path, timeout: timeout, authenticated: true)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try encoder.encode(body)
    return try await perform(request)
  }

  private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch let error as URLError where error.code == .cancelled {
      throw CancellationError()
    } catch is URLError {
      throw APIError.offline
    }
    guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

    guard (200..<300).contains(http.statusCode) else {
      let body = try? decoder.decode(ErrorBody.self, from: data)
      if http.statusCode == 401, request.value(forHTTPHeaderField: "Authorization") != nil {
        onUnauthorized?()
      }
      throw APIError.server(status: http.statusCode, code: body?.code, message: body?.message, params: body?.params ?? [:])
    }

    if Response.self == EmptyResponse.self, let empty = EmptyResponse() as? Response { return empty }
    do {
      return try decoder.decode(Response.self, from: data)
    } catch {
      throw APIError.invalidResponse
    }
  }
}
