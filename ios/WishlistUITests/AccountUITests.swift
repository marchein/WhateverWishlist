import XCTest

final class AccountUITests: WishlistUITestCase {
  func testWrongPasswordShowsError() {
    launch()
    login(email: "ada@example.com", password: "wrong-password")
    expectToast(containing: "Invalid email or password")
    XCTAssertTrue(element("login.submit").exists)
  }

  func testInvalidInputIsRejectedBeforeSending() {
    launch()
    type("not-an-email", into: "login.email")
    tap("login.submit")
    expectToast(containing: "Please enter your email and password")
  }

  func testLoginAndLogout() {
    launch()
    login(email: "ada@example.com")
    waitFor(text("Christmas 2026"), timeout: 8)

    tap("wishlists.account")
    tap("wishlists.logout")
    confirm("Log out")
    waitFor(element("login.email"))
  }

  func testRegisterShowsEmptyStartPage() {
    launch(scenario: "empty")
    waitFor(app.segmentedControls.buttons["Create account"]).tap()
    type("Carla", into: "login.name")
    login(email: "carla@example.com")
    waitFor(text("Hi Carla!"), timeout: 8)
    waitFor(button("Create my first wishlist"))
  }

  func testRegisterWithTakenEmailShowsError() {
    launch()
    waitFor(app.segmentedControls.buttons["Create account"]).tap()
    type("Ada", into: "login.name")
    login(email: "ada@example.com")
    expectToast(containing: "already exists")
  }

  func testSessionIsKeptAcrossScreens() {
    launch(signedInAs: .bob)
    waitFor(text("Christmas 2026"))
    waitFor(text("by Ada · 3 wishes · Dec 24, 2026"))
  }
}

final class StatusUITests: WishlistUITestCase {
  func testStatusShowsBackendVersionAndAddress() {
    launch()
    tap("nav.status")
    // iOS 27 reads the row's title along with the value ("Connected backend version, mock").
    XCTAssertTrue(waitFor(element("status.backendVersion")).label.hasSuffix("mock"))
    waitFor(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'https://wishlist.test/api'")).firstMatch)
  }

  func testGermanFollowsSystemLanguage() {
    launch(language: "de")
    waitFor(app.segmentedControls.buttons["Konto erstellen"])
    waitFor(text("Eine Liste für all deine Wünsche"))
  }
}
