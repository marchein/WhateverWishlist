import SwiftUI

/// Everything behind a share link. Owners get their editor (without purchase data); everyone else the
/// guest view where wishes can be marked as bought.
struct SharedWishlistView: View {
  @Environment(AppModel.self) private var model
  let token: String

  @State private var data: SharedWishlist?
  @State private var notFound = false
  /// Owner-only: show the guest layout. Purchases stay hidden because the API omits them for owners.
  @State private var previewing = false
  @State private var sort: ItemSort = .newest
  @State private var appeared = ContinuousClock.now

  /// Known own lists open in the editor right away; the share-link lookup then runs in parallel.
  private var ownerID: String? {
    if let data { return data.isOwner ? data.wishlist.id : nil }
    return notFound ? nil : model.ownedWishlistID(token: token)
  }

  var body: some View {
    Group {
      if let ownerID, !previewing {
        OwnerWishlistView(id: ownerID, token: token, sort: $sort) {
          Task { await startPreview() }
        }
      } else {
        GuestWishlistView(
          token: token, data: $data, notFound: notFound, previewing: $previewing, sort: $sort, reload: load)
      }
    }
    // The token changes in place when the owner creates a new share link.
    .task(id: "\(token)|\(model.isLoggedIn)") {
      // Known own lists open in the editor, which loads its own data (and leaves when the list is gone);
      // the share-link lookup would only redraw it mid-transition. The guest preview loads it when needed.
      if data == nil, !notFound, model.ownedWishlistID(token: token) != nil { return }
      await load()
    }
    .userActivity(NSUserActivityTypeBrowsingWeb) { activity in
      // Handoff: continue on a Mac or iPad in the browser.
      activity.webpageURL = model.config.shareURL(token: token)
      activity.title = data?.wishlist.title
      activity.isEligibleForHandoff = true
    }
  }

  private func load() async {
    if data == nil { data = model.cachedShared(token: token) }
    do {
      let fresh = try await model.api.getShared(token: token)
      if data == nil { await PushTiming.waitForPushToFinish(since: appeared) }
      data = fresh
      notFound = false
      model.remember(fresh, token: token)
    } catch is CancellationError {
    } catch {
      data = nil
      notFound = true
      model.forget(token: token)
      model.show(error: error)
    }
  }

  /// The owner editor loads its own data, so refresh ours before showing wishes added meanwhile.
  private func startPreview() async {
    await load()
    if data?.isOwner == true {
      withAnimation { previewing = true }
    }
  }
}

struct GuestWishlistView: View {
  @Environment(AppModel.self) private var model
  @Environment(L10n.self) private var l10n
  @Environment(Router.self) private var router
  @Environment(\.imagePipeline) private var pipeline
  @Environment(\.displayScale) private var displayScale

  let token: String
  @Binding var data: SharedWishlist?
  let notFound: Bool
  @Binding var previewing: Bool
  @Binding var sort: ItemSort
  let reload: () async -> Void

  @State private var filter: ItemFilter = .all
  @State private var busyItem: String?
  @State private var followBusy = false
  @State private var buying: Item?
  @State private var undoing: (item: Item, purchase: Purchase)?
  @State private var undoName = ""
  @State private var loggingIn = false
  @State private var sorted = SortedItemsCache()

  /// Filtered and sorted only when the wishes, the filter or the sort order changed.
  private var visibleItems: [Item] {
    guard let data else { return [] }
    return sorted.items(
      data.items, filter: data.isOwner ? nil : filter, sort: sort, locale: l10n.locale, boughtLast: !data.isOwner)
  }

  var body: some View {
    let items = visibleItems
    ScrollView {
      LazyVStack(spacing: 16) {
        if let data {
          if data.isOwner { previewBanner }
          hero(data)
          controls(data)
          ForEach(items) { item in
            SharedItemCard(
              item: item,
              isOwner: data.isOwner,
              busy: busyItem == item.id,
              onBuy: { buying = item },
              onUndo: { purchase in
                undoName = model.buyerName
                undoing = (item, purchase)
              }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
          }
          if items.isEmpty {
            ContentUnavailableView(l10n.t(filter.emptyText), systemImage: filter == .open ? "party.popper" : "gift")
              .padding(.top, 24)
          }
        } else if notFound {
          ContentUnavailableView {
            Label(l10n.t(.sharedNotFoundTitle), systemImage: "link.badge.plus")
          } description: {
            Text(l10n.t(.sharedNotFoundText))
          }
          .padding(.top, 60)
        } else {
          ProgressView().padding(.top, 80)
        }
      }
      .padding(.horizontal)
      .padding(.bottom, 24)
      .frame(maxWidth: 720)
      .frame(maxWidth: .infinity)
      // No container-wide animation: it animated every card in while the screen was still being pushed.
      // Filter, sort, buying and undoing animate through their own transactions.
    }
    .onChange(of: items.prefix(8).map(\.id), initial: true) { prefetchImages() }
    .background(alignment: .top) { BrandBackdrop().frame(height: 320) }
    .background(Color(.systemGroupedBackground))
    .refreshable { await reload() }
    .softScrollEdges()
    .navigationTitle(data?.wishlist.title ?? l10n.t(.appTitle))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { toolbar }
    .sheet(item: $buying) { item in
      MarkBoughtSheet(item: item) { name, quantity in
        await markBought(item, name: name, quantity: quantity)
      }
    }
    .sheet(isPresented: $loggingIn) {
      NavigationStack {
        LoginView { loggingIn = false }
      }
      .toastHost()
    }
    .alert(
      l10n.t(.sharedUndoHeader),
      isPresented: Binding(get: { undoing != nil }, set: { if !$0 { undoing = nil } })
    ) {
      TextField(l10n.t(.commonYourName), text: $undoName)
        .textContentType(.name)
      Button(l10n.t(.commonCancel), role: .cancel) {}
      Button(l10n.t(.sharedUndo), role: .destructive) {
        if let undoing { Task { await undo(undoing.item, undoing.purchase) } }
      }
    } message: {
      if let undoing {
        Text(l10n.t(.sharedUndoMessage, ["name": undoing.purchase.buyerName, "count": String(undoing.purchase.quantity)]))
      }
    }
  }

  // MARK: Sections

  private var previewBanner: some View {
    HStack(spacing: 12) {
      Image(systemName: "eye")
        .font(.title3)
        .foregroundStyle(.tint)
      Text(l10n.t(.sharedPreviewHint))
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button(l10n.t(.sharedPreviewExit)) {
        withAnimation { previewing = false }
      }
      .prominentButtonStyle()
      .controlSize(.small)
      .accessibilityIdentifier("guest.exitPreview")
    }
    .padding(14)
    .glassSurface(in: .rect(cornerRadius: 22), tint: .accentColor)
  }

  private func hero(_ data: SharedWishlist) -> some View {
    VStack(spacing: 8) {
      Text(l10n.t(.sharedHeading, ["name": data.wishlist.ownerName]))
        .font(.title2.bold())
        .multilineTextAlignment(.center)
      if let date = data.wishlist.eventDate {
        Label(l10n.formatDate(date, style: .longDate), systemImage: "calendar")
          .font(.subheadline.weight(.semibold))
      }
      if let description = data.wishlist.description, !description.isEmpty {
        Text(description)
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      if !data.isOwner, model.isLoggedIn {
        let following = data.isFollowing == true
        Button {
          Task { await toggleFollow() }
        } label: {
          Label(
            l10n.t(following ? .sharedFollowing : .sharedFollow),
            systemImage: following ? "bookmark.fill" : "bookmark"
          )
          .contentTransition(.symbolEffect(.replace))
        }
        .modifier(FollowButtonStyle(following: following))
        .controlSize(.small)
        .disabled(followBusy)
        .accessibilityIdentifier("guest.follow")
        .sensoryFeedback(.success, trigger: following) { _, new in new }
        .padding(.top, 4)
        .accessibilityAddTraits(following ? .isSelected : [])
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
  }

  private func controls(_ data: SharedWishlist) -> some View {
    VStack(spacing: 10) {
      Picker(l10n.t(.sharedFilterAll), selection: $filter.animation()) {
        ForEach(ItemFilter.allCases) { Text(l10n.t($0.label)).tag($0) }
      }
      .filterPickerStyle()
      .labelsHidden()
      .accessibilityIdentifier("guest.filter")
      .disabled(data.isOwner)

      HStack {
        Spacer()
        SortMenu(sort: $sort)
      }
    }
  }

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    if data != nil {
      ToolbarItem(placement: .topBarTrailing) {
        ShareLink(item: model.config.shareURL(token: token)) {
          Label(l10n.t(.detailShare), systemImage: "square.and.arrow.up")
        }
      }
      .visibilityPriorityIfAvailable(high: false)
    }
    ToolbarItem(placement: .topBarTrailing) {
      if model.isLoggedIn {
        Button {
          router.popToRoot()
        } label: {
          Label(l10n.t(.wishlistsTitle), systemImage: "gift")
        }
        .accessibilityIdentifier("guest.home")
      } else {
        Button {
          loggingIn = true
        } label: {
          Label(l10n.t(.commonLogin), systemImage: "person.crop.circle")
        }
        .accessibilityIdentifier("guest.login")
      }
    }
    .visibilityPriorityIfAvailable(high: true)
  }

  // MARK: Actions

  /// Decodes the first pictures while the hero and controls are being shown.
  private func prefetchImages() {
    let urls = visibleItems.prefix(8).compactMap { model.config.assetURL($0.displayImageUrl) }
    pipeline.prefetch(urls, maxPixelSize: Int(ImageSize.card * displayScale))
  }

  private func toggleFollow() async {
    guard let current = data, !current.isOwner, !followBusy else { return }
    followBusy = true
    defer { followBusy = false }
    do {
      let state =
        current.isFollowing == true ? try await model.api.unfollow(token: token) : try await model.api.follow(token: token)
      withAnimation { data?.isFollowing = state.isFollowing }
      if state.isFollowing { model.show(success: l10n.t(.sharedFollowed)) }
    } catch {
      model.show(error: error)
    }
  }

  private func markBought(_ item: Item, name: String, quantity: Int) async {
    busyItem = item.id
    defer { busyItem = nil }
    do {
      let updated = try await model.api.markPurchased(token: token, itemID: item.id, name: name, quantity: quantity)
      model.rememberBuyerName(name)
      replace(updated)
      model.show(success: l10n.t(.sharedBuyThanks))
    } catch {
      model.show(error: error)
      await reload()
    }
  }

  private func undo(_ item: Item, _ purchase: Purchase) async {
    let name = undoName.trimmed
    guard !name.isEmpty else {
      model.show(errorMessage: l10n.t(.sharedUndoNameRequired))
      return
    }
    busyItem = item.id
    defer { busyItem = nil }
    do {
      model.rememberBuyerName(name)
      replace(try await model.api.revertPurchase(token: token, purchaseID: purchase.id, name: name))
    } catch {
      model.show(error: error)
      await reload()
    }
  }

  private func replace(_ updated: Item) {
    withAnimation {
      guard let index = data?.items.firstIndex(where: { $0.id == updated.id }) else { return }
      data?.items[index] = updated
    }
  }
}

private struct FollowButtonStyle: ViewModifier {
  let following: Bool

  func body(content: Content) -> some View {
    if following {
      content.secondaryButtonStyle()
    } else {
      content.prominentButtonStyle()
    }
  }
}

struct SortMenu: View {
  @Environment(L10n.self) private var l10n
  @Binding var sort: ItemSort

  var body: some View {
    Menu {
      Picker(l10n.t(.sharedSortLabel), selection: $sort.animation()) {
        ForEach(ItemSort.allCases) { Text(l10n.t($0.label)).tag($0) }
      }
    } label: {
      Label("\(l10n.t(.sharedSortLabel)): \(l10n.t(sort.label))", systemImage: "arrow.up.arrow.down")
        .font(.subheadline)
    }
    .menuActionDismissBehavior(.automatic)
    .accessibilityIdentifier("sort.menu")
  }
}

/// One wish as guests see it, with purchase status and history.
struct SharedItemCard: View {
  @Environment(AppModel.self) private var model
  @Environment(L10n.self) private var l10n
  let item: Item
  let isOwner: Bool
  let busy: Bool
  let onBuy: () -> Void
  let onUndo: (Purchase) -> Void

  @State private var showingHistory = false

  private var done: Bool { !isOwner && item.isFullyBought }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let url = model.config.assetURL(item.displayImageUrl) {
        RemoteImage(url: url, contentMode: .fit, maxPointSize: ImageSize.card)
          .frame(maxWidth: .infinity)
          .frame(height: 200)
          .padding(12)
          .background(Color.white)
          .clipped()
          .accessibilityHidden(true)
      }

      VStack(alignment: .leading, spacing: 10) {
        VStack(alignment: .leading, spacing: 4) {
          Text(item.title).font(.headline)
          PriorityStars(value: item.priority, showLabel: true)
        }

        if item.price != nil || item.quantity > 1 {
          HStack(spacing: 12) {
            if item.price != nil {
              Text(l10n.formatPrice(item.price, currency: item.currency)).font(.body.bold())
            }
            if item.quantity > 1 {
              Text(l10n.t(.sharedWanted, count: item.quantity)).foregroundStyle(.secondary)
            }
          }
          .font(.subheadline)
        }

        if let notes = item.notes, !notes.isEmpty {
          Text(notes)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        if !item.links.isEmpty {
          FlowLayout(spacing: 8) {
            ForEach(item.links, id: \.self) { link in
              if let url = URL(string: link) {
                Link(destination: url) {
                  Label(AppHostname.of(link), systemImage: "arrow.up.right.square")
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.tint.opacity(0.12), in: .capsule)
                }
              }
            }
          }
        }

        Divider().padding(.vertical, 2)
        statusRow

        if !isOwner, let purchases = item.purchases, !purchases.isEmpty {
          DisclosureGroup(isExpanded: $showingHistory.animation()) {
            VStack(alignment: .leading, spacing: 10) {
              ForEach(purchases) { purchase in
                historyEntry(purchase)
              }
            }
            .padding(.top, 8)
          } label: {
            // On the label only: on the group, iOS 27 passes it on to every entry and their undo buttons.
            Text(l10n.t(.sharedHistory, count: purchases.count))
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("history.\(item.title)")
          }
        }
      }
      .padding(16)
    }
    .cardBackground()
    .clipShape(.rect(cornerRadius: 24))
    .opacity(done ? 0.6 : 1)
  }

  @ViewBuilder
  private var statusRow: some View {
    HStack {
      if isOwner {
        Spacer()
        // Preview: the owner never receives purchase data, so only the guests' action is hinted at.
        Button {
        } label: {
          Label(l10n.t(.sharedIBoughtThis), systemImage: "cart")
        }
        .prominentButtonStyle()
        .controlSize(.small)
        .disabled(true)
      } else {
        badge
        Spacer()
        Button(action: onBuy) {
          ZStack {
            Label(l10n.t(.sharedIBoughtThis), systemImage: "cart").opacity(busy ? 0 : 1)
            if busy { ProgressView() }
          }
        }
        .prominentButtonStyle()
        .controlSize(.small)
        .disabled(item.remaining == 0 || busy)
        .accessibilityIdentifier("buy.\(item.title)")
      }
    }
  }

  private var badge: some View {
    let (text, color): (String, Color) =
      if item.remaining == 0 {
        (l10n.t(.sharedStatusBought), .green)
      } else if let bought = item.purchasedQuantity, bought > 0 {
        (l10n.t(.sharedStatusPartial, ["bought": String(bought), "total": String(item.quantity)]), .orange)
      } else {
        (l10n.t(.sharedStatusOpen), .secondary)
      }
    return Text(text)
      .font(.caption.weight(.semibold))
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .foregroundStyle(color)
      .background(color.opacity(0.15), in: .capsule)
      .accessibilityIdentifier("status.\(item.title)")
  }

  @ViewBuilder
  private func historyEntry(_ purchase: Purchase) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "cart").foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        (Text(purchase.buyerName).bold()
          + Text(purchase.isMine ? " \(l10n.t(.sharedYou))" : "").foregroundStyle(.tint)
          + Text(" \(l10n.t(.sharedMarkedBought, count: purchase.quantity))"))
          .strikethrough(purchase.revertedAt != nil)
        Text(l10n.formatDate(purchase.createdAt, style: .dateTime))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if purchase.revertedAt == nil {
        Button(l10n.t(.sharedUndo)) { onUndo(purchase) }
          .font(.footnote)
          .buttonStyle(.borderless)
          .foregroundStyle(.secondary)
          .disabled(busy)
          .accessibilityIdentifier("undo.\(purchase.buyerName)")
      }
    }
    .font(.subheadline)
    .foregroundStyle(purchase.revertedAt != nil ? .secondary : .primary)

    if let revertedAt = purchase.revertedAt {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: purchase.isSuspicious ? "exclamationmark.triangle.fill" : "arrow.uturn.backward")
          .foregroundStyle(purchase.isSuspicious ? .orange : .secondary)
        VStack(alignment: .leading, spacing: 2) {
          (Text(purchase.revertedByName ?? "").bold() + Text(" \(l10n.t(.sharedUndid))"))
          Text(l10n.formatDate(revertedAt, style: .dateTime))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .font(.subheadline)
      .padding(8)
      .background(purchase.isSuspicious ? Color.orange.opacity(0.12) : Color.clear, in: .rect(cornerRadius: 10))
    }
  }
}

struct MarkBoughtSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(L10n.self) private var l10n
  @Environment(\.dismiss) private var dismiss
  let item: Item
  let onConfirm: (String, Int) async -> Void

  @State private var name = ""
  @State private var quantity = 1
  @FocusState private var focused: Bool

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(l10n.t(.sharedBuyMessage)).foregroundStyle(.secondary)
          TextField(l10n.t(.commonYourName), text: $name)
            .textContentType(.name)
            .focused($focused)
            .submitLabel(.done)
            .onSubmit(confirm)
            .accessibilityIdentifier("buy.name")
            .onChange(of: name) { _, value in if value.count > 60 { name = String(value.prefix(60)) } }
        } header: {
          Text(item.title)
        }
        if item.remaining > 1 {
          Section {
            Stepper(value: $quantity, in: 1...item.remaining) {
              LabeledContent(l10n.t(.sharedBuyQuantity, count: item.remaining)) {
                Text("\(quantity)").monospacedDigit().contentTransition(.numericText())
              }
            }
            .accessibilityIdentifier("buy.quantity")
          }
        }
      }
      .navigationTitle(l10n.t(.sharedBuyHeader))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(l10n.t(.commonCancel), role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(l10n.t(.sharedBuyConfirm), action: confirm)
            .accessibilityIdentifier("buy.confirm")
        }
      }
      .onAppear {
        name = model.buyerName
        if name.isEmpty { focused = true }
      }
    }
    .presentationDetents([.medium, .large])
    .toastHost()
  }

  private func confirm() {
    let name = name.trimmed
    guard !name.isEmpty else {
      model.show(errorMessage: l10n.t(.sharedBuyNameRequired))
      return
    }
    let quantity = min(item.remaining, max(1, quantity))
    dismiss()
    Task { await onConfirm(name, quantity) }
  }
}
