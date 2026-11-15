import Foundation
import Observation

nonisolated enum Language: String, CaseIterable, Identifiable, Sendable {
  case de, en

  var id: String { rawValue }
  /// Language names are shown in their own language, like in the web app.
  var nativeName: String {
    switch self {
    case .de: "Deutsch"
    case .en: "English"
    }
  }

  var defaultLocale: String {
    switch self {
    case .de: "de_DE"
    case .en: "en_US"
    }
  }
}

nonisolated enum DateStyle: Sendable {
  case date, longDate, dateTime
}

/// Translations shared with the web app plus number/date formatting for the system language.
///
/// The language follows iOS: the device language, or the one picked for this app under
/// Settings → Wishlist → Language (iOS relaunches the app after a change).
@Observable
final class L10n {
  let language: Language
  /// Keeps the device region (de-AT, en-GB, …) when the language matches.
  let locale: Locale

  // Formatters are expensive to create and are needed for every price and date in a list.
  @ObservationIgnored private var dateFormatters: [DateStyle: DateFormatter] = [:]
  @ObservationIgnored private var priceFormatters: [String: NumberFormatter] = [:]

  init(language: Language = L10n.detect(preferred: Bundle.main.preferredLocalizations + Locale.preferredLanguages)) {
    self.language = language
    let identifier = Locale.preferredLanguages.first { $0.lowercased().hasPrefix(language.rawValue) }
    locale = Locale(identifier: identifier ?? language.defaultLocale)
  }

  /// The first supported language wins; everyone else gets English.
  static func detect(preferred: [String]) -> Language {
    for tag in preferred {
      if let language = Language(rawValue: String(tag.prefix(2)).lowercased()) { return language }
    }
    return .en
  }

  // MARK: Translation

  func t(_ key: TKey, _ params: [String: String] = [:]) -> String {
    let dictionary = language == .de ? Translations.de : Translations.en
    let value = dictionary[key] ?? Translations.en[key] ?? .text(key.rawValue)
    let template: String
    switch value {
    case .text(let text):
      template = text
    case .plural(let one, let other):
      template = Int(params["count"] ?? "") == 1 ? one : other
    }
    return Self.interpolate(template, params)
  }

  func t(_ key: TKey, count: Int, _ params: [String: String] = [:]) -> String {
    t(key, params.merging(["count": String(count)]) { $1 })
  }

  func t(_ key: AppKey) -> String {
    AppStrings.text(key, language)
  }

  /// For keys built at runtime (error codes, scrape sources, …).
  func t(raw: String, _ params: [String: String] = [:]) -> String? {
    TKey(rawValue: raw).map { t($0, params) }
  }

  static func interpolate(_ template: String, _ params: [String: String]) -> String {
    guard !params.isEmpty, template.contains("{") else { return template }
    var result = template
    for (name, value) in params {
      result = result.replacingOccurrences(of: "{\(name)}", with: value)
    }
    return result
  }

  // MARK: Formatting

  func formatDate(_ value: String?, style: DateStyle = .date) -> String {
    guard let value, let date = Self.parseDate(value) else { return "" }
    if let formatter = dateFormatters[style] { return formatter.string(from: date) }
    let formatter = DateFormatter()
    formatter.locale = locale
    switch style {
    case .date:
      formatter.dateStyle = .medium
    case .longDate:
      formatter.dateStyle = .full
    case .dateTime:
      formatter.dateStyle = .medium
      formatter.timeStyle = .short
    }
    dateFormatters[style] = formatter
    return formatter.string(from: date)
  }

  func formatPrice(_ price: Double?, currency: String?) -> String {
    guard let price else { return "" }
    let code = (currency?.isEmpty == false ? currency! : "EUR").uppercased()
    let formatter = priceFormatters[code] ?? {
      let formatter = NumberFormatter()
      formatter.locale = locale
      formatter.numberStyle = .currency
      formatter.currencyCode = code
      priceFormatters[code] = formatter
      return formatter
    }()
    return formatter.string(from: NSNumber(value: price)) ?? "\(price) \(currency ?? "")".trimmed
  }

  /// Date-only values (event dates) are calendar days, not UTC instants.
  static func parseDate(_ value: String) -> Date? {
    let parts = value.split(separator: "-")
    if value.count == 10, parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) {
      return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }
    if let date = try? Date(value, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)) {
      return date
    }
    return try? Date(value, strategy: .iso8601)
  }

  static func dateOnlyString(_ date: Date) -> String {
    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
  }

  // MARK: Errors

  /// Translates the API's error `code`; unknown codes get a generic message.
  func errorMessage(_ error: Error) -> String {
    switch error {
    case let error as LocalizedAppError:
      return t(error.key)
    case APIError.offline:
      return t(.errorsOFFLINE)
    case APIError.server(_, let code?, _, let params):
      let strings = params.mapValues(\.description)
      return t(raw: "errors.\(code)", strings) ?? t(.errorsUNKNOWN)
    default:
      return t(.errorsUNKNOWN)
    }
  }

  func scrapeMessage(_ message: ScrapeMessage) -> String {
    t(raw: "scrape.msg.\(message.code)", (message.params ?? [:]).mapValues(\.description)) ?? message.message
  }

  func priorityLabel(_ level: Int) -> String {
    t(raw: "priority.\(level)") ?? ""
  }
}

nonisolated enum AppHostname {
  /// "https://www.shop.com/x" → "shop.com"
  static func of(_ link: String) -> String {
    guard let host = URL(string: link)?.host() else { return link }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }
}
