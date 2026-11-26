import XCTest

/// Friends and family mark wishes as bought through the share link.
final class GuestUITests: WishlistUITestCase {
  func testAnonymousGuestOpensSharedLink() {
    launch()
    openSharedLink()
    waitFor(text("Ada's wishlist"))
    XCTAssertEqual(waitFor(element("status.Wool socks")).label, "Bought")
    XCTAssertEqual(element("status.Espresso cups").label, "2 of 4 bought")
    XCTAssertFalse(element("guest.follow").exists, "Only signed-in users can follow")
    waitFor(element("guest.login"))
  }

  func testUnknownLinkShowsNotFound() {
    launch()
    openSharedLink("doesNotExist123")
    waitFor(text("Wishlist not found"))
  }

  func testInvalidLinkIsRejected() {
    launch()
    tap("login.openLink")
    type("hello world", into: "openLink.field")
    tap("openLink.open")
    waitFor(text("That doesn't look like a wishlist link."))
  }

  func testGuestNeedsANameToMarkAsBought() {
    launch()
    openSharedLink()
    tap("buy.Cookbook")
    tap("buy.confirm")
    expectToast(containing: "Please enter your name")
  }

  func testMarkAsBoughtAndUndo() {
    launch(signedInAs: .bob)
    openList("Christmas 2026")
    tap("buy.Cookbook")
    XCTAssertEqual(waitFor(element("buy.name")).value as? String, "Bob")
    tap("buy.confirm")
    expectToast(containing: "Thanks!")
    let status = element("status.Cookbook")
    XCTAssertEqual(waitFor(status).label, "Bought")
    XCTAssertFalse(element("buy.Cookbook").isEnabled)

    // The bought wish moved to the bottom, under the thank-you toast.
    waitForToastToDisappear()
    tap("history.Cookbook")
    tap("undo.Bob")
    waitFor(app.alerts.firstMatch)
    confirm("Undo")
    let reopened = expectation(for: NSPredicate(format: "label == 'Still needed'"), evaluatedWith: status)
    wait(for: [reopened], timeout: Self.defaultTimeout)
  }

  func testBuyRemainingQuantity() {
    launch(signedInAs: .bob)
    openList("Christmas 2026")
    scrollTo(element("buy.Espresso cups"))
    tap("buy.Espresso cups")
    waitFor(text("How many? (2 still needed)"))
    // Stepper buttons are named "<identifier>-Increment" since iOS 27, plain "Increment" before.
    waitFor(element("buy.quantity")).buttons.matching(NSPredicate(format: "identifier ENDSWITH 'Increment'"))
      .firstMatch.tap()
    tap("buy.confirm")
    XCTAssertEqual(waitFor(element("status.Espresso cups")).label, "Bought")
  }

  func testFilterBoughtAndOpenWishes() {
    launch(signedInAs: .bob)
    openList("Christmas 2026")
    let filter = waitFor(element("guest.filter"))

    filter.buttons["Bought"].tap()
    waitFor(text("Wool socks"))
    waitForAbsence(text("Cookbook"))

    filter.buttons["Still needed"].tap()
    waitFor(text("Cookbook"))
    waitForAbsence(text("Wool socks"))
  }

  func testSortByPrice() {
    launch(signedInAs: .bob)
    openList("Christmas 2026")
    tap("sort.menu")
    button("Price: high to low").tap()
    let cookbook = waitFor(text("Cookbook"))
    let cups = waitFor(text("Espresso cups"))
    XCTAssertLessThan(cookbook.frame.minY, cups.frame.minY)
  }

  func testUnfollowAndFollowAgain() {
    launch(signedInAs: .bob)
    openList("Christmas 2026")
    let follow = waitFor(element("guest.follow"))
    XCTAssertEqual(follow.label, "Following")
    follow.tap()
    let unfollowed = expectation(for: NSPredicate(format: "label == 'Follow'"), evaluatedWith: follow)
    wait(for: [unfollowed], timeout: Self.defaultTimeout)

    // Bob has no lists of his own, so without the followed one the start page shows its welcome.
    tap("guest.home")
    waitFor(button("Create my first wishlist"))
    XCTAssertFalse(text("Christmas 2026").exists)
  }

  func testUnfollowFromStartPage() {
    launch(signedInAs: .bob)
    revealSwipeActions(of: text("Christmas 2026"), action: "Unfollow").tap()
    expectToast(containing: "You no longer follow")
    waitForAbsence(text("Christmas 2026"))
  }

  func testLoginFromSharedListKeepsTheList() {
    launch()
    openSharedLink()
    tap("guest.login")
    login(email: "bob@example.com")
    waitFor(element("guest.follow"))
    waitFor(text("Ada's wishlist"))
  }
}

final class PerformanceUITests: WishlistUITestCase {
  /// A list with 20 pictures has to open and scroll to the end without getting stuck.
  func testLargeListOpensAndScrolls() {
    launch(scenario: "many", signedInAs: .bob)
    openList("Big list")
    waitFor(element("buy.Wish 20"))
    let last = element("buy.Wish 1")
    scrollTo(last, maxSwipes: 20)
    XCTAssertTrue(last.isHittable)
  }

  func testScrollingLargeOwnList() {
    launch(scenario: "many", signedInAs: .ada)
    openList("Big list")
    waitFor(text("Wish 20"))
    let options = XCTMeasureOptions()
    options.iterationCount = 3
    options.invocationOptions = [.manuallyStop]
    measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
      app.swipeUp(velocity: .fast)
      stopMeasuring()
      app.swipeDown(velocity: .fast)
    }
  }

  /// Opening a list must not hitch, also when its data arrives while the screen is being pushed.
  func testOpeningLargeOwnList() {
    measureOpeningBigList(as: .ada)
  }

  func testOpeningLargeSharedList() {
    measureOpeningBigList(as: .bob)
  }

  /// Worst case, like opening a list for the first time: nothing cached, and the data arrives while the
  /// screen is still being pushed.
  private func measureOpeningBigList(as account: Account) {
    // `xcodebuild … TEST_RUNNER_PERF_LATENCY_MS=1500` tries other network delays.
    let latency = ProcessInfo.processInfo.environment["PERF_LATENCY_MS"] ?? "300"
    launch(
      scenario: "many", signedInAs: account,
      environment: ["UITEST_ANIMATIONS": "1", "UITEST_LATENCY_MS": latency, "UITEST_LIST_CACHE": "0"])
    let row = waitFor(text("Big list"))
    let options = XCTMeasureOptions()
    options.iterationCount = 10
    options.invocationOptions = [.manuallyStop]
    measure(metrics: [XCTOSSignpostMetric.navigationTransitionMetric], options: options) {
      waitForHittable(row).tap()
      XCTAssertTrue(text("Wish 20").waitForExistence(timeout: Self.defaultTimeout))
      stopMeasuring()
      app.navigationBars.buttons.element(boundBy: 0).tap()
      waitForHittable(row)
    }
  }

  @discardableResult
  private func waitForHittable(_ element: XCUIElement) -> XCUIElement {
    let hittable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: element)
    XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: Self.defaultTimeout), .completed, "\(element) is not hittable")
    return element
  }
}
