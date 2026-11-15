/// Texts that only exist in the iOS app (the web app has an address bar and a browser around it).
/// Everything else comes from the shared dictionaries in Translations.swift.
nonisolated enum AppKey: CaseIterable, Sendable {
  case openLinkTitle, openLinkHint, openLinkPlaceholder, openLinkOpen, openLinkInvalid
  case statusApp, statusWebApp, account, editWish, openLink, languageSettings
}

nonisolated enum AppStrings {
  static func text(_ key: AppKey, _ language: Language) -> String {
    let (en, de) = pair(key)
    return language == .de ? de : en
  }

  private static func pair(_ key: AppKey) -> (String, String) {
    switch key {
    case .openLinkTitle: ("Open a shared wishlist", "Geteilte Wunschliste öffnen")
    case .openLinkHint:
      ("Paste the link someone sent you – or the whole message containing it.",
       "Füge den Link ein, den du bekommen hast – oder gleich die ganze Nachricht.")
    case .openLinkPlaceholder: ("https://…/s/…", "https://…/s/…")
    case .openLinkOpen: ("Open", "Öffnen")
    case .openLinkInvalid: ("That doesn't look like a wishlist link.", "Das sieht nicht nach einem Wunschlisten-Link aus.")
    case .statusApp: ("App version", "App-Version")
    case .statusWebApp: ("Open the web app", "Web-App öffnen")
    case .account: ("Account", "Konto")
    case .editWish: ("Edit", "Bearbeiten")
    case .openLink: ("Open link", "Link öffnen")
    case .languageSettings: ("Change language in Settings", "Sprache in den Einstellungen ändern")
    }
  }
}
