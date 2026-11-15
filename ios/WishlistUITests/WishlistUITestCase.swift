import XCTest

/// Launches the app against its built-in mock backend (see Wishlist/Testing/UITestEnvironment.swift), so the
/// tests run without a server – on a local simulator and on Xcode Cloud.
///
/// Seed data: Ada owns "Christmas 2026" (Cookbook, Espresso cups 2 of 4 bought by Bob, Wool socks bought by
/// Grandma) and Bob follows it. Both use the password "password123".
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

  // MARK: Actions

  @discardableResult
  func waitFor(_ element: XCUIElement, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line)
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

  func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
    let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
    XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: timeout), .completed, "\(element) is still shown", file: file, line: line)
  }

  func tap(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
    waitFor(element(identifier), file: file, line: line).tap()
  }

  func type(_ text: String, into identifier: String, replacing: Bool = false) {
    let field = waitFor(element(identifier))
    if replacing, let current = field.value as? String, !current.isEmpty, current != field.placeholderValue {
      // A plain tap may put the cursor anywhere in the text; at the trailing edge it lands at the end.
      field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
      field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
    } else {
      field.tap()
    }
    if field.elementType == .secureTextField { dismissStrongPasswordSuggestion() }
    field.typeText(text)
  }

  /// New-password fields offer "Use Strong Password?" in place of the keyboard, which swallows typing.
  private func dismissStrongPasswordSuggestion() {
    guard app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout: 1.5) else { return }
    app.buttons.matching(identifier: "xmark").firstMatch.tap()
    waitForAbsence(app.buttons["GenerateStrongPasswordButton"])
  }

  /// Toasts sit at the bottom and take taps, so wait until one is gone before tapping what's below it.
  func waitForToastToDisappear() {
    let toast = app.descendants(matching: .any).matching(identifier: "toast").firstMatch
    if toast.exists { waitForAbsence(toast, timeout: 6) }
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
    XCTAssertTrue(toast.waitForExistence(timeout: 5), "No toast with \"\(text)\"", file: file, line: line)
  }

  func login(email: String, password: String = "password123") {
    type(email, into: "login.email")
    type(password, into: "login.password")
    tap("login.submit")
  }

  func openList(_ title: String) {
    waitFor(text(title)).tap()
  }

  /// Opens a list through its share link, like someone who received the link.
  func openSharedLink(_ token: String = WishlistUITestCase.christmasToken) {
    tap("login.openLink")
    type("https://wishlist.test/s/\(token)", into: "openLink.field")
    tap("openLink.open")
  }

  func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) {
    var swipes = 0
    while !element.isHittable, swipes < maxSwipes {
      app.swipeUp()
      swipes += 1
    }
  }
}
