import XCTest

/// Ada manages her own list. Owners must never see purchase information.
final class OwnerUITests: WishlistUITestCase {
  override func setUp() async throws {
    try await super.setUp()
    launch(signedInAs: .ada)
  }

  private func openChristmas() {
    openList("Christmas 2026")
    waitFor(element("owner.shareURL"))
  }

  func testOwnListShowsWishesButNoPurchases() {
    openChristmas()
    XCTAssertEqual(element("owner.shareURL").label, "https://wishlist.test/s/\(Self.christmasToken)")
    reveal(text("Cookbook"))
    reveal(text("Espresso cups"))
    reveal(text("Wool socks"))
    XCTAssertFalse(element("status.Wool socks").exists)
    XCTAssertFalse(text("Bought").exists)
    XCTAssertFalse(text("Grandma").exists)
  }

  func testCreateWishlist() {
    tap("wishlists.add")
    type("Birthday", into: "createWishlist.title")
    tap("createWishlist.create")
    waitFor(element("owner.shareURL"))
    waitFor(element("owner.addFirst"))
    app.navigationBars.buttons.element(boundBy: 0).tap()
    waitFor(text("Birthday"))
  }

  func testAddWishFromPastedLink() {
    openChristmas()
    tap("owner.addWish")
    type("Look at this: https://shop.example/headphones", into: "editor.paste")
    tap("editor.fetch")
    waitFor(text("All details found"))
    // The form redraws with the fetched details; wait for the field instead of reading it mid-update.
    XCTAssertEqual(waitFor(element("editor.title")).value as? String, "Wireless Headphones")
    tap("editor.save")
    reveal(text("Wireless Headphones"))
  }

  func testAddWishManually() {
    openChristmas()
    tap("owner.addWish")
    type("Board game", into: "editor.title")
    type("19,99", into: "editor.price")
    tap("priority.5")
    type("shop.example/game", into: "editor.newLink")
    tap("editor.addLink")
    waitFor(labeled("shop.example"))
    tap("editor.save")
    reveal(text("Board game"))
  }

  func testTitleIsRequired() {
    openChristmas()
    tap("owner.addWish")
    tap("editor.save")
    expectToast(containing: "Please give your wish a title")
    tap("editor.cancel")
  }

  func testEditWish() {
    openChristmas()
    openList("Cookbook")
    type("Vegan cookbook", into: "editor.title", replacing: true)
    tap("editor.save")
    reveal(text("Vegan cookbook"))
    // The old row can still be fading out when the new title appears.
    waitForAbsence(text("Cookbook"))
  }

  func testDeleteWishFromEditor() {
    openChristmas()
    openList("Wool socks")
    scrollTo(element("editor.delete"))
    tap("editor.delete")
    confirm("Delete")
    waitForAbsence(text("Wool socks"))
  }

  func testDeleteWishBySwiping() {
    openChristmas()
    revealSwipeActions(of: app.cells.containing(.staticText, identifier: "Espresso cups").firstMatch, action: "Delete").tap()
    confirm("Delete")
    waitForAbsence(text("Espresso cups"))
  }

  func testEditListDetails() {
    openChristmas()
    tap("owner.more")
    button("Edit list details").tap()
    type("Xmas 2026", into: "editWishlist.title", replacing: true)
    tap("editWishlist.save")
    waitFor(text("Xmas 2026"))
  }

  func testPreviewAsGuestHidesPurchases() {
    openChristmas()
    tap("owner.preview")
    waitFor(text("Ada's wishlist"))
    waitFor(text("Preview: this is how others see your list. Purchases stay hidden from you."))
    XCTAssertFalse(element("buy.Cookbook").exists, "The owner preview only hints at the guests' button")
    XCTAssertFalse(text("Grandma").exists)
    tap("guest.exitPreview")
    waitFor(element("owner.shareURL"))
  }

  func testCopyLink() {
    openChristmas()
    tap("owner.copyLink")
    expectToast(containing: "Link copied")
  }

  func testRemoveFollower() {
    openChristmas()
    tap("owner.followers")
    waitFor(text("Bob"))
    tap("follower.remove.Bob")
    confirm("Remove follower")
    waitFor(text("Nobody follows this list yet."))
  }

  func testCreateNewShareLink() {
    openChristmas()
    tap("owner.more")
    button("Create a new share link").tap()
    tap("regenerate.confirm")
    expectToast(containing: "New link created")
    let url = waitFor(element("owner.shareURL"))
    XCTAssertFalse(url.label.contains(Self.christmasToken))
  }

  func testDeleteList() {
    openChristmas()
    tap("owner.more")
    button("Delete list").tap()
    confirm("Delete")
    waitFor(button("Create my first wishlist"))
    XCTAssertFalse(text("Christmas 2026").exists)
  }
}
