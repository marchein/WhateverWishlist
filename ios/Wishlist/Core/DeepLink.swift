import Foundation

/// Finds the share token in links like https://wishlist.example.com/s/<token>,
/// whateverwishlist://s/<token>, a whole pasted message containing such a link, or a bare token.
nonisolated enum DeepLink {
  private static var tokenPattern: Regex<Substring> { /^[A-Za-z0-9_-]{8,128}$/ }

  static func shareToken(from url: URL, scheme: String) -> String? {
    if url.scheme?.lowercased() == scheme.lowercased() {
      // whateverwishlist://s/<token> or whateverwishlist:///s/<token>
      let parts = ([url.host()].compactMap { $0 } + url.pathComponents).filter { $0 != "/" && !$0.isEmpty }
      return token(in: parts)
    }
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
    return token(in: url.pathComponents.filter { $0 != "/" })
  }

  static func shareToken(fromText text: String, scheme: String) -> String? {
    let text = text.trimmed
    guard !text.isEmpty else { return nil }
    if let url = URL(string: text), url.scheme != nil, let token = shareToken(from: url, scheme: scheme) {
      return token
    }
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
      for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        if let url = match.url, let token = shareToken(from: url, scheme: scheme) { return token }
      }
    }
    if let custom = text.range(of: "\(scheme)://\\S+", options: [.regularExpression, .caseInsensitive]),
      let url = URL(string: String(text[custom])), let token = shareToken(from: url, scheme: scheme)
    {
      return token
    }
    return text.wholeMatch(of: tokenPattern) != nil ? text : nil
  }

  private static func token(in parts: [String]) -> String? {
    guard let index = parts.lastIndex(of: "s"), index + 1 < parts.count else { return nil }
    let candidate = parts[index + 1]
    return candidate.wholeMatch(of: tokenPattern) != nil ? candidate : nil
  }
}
