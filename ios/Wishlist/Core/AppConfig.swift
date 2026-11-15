import Foundation

/// Server settings baked into Info.plist from Config/App.xcconfig at build time.
nonisolated struct AppConfig: Sendable {
  static let fallbackServer = URL(string: "https://wishlist.hein.cx")!
  static let current = AppConfig(bundle: .main)

  /// Origin of the backend; the API lives below `/api`, uploads below `/uploads` and cached images below `/_cache`.
  let serverURL: URL
  /// Origin of the web app, used for share links.
  let webURL: URL
  let urlScheme: String

  init(serverURL: URL, webURL: URL? = nil, urlScheme: String = "whateverwishlist") {
    self.serverURL = serverURL
    self.webURL = webURL ?? serverURL
    self.urlScheme = urlScheme
  }

  init(bundle: Bundle) {
    func url(_ key: String) -> URL? {
      guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
      return Self.origin(raw)
    }
    let server = url("WishlistServerURL") ?? Self.fallbackServer
    let scheme = (bundle.object(forInfoDictionaryKey: "WishlistURLScheme") as? String)?.trimmed
    self.init(serverURL: server, webURL: url("WishlistWebURL"), urlScheme: scheme?.isEmpty == false ? scheme! : "whateverwishlist")
  }

  var apiURL: URL { serverURL.appending(path: "api") }

  /// Uploaded and cached images are stored as server-relative paths ("/uploads/…", "/_cache/…").
  func assetURL(_ value: String?) -> URL? {
    guard let value = value?.trimmed, !value.isEmpty else { return nil }
    if value.hasPrefix("/uploads/") || value.hasPrefix("/_cache/") {
      return URL(string: serverURL.absoluteString + value)
    }
    guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
      return nil
    }
    return url
  }

  func shareURL(token: String) -> URL {
    webURL.appending(path: "s").appending(path: token)
  }

  /// Normalizes "https://host/" to "https://host" so paths can be appended safely.
  static func origin(_ raw: String) -> URL? {
    var value = raw.trimmed
    while value.hasSuffix("/") { value.removeLast() }
    guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      url.host() != nil
    else { return nil }
    return url
  }

  static var appVersion: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    return "\(version) (\(build))"
  }
}

nonisolated extension String {
  var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
