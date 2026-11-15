import Foundation
import SwiftUI

struct Toast: Identifiable, Equatable {
  enum Kind { case success, error }
  let id = UUID()
  let kind: Kind
  let message: String
}

/// Where the session token is kept: the Keychain in the app, memory in UI tests.
protocol TokenStore {
  func read() -> String?
  func write(_ token: String?)
}

struct KeychainTokenStore: TokenStore {
  func read() -> String? { Keychain.read("token") }
  func write(_ token: String?) { Keychain.write(token, for: "token") }
}

final class MemoryTokenStore: TokenStore {
  private var token: String?
  init(token: String? = nil) { self.token = token }
  func read() -> String? { token }
  func write(_ token: String?) { self.token = token }
}

/// App-wide state: the signed-in session, the API client, recently loaded lists and transient toasts.
@Observable
final class AppModel {
  private static let userKey = "wishlist.user"
  private static let guestNameKey = "wishlist.guestName"

  let config: AppConfig
  let api: APIClient
  let l10n: L10n
  private(set) var token: String?
  private(set) var user: User?
  var toast: Toast?
  /// Set once the start page has its lists, so the launch splash can step aside without revealing a spinner.
  var isFirstScreenReady = false

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let tokenStore: TokenStore
  @ObservationIgnored private var toastTask: Task<Void, Never>?

  // Last loaded lists, shown immediately when a list is opened again while fresh data loads.
  @ObservationIgnored private var sharedCache: [String: SharedWishlist] = [:]
  @ObservationIgnored private var ownedCache: [String: WishlistWithItems] = [:]
  @ObservationIgnored private var ownedIDs: [String: String] = [:]

  var isLoggedIn: Bool { token != nil }

  init(
    config: AppConfig = .current, l10n: L10n, session: URLSession = .shared, defaults: UserDefaults = .standard,
    tokenStore: TokenStore = KeychainTokenStore()
  ) {
    self.config = config
    self.l10n = l10n
    self.defaults = defaults
    self.tokenStore = tokenStore
    api = APIClient(config: config, session: session)
    if let token = tokenStore.read() {
      self.token = token
      user = defaults.data(forKey: Self.userKey).flatMap { try? JSONDecoder().decode(User.self, from: $0) }
    }
    api.token = token
    api.onUnauthorized = { [weak self] in
      guard let self, self.isLoggedIn else { return }
      self.logout()
      self.show(error: APIError.server(status: 401, code: "AUTH_REQUIRED", message: nil, params: [:]))
    }
  }

  // MARK: Session

  func login(email: String, password: String) async throws {
    setSession(try await api.login(email: email.trimmed, password: password))
  }

  func register(email: String, password: String, displayName: String) async throws {
    setSession(try await api.register(email: email.trimmed, password: password, displayName: displayName.trimmed))
  }

  /// Refreshes the cached profile (e.g. a display name changed by an admin); a revoked session logs out.
  func refreshUser() async {
    guard isLoggedIn, let user = try? await api.me() else { return }
    self.user = user
    defaults.set(try? JSONEncoder().encode(user), forKey: Self.userKey)
  }

  func logout() {
    tokenStore.write(nil)
    clearCaches()
    defaults.removeObject(forKey: Self.userKey)
    token = nil
    user = nil
    api.token = nil
  }

  func setSession(_ response: AuthResponse) {
    tokenStore.write(response.token)
    clearCaches()
    defaults.set(try? JSONEncoder().encode(response.user), forKey: Self.userKey)
    token = response.token
    user = response.user
    api.token = response.token
  }

  /// Name used when marking items as bought – what was typed last time, or the account name.
  var buyerName: String {
    defaults.string(forKey: Self.guestNameKey) ?? user?.displayName ?? ""
  }

  func rememberBuyerName(_ name: String) {
    defaults.set(name, forKey: Self.guestNameKey)
  }

  // MARK: Cached lists

  /// Performance tests switch this off to measure every opening like the first one.
  @ObservationIgnored var cachesLists = true

  func cachedShared(token: String) -> SharedWishlist? { cachesLists ? sharedCache[token] : nil }
  func cachedOwned(id: String) -> WishlistWithItems? { cachesLists ? ownedCache[id] : nil }
  /// Lets an own list open straight into the editor instead of waiting for the share-link lookup.
  func ownedWishlistID(token: String) -> String? { ownedIDs[token] }

  func remember(_ shared: SharedWishlist, token: String) {
    sharedCache[token] = shared
    if shared.isOwner { ownedIDs[token] = shared.wishlist.id }
  }

  func remember(_ wishlist: WishlistWithItems) {
    ownedCache[wishlist.id] = wishlist
    ownedIDs[wishlist.shareToken] = wishlist.id
  }

  func remember(ownLists: [Wishlist]) {
    for list in ownLists { ownedIDs[list.shareToken] = list.id }
  }

  func forget(token: String) {
    sharedCache[token] = nil
    ownedIDs[token] = nil
  }

  /// Another account must never see data loaded for the previous one.
  private func clearCaches() {
    sharedCache = [:]
    ownedCache = [:]
    ownedIDs = [:]
  }

  // MARK: Toasts

  func show(success message: String) {
    present(Toast(kind: .success, message: message), seconds: 2.5)
  }

  /// Accepts an already translated message or an error (API error codes are translated).
  func show(error: Error) {
    if error is CancellationError { return }
    present(Toast(kind: .error, message: l10n.errorMessage(error)), seconds: 4)
  }

  func show(errorMessage message: String) {
    present(Toast(kind: .error, message: message), seconds: 4)
  }

  private func present(_ toast: Toast, seconds: Double) {
    self.toast = toast
    toastTask?.cancel()
    toastTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(seconds))
      guard !Task.isCancelled, self?.toast?.id == toast.id else { return }
      self?.toast = nil
    }
  }
}

enum Route: Hashable {
  case wishlist(token: String)
  case status
}

/// Navigation state of one window.
@Observable
final class Router {
  var path: [Route] = []

  func show(token: String) {
    if path.last == .wishlist(token: token) { return }
    path.append(.wishlist(token: token))
  }

  /// After a new share link was created the old one is gone, so the screen is swapped without animation.
  func replace(token old: String, with new: String) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      path = path.map { $0 == .wishlist(token: old) ? .wishlist(token: new) : $0 }
    }
  }

  func popToRoot() {
    path.removeAll()
  }
}
