import XCTest

/// Launches the app against its built-in mock backend (see Wishlist/Testing/UITestEnvironment.swift), so the
/// tests run without a server – on a local simulator and on Xcode Cloud.
///
/// Seed data: Ada owns "Christmas 2026" (Cookbook, Espresso cups 2 of 4 bought by Bob, Wool socks bought by
/// Grandma) and Bob follows it. Both use the password "password123".
/// XCUIApplication and XCUIElement are main-actor types, and XCTest runs tests on the main thread.
@MainActor
class WishlistUITestCase: XCTestCase {
  static let christmasToken = "christmasToken2026"
  var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  enum Account: String {
    case ada, bob
  }

  func launch(
    scenario: String = "standard", signedInAs account: Account? = nil, language: String = "en",
    environment: [String: String] = [:]
  ) {
    app = XCUIApplication()
    app.launchEnvironment.merge(environment) { $1 }
    app.launchArguments = [
      "-ui-testing", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "de" ? "de_DE" : "en_US",
    ]
    app.launchEnvironment["UITEST_SCENARIO"] = scenario
    if let account { app.launchEnvironment["UITEST_LOGIN"] = account.rawValue }
    app.launch()
  }

  // MARK: Queries

  func element(_ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  func text(_ label: String) -> XCUIElement {
    app.staticTexts[label].firstMatch
  }

  func button(_ label: String) -> XCUIElement {
    app.buttons[label].firstMatch
  }

  /// Any element by label, for controls whose accessibility type differs between iOS versions and devices
  /// (e.g. a SwiftUI Link is a link on iPhone with iOS 26 but a button on iPad and iOS 18).
  func labeled(_ label: String) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
  }

  // MARK: Actions

  /// Xcode Cloud's simulators are several times slower than a local Mac, so waits are generous;
  /// they only take this long when something is actually wrong.
  static let defaultTimeout: TimeInterval = 15

  @discardableResult
  func waitFor(_ element: XCUIElement, timeout: TimeInterval = defaultTimeout, file: StaticString = #filePath, line: UInt = #line)
    -> XCUIElement
  {
    if !element.waitForExistence(timeout: timeout) {
      attachHierarchy()
      XCTFail("\(element) did not appear", file: file, line: line)
    }
    return element
  }

  /// Keeps what was on screen with the test report, so failures can be understood without rerunning.
  func attachHierarchy() {
    let attachment = XCTAttachment(string: app.debugDescription)
    attachment.name = "UI hierarchy"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval = defaultTimeout, file: StaticString = #filePath, line: UInt = #line) {
    let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
    XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: timeout), .completed, "\(element) is still shown", file: file, line: line)
  }

  func tap(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
    waitFor(element(identifier), file: file, line: line).tap()
  }

  func type(_ text: String, into identifier: String, replacing: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
    let field = waitFor(element(identifier), file: file, line: line)
    let isSecure = field.elementType == .secureTextField
    // Slow simulators drop taps during transitions, and password fields may show AutoFill's strong
    // password suggestion instead of the keyboard, so check that the text arrived and retry otherwise.
    for attempt in 0..<3 {
      if replacing, let current = currentText(of: field), !current.isEmpty {
        focus(field, atTrailingEdge: true)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
      } else {
        focus(field)
      }
      if isSecure { dismissStrongPasswordSuggestion() }
      if attempt == 0 {
        field.typeText(text)
      } else {
        // Password AutoFill sometimes drops keystrokes typed in one go.
        for character in text { field.typeText(String(character)) }
      }
      // Depending on the device, secure fields report one bullet per character or a single one.
      let entered = currentText(of: field)
      if isSecure ? entered?.isEmpty == false : entered?.hasSuffix(text) == true { return }
      if isSecure, let entered = currentText(of: field) {
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: entered.count))
      }
    }
    XCTFail("Could not type \"\(text)\" into \(identifier)", file: file, line: line)
  }

  /// The field's text, or nil while it only shows its placeholder.
  private func currentText(of field: XCUIElement) -> String? {
    guard let value = field.value as? String, value != field.placeholderValue else { return nil }
    return value
  }

  private func hasKeyboardFocus(_ field: XCUIElement) -> Bool {
    (field.value(forKey: "hasKeyboardFocus") as? Bool) == true
  }

  /// Taps until the field has keyboard focus; a tap at the trailing edge puts the cursor at the end.
  private func focus(_ field: XCUIElement, atTrailingEdge: Bool = false) {
    // On iOS 18 a form field's frame includes the row's padding, so the very edge can miss the text input.
    for dx in [0.97, 0.9, 0.75] {
      if atTrailingEdge {
        field.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
      } else {
        field.tap()
      }
      let focused = expectation(for: NSPredicate { [unowned self] _, _ in
        MainActor.assumeIsolated { hasKeyboardFocus(field) }
      }, evaluatedWith: nil)
      if XCTWaiter().wait(for: [focused], timeout: 3) == .completed { return }
    }
  }

  /// New-password fields offer "Use Strong Password?" in place of the keyboard, which swallows typing.
  private func dismissStrongPasswordSuggestion() {
    guard app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout: 3) else { return }
    app.buttons.matching(identifier: "xmark").firstMatch.tap()
    waitForAbsence(app.buttons["GenerateStrongPasswordButton"])
  }

  /// Swipes a row until its swipe actions show; a swipe during an animation is sometimes lost.
  func revealSwipeActions(of row: XCUIElement, action: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
    let button = button(action)
    for _ in 0..<3 {
      reveal(row, file: file, line: line).swipeLeft()
      if button.waitForExistence(timeout: 3) { return button }
    }
    return waitFor(button, file: file, line: line)
  }

  /// Toasts sit at the bottom and take taps, so wait until one is gone before tapping what's below it.
  func waitForToastToDisappear() {
    let toast = app.descendants(matching: .any).matching(identifier: "toast").firstMatch
    if toast.exists { waitForAbsence(toast) }
  }

  /// Buttons of alerts and confirmation dialogs.
  func confirm(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
    let candidates = [app.alerts.buttons[label], app.sheets.buttons[label], app.buttons[label]]
    for candidate in candidates where candidate.waitForExistence(timeout: 2) {
      candidate.firstMatch.tap()
      return
    }
    XCTFail("No \"\(label)\" button to confirm", file: file, line: line)
  }

  func expectToast(containing text: String, file: StaticString = #filePath, line: UInt = #line) {
    let toast = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier == 'toast' AND label CONTAINS %@", text)
    ).firstMatch
    XCTAssertTrue(toast.waitForExistence(timeout: Self.defaultTimeout), "No toast with \"\(text)\"", file: file, line: line)
  }

  func login(email: String, password: String = "password123") {
    type(email, into: "login.email")
    // Shown as plain text, the password can't be swallowed by AutoFill and the test can verify it
    // (secure fields on iPad and iOS 18 report a single bullet, whatever was typed).
    let showPassword = app.buttons["eye"].firstMatch
    if showPassword.exists { showPassword.tap() }
    type(password, into: "login.password")
    tap("login.submit")
  }

  func openList(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
    reveal(text(title), file: file, line: line).tap()
  }

  /// Opens a list through its share link, like someone who received the link.
  func openSharedLink(_ token: String = WishlistUITestCase.christmasToken) {
    tap("login.openLink")
    type("https://wishlist.test/s/\(token)", into: "openLink.field")
    tap("openLink.open")
  }

  /// Scrolls until the element can be tapped. Lists load rows lazily, and rows at the bottom sit behind the
  /// toolbar, so on smaller screens (Xcode Cloud) an element may not exist or not be hittable yet.
  @discardableResult
  func reveal(_ element: XCUIElement, maxSwipes: Int = 6, file: StaticString = #filePath, line: UInt = #line)
    -> XCUIElement
  {
    _ = element.waitForExistence(timeout: 3)
    for _ in 0..<maxSwipes {
      if element.exists, element.isHittable, isAboveToolbar(element) { return element }
      app.swipeUp(velocity: .slow)
    }
    if !element.isHittable { waitFor(element, file: file, line: line) }
    return element
  }

  /// A row partly behind the bottom toolbar counts as hittable, but swipes and taps on its centre hit the toolbar.
  private func isAboveToolbar(_ element: XCUIElement) -> Bool {
    let toolbar = app.toolbars.firstMatch
    guard toolbar.exists, !toolbar.frame.isEmpty else { return true }
    return element.frame.maxY <= toolbar.frame.minY
  }

  func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) {
    reveal(element, maxSwipes: maxSwipes)
  }
}
