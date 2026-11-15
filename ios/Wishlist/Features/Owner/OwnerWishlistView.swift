import SwiftUI

/// The owner's view of one wishlist. Intentionally shows nothing about purchases.
struct OwnerWishlistView: View {
  @Environment(AppModel.self) private var model
  @Environment(L10n.self) private var l10n
  @Environment(Router.self) private var router

  @Environment(\.imagePipeline) private var pipeline
  @Environment(\.displayScale) private var displayScale

  let id: String
  let token: String
  /// Shared with the guest preview so both views list wishes in the same order.
  @Binding var sort: ItemSort
  let onPreview: () -> Void

  @State private var wishlist: WishlistWithItems?
  @State private var editing: EditorTarget?
  @State private var editingDetails = false
  @State private var showingFollowers = false
  @State private var regenerating = false
  @State private var confirmingDelete = false
  @State private var deletingItem: Item?
  @Namespace private var zoom

  @State private var sorted = SortedItemsCache()
  @State private var appeared = ContinuousClock.now

  /// The route's token is always the current one: after a new link was created the screen is kept and
  /// only its token changes, while `wishlist` still holds the old link until it reloads.
  private var shareURL: URL { model.config.shareURL(token: token) }
  /// Sorted only when the wishes or the sort order changed, not on every redraw.
  private var sortedItems: [Item] {
    wishlist.map { sorted.items($0.items, sort: sort, locale: l10n.locale, boughtLast: false) } ?? []
  }

  var body: some View {
    Group {
      if let wishlist {
        content(wishlist)
      } else {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle(wishlist?.title ?? "")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { toolbar }
    .task { await load() }
    .sheet(item: $editing) { target in
      ItemEditorView(wishlistID: id, item: target.item) {
        Task { await load() }
      }
      .zoomTransition(id: target.id, in: zoom)
    }
    .sheet(isPresented: $editingDetails) {
      if let wishlist {
        EditWishlistSheet(wishlist: wishlist) { updated in
          self.wishlist?.title = updated.title
          self.wishlist?.description = updated.description
          self.wishlist?.eventDate = updated.eventDate
        }
      }
    }
    .sheet(isPresented: $showingFollowers) {
      FollowersSheet(wishlistID: id) { count in
        wishlist?.followerCount = count
      }
    }
    .sheet(isPresented: $regenerating) {
      RegenerateLinkSheet(wishlistID: id, followerCount: wishlist?.followerCount ?? 0) { updated in
        wishlist?.shareToken = updated.shareToken
        model.forget(token: token)
        model.remember(ownLists: [updated])
        router.replace(token: token, with: updated.shareToken)
        model.show(success: l10n.t(.detailRegenerateDone))
      }
    }
    .confirmationDialog(l10n.t(.detailDeleteHeader), isPresented: $confirmingDelete, titleVisibility: .visible) {
      Button(l10n.t(.commonDelete), role: .destructive) { Task { await deleteList() } }
    } message: {
      Text(l10n.t(.detailDeleteMessage))
    }
    .alert(
      l10n.t(.editorDeleteHeader),
      isPresented: Binding(get: { deletingItem != nil }, set: { if !$0 { deletingItem = nil } }),
      presenting: deletingItem
    ) { item in
      Button(l10n.t(.commonCancel), role: .cancel) {}
      Button(l10n.t(.commonDelete), role: .destructive) { Task { await delete(item) } }
    } message: { _ in
      Text(l10n.t(.editorDeleteMessage))
    }
  }

  private func content(_ wishlist: WishlistWithItems) -> some View {
    let items = sortedItems
    return List {
      Section {
        VStack(alignment: .leading, spacing: 8) {
          Text(wishlist.title).font(.largeTitle.bold())
          if let date = wishlist.eventDate {
            Label(l10n.formatDate(date, style: .longDate), systemImage: "calendar")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.tint)
          }
          if let description = wishlist.description, !description.isEmpty {
            Text(description).foregroundStyle(.secondary)
          }
          Label(l10n.t(.detailOwnerHint), systemImage: "eye.slash")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
      }

      Section {
        Text(shareURL.absoluteString)
          .font(.callout.monospaced())
          .accessibilityIdentifier("owner.shareURL")
          .textSelection(.enabled)
          .lineLimit(2)
        GlassGroup {
          HStack(spacing: 10) {
            Button(action: copyLink) {
              Label(l10n.t(.detailCopyLink), systemImage: "doc.on.doc")
                .frame(maxWidth: .infinity)
            }
            .secondaryButtonStyle()
            .accessibilityIdentifier("owner.copyLink")
            ShareLink(
              item: shareURL,
              message: Text(l10n.t(.detailShareText, ["title": wishlist.title])),
              preview: SharePreview(wishlist.title, image: Image("BrandIcon"))
            ) {
              Label(l10n.t(.detailShare), systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
            }
            .prominentButtonStyle()
          }
          .labelStyle(.titleAndIcon)
          .lineLimit(1)
          .buttonStyle(.borderless)
        }
        .listRowSeparator(.hidden)
        if let count = wishlist.followerCount, count > 0 {
          Button {
            showingFollowers = true
          } label: {
            Label(l10n.t(.detailFollowersCount, count: count), systemImage: "person.2")
          }
          .accessibilityIdentifier("owner.followers")
        }
      } header: {
        Text(l10n.t(.detailPublicLink))
      } footer: {
        Text(l10n.t(.detailShareHint))
      }

      Section {
        if wishlist.items.isEmpty {
          Button {
            editing = EditorTarget(item: nil)
          } label: {
            HStack(spacing: 14) {
              Tile(size: 48) { Image(systemName: "sparkles").font(.title2) }
              VStack(alignment: .leading, spacing: 2) {
                Text(l10n.t(.detailAddFirst)).font(.headline)
                Text(l10n.t(.detailEmptyText)).font(.subheadline).foregroundStyle(.secondary)
              }
            }
            .padding(.vertical, 6)
          }
          .foregroundStyle(.primary)
          .matchedTransitionSource(id: EditorTarget.newID, in: zoom)
          .accessibilityIdentifier("owner.addFirst")
        }
        ForEach(items) { item in
          Button {
            editing = EditorTarget(item: item)
          } label: {
            OwnerItemRow(item: item)
          }
          .foregroundStyle(.primary)
          .matchedTransitionSource(id: item.id, in: zoom)
          .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
              deletingItem = item
            } label: {
              Label(l10n.t(.commonDelete), systemImage: "trash")
            }
            Button {
              editing = EditorTarget(item: item)
            } label: {
              Label(l10n.t(.editWish), systemImage: "pencil")
            }
            .tint(.accentColor)
          }
          .contextMenu {
            Button {
              editing = EditorTarget(item: item)
            } label: {
              Label(l10n.t(.editorEditTitle), systemImage: "pencil")
            }
            ForEach(item.links, id: \.self) { link in
              if let url = URL(string: link) {
                Link(destination: url) {
                  Label(AppHostname.of(link), systemImage: "safari")
                }
              }
            }
            Divider()
            Button(role: .destructive) {
              deletingItem = item
            } label: {
              Label(l10n.t(.editorDeleteWish), systemImage: "trash")
            }
          }
        }
      } header: {
        HStack {
          Text(l10n.t(.detailWishes))
          if !wishlist.items.isEmpty {
            Text("\(wishlist.items.count)")
              .font(.caption.weight(.semibold))
              .padding(.horizontal, 8)
              .padding(.vertical, 2)
              .background(.quaternary, in: .capsule)
            Spacer()
            SortMenu(sort: $sort).textCase(nil)
          }
        }
      }
    }
    .refreshable { await load() }
    .softScrollEdges()
  }

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      Button(action: onPreview) {
        Label(l10n.t(.detailMenuPreview), systemImage: "eye")
      }
      .disabled(wishlist == nil)
      .accessibilityIdentifier("owner.preview")
    }
    .visibilityPriorityIfAvailable(high: false)

    ToolbarItem(placement: .topBarTrailing) {
      Menu {
        Button(action: copyLink) {
          Label(l10n.t(.detailCopyLink), systemImage: "doc.on.doc")
        }
        Button {
          editingDetails = true
        } label: {
          Label(l10n.t(.detailMenuEdit), systemImage: "square.and.pencil")
        }
        Button(action: onPreview) {
          Label(l10n.t(.detailMenuPreview), systemImage: "eye")
        }
        Button {
          showingFollowers = true
        } label: {
          Label(l10n.t(.detailMenuFollowers, count: wishlist?.followerCount ?? 0), systemImage: "person.2")
        }
        Button {
          regenerating = true
        } label: {
          Label(l10n.t(.detailMenuRegenerate), systemImage: "arrow.clockwise")
        }
        Divider()
        Button(role: .destructive) {
          confirmingDelete = true
        } label: {
          Label(l10n.t(.detailMenuDelete), systemImage: "trash")
        }
      } label: {
        Label(l10n.t(.detailMore), systemImage: "ellipsis")
      }
      .disabled(wishlist == nil)
      .accessibilityIdentifier("owner.more")
    }
    .visibilityPriorityIfAvailable(high: true)

    ToolbarItem(placement: .bottomBar) {
      Button {
        editing = EditorTarget(item: nil)
      } label: {
        Label(l10n.t(.detailAddWish), systemImage: "plus")
          .labelStyle(.titleAndIcon)
          .padding(.horizontal, 6)
      }
      .prominentButtonStyle()
      .matchedTransitionSource(id: EditorTarget.newID, in: zoom)
      .disabled(wishlist == nil)
      .accessibilityIdentifier("owner.addWish")
    }
  }

  // MARK: Actions

  private func load() async {
    if wishlist == nil { wishlist = model.cachedOwned(id: id) }
    do {
      let fresh = try await model.api.getWishlist(id: id)
      // Changes to a list already on screen (a wish added in the editor) animate; the first fill doesn't,
      // so opening the list isn't slowed down by inserting every row while the screen is pushed.
      if wishlist == nil {
        await PushTiming.waitForPushToFinish(since: appeared)
        wishlist = fresh
      } else if wishlist != fresh {
        withAnimation { wishlist = fresh }
      }
      model.remember(fresh)
      let urls = fresh.items.compactMap { model.config.assetURL($0.displayImageUrl) }
      pipeline.prefetch(urls, maxPixelSize: Int(ImageSize.thumbnail * displayScale))
    } catch is CancellationError {
    } catch {
      model.show(error: error)
      router.popToRoot()
    }
  }

  private func copyLink() {
    UIPasteboard.general.url = shareURL
    model.show(success: l10n.t(.detailLinkCopied))
  }

  private func delete(_ item: Item) async {
    do {
      try await model.api.deleteItem(wishlistID: id, itemID: item.id)
      withAnimation { wishlist?.items.removeAll { $0.id == item.id } }
    } catch {
      model.show(error: error)
    }
  }

  private func deleteList() async {
    do {
      try await model.api.deleteWishlist(id: id)
      router.popToRoot()
    } catch {
      model.show(error: error)
    }
  }
}

struct EditorTarget: Identifiable {
  static let newID = "new-wish"
  let item: Item?
  var id: String { item?.id ?? Self.newID }
}

private struct OwnerItemRow: View {
  @Environment(AppModel.self) private var model
  @Environment(L10n.self) private var l10n
  let item: Item

  private var meta: String {
    var parts: [String] = []
    if item.price != nil { parts.append(l10n.formatPrice(item.price, currency: item.currency)) }
    if item.quantity > 1 { parts.append("\(item.quantity)×") }
    if !item.links.isEmpty { parts.append(l10n.t(.detailLinkCount, count: item.links.count)) }
    return parts.joined(separator: " · ")
  }

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Group {
        if let url = model.config.assetURL(item.displayImageUrl) {
          RemoteImage(url: url, contentMode: .fit, maxPointSize: ImageSize.thumbnail)
            .padding(4)
            .background(Color.white)
        } else {
          Image(systemName: "gift").font(.title3)
        }
      }
      .frame(width: 60, height: 60)
      .background(Color.accentColor.opacity(0.12))
      .clipShape(.rect(cornerRadius: 14))
      .foregroundStyle(.tint)
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(item.title).font(.headline).lineLimit(2)
        PriorityStars(value: item.priority)
        if let notes = item.notes, !notes.isEmpty {
          Text(notes).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
        }
        if !meta.isEmpty {
          Text(meta).font(.subheadline).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
      Image(systemName: "pencil")
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }
    .padding(.vertical, 4)
    .contentShape(.rect)
  }
}

struct EditWishlistSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(L10n.self) private var l10n
  @Environment(\.dismiss) private var dismiss
  let wishlist: WishlistWithItems
  let onSaved: (Wishlist) -> Void

  @State private var title = ""
  @State private var description = ""
  @State private var hasDate = false
  @State private var date = Date()
  @State private var saving = false

  var body: some View {
    NavigationStack {
      Form {
        Section(l10n.t(.detailEditTitle)) {
          TextField(l10n.t(.detailEditTitle), text: $title)
            .accessibilityIdentifier("editWishlist.title")
            .onChange(of: title) { _, value in if value.count > 120 { title = String(value.prefix(120)) } }
        }
        Section(l10n.t(.detailEditDescription)) {
          TextField(l10n.t(.detailEditDescription), text: $description, axis: .vertical)
            .accessibilityIdentifier("editWishlist.description")
            .lineLimit(3...8)
            .onChange(of: description) { _, value in
              if value.count > 1000 { description = String(value.prefix(1000)) }
            }
        }
        Section {
          Toggle(l10n.t(.wishlistsDateOptional), isOn: $hasDate.animation())
          if hasDate {
            DatePicker(l10n.t(.wishlistsDateOptional), selection: $date, displayedComponents: .date)
          }
        }
      }
      .disabled(saving)
      .navigationTitle(l10n.t(.detailEditHeader))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(l10n.t(.commonCancel), role: .cancel) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          if saving {
            ProgressView()
          } else {
            Button(l10n.t(.commonSave)) { Task { await save() } }
              .disabled(title.trimmed.isEmpty)
              .accessibilityIdentifier("editWishlist.save")
          }
        }
      }
    }
    .onAppear {
      title = wishlist.title
      description = wishlist.description ?? ""
      if let eventDate = wishlist.eventDate, let parsed = L10n.parseDate(eventDate) {
        hasDate = true
        date = parsed
      }
    }
    .interactiveDismissDisabled(saving)
    .toastHost()
  }

  private func save() async {
    guard !title.trimmed.isEmpty else { return }
    saving = true
    defer { saving = false }
    do {
      let updated = try await model.api.updateWishlist(
        id: wishlist.id,
        WishlistInput(
          title: title.trimmed,
          description: description.trimmed.isEmpty ? nil : description.trimmed,
          eventDate: hasDate ? L10n.dateOnlyString(date) : nil))
      onSaved(updated)
      dismiss()
    } catch {
      model.show(error: error)
    }
  }
}

struct FollowersSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(L10n.self) private var l10n
  @Environment(\.dismiss) private var dismiss
  let wishlistID: String
  let onCountChange: (Int) -> Void

  /// nil while loading.
  @State private var followers: [Follower]?
  @State private var removing: Follower?

  var body: some View {
    NavigationStack {
      List {
        Section {
          if let followers {
            if followers.isEmpty {
              Text(l10n.t(.detailFollowersEmpty))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            }
            ForEach(followers) { follower in
              HStack(spacing: 12) {
                Tile(size: 36, tint: .orange) {
                  Text(follower.displayName.prefix(1).uppercased()).font(.headline)
                }
                VStack(alignment: .leading) {
                  Text(follower.displayName).font(.headline)
                  Text(l10n.t(.detailFollowersSince, ["date": l10n.formatDate(follower.followedAt)]))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                  removing = follower
                } label: {
                  Image(systemName: "person.badge.minus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .accessibilityLabel("\(l10n.t(.detailFollowersRemove)): \(follower.displayName)")
                .accessibilityIdentifier("follower.remove.\(follower.displayName)")
              }
              .swipeActions {
                Button(role: .destructive) {
                  removing = follower
                } label: {
                  Label(l10n.t(.detailFollowersRemove), systemImage: "person.badge.minus")
                }
              }
            }
          } else {
            ProgressView().frame(maxWidth: .infinity)
          }
        } footer: {
          Text(l10n.t(.detailFollowersHint))
        }
      }
      .navigationTitle(l10n.t(.detailFollowersTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          CloseButton { dismiss() }
        }
      }
      .alert(
        l10n.t(.detailFollowersRemoveHeader, ["name": removing?.displayName ?? ""]),
        isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
        presenting: removing
      ) { follower in
        Button(l10n.t(.commonCancel), role: .cancel) {}
        Button(l10n.t(.detailFollowersRemove), role: .destructive) { Task { await remove(follower) } }
      } message: { _ in
        Text(l10n.t(.detailFollowersRemoveMessage))
      }
      .task { await load() }
    }
    .presentationDetents([.medium, .large])
    .toastHost()
  }

  private func load() async {
    do {
      followers = try await model.api.listFollowers(id: wishlistID)
      onCountChange(followers?.count ?? 0)
    } catch is CancellationError {
    } catch {
      model.show(error: error)
      dismiss()
    }
  }

  private func remove(_ follower: Follower) async {
    do {
      try await model.api.removeFollower(wishlistID: wishlistID, userID: follower.userId)
      withAnimation { followers?.removeAll { $0.userId == follower.userId } }
      onCountChange(followers?.count ?? 0)
    } catch {
      model.show(error: error)
    }
  }
}

struct RegenerateLinkSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(L10n.self) private var l10n
  @Environment(\.dismiss) private var dismiss
  let wishlistID: String
  let followerCount: Int
  let onDone: (Wishlist) -> Void

  /// Followers are kept unless the owner switches the toggle off.
  @State private var keepFollowers = true
  @State private var busy = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(l10n.t(.detailRegenerateMessage))
        }
        Section {
          Toggle(isOn: $keepFollowers.animation()) {
            VStack(alignment: .leading) {
              Text(l10n.t(.detailRegenerateKeepFollowers))
              if followerCount > 0 {
                Text(l10n.t(.detailFollowersCount, count: followerCount))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
          .accessibilityIdentifier("regenerate.keepFollowers")
        } footer: {
          Label(
            l10n.t(keepFollowers ? .detailRegenerateKeepHint : .detailRegenerateRemoveHint),
            systemImage: keepFollowers ? "info.circle" : "exclamationmark.triangle"
          )
          .foregroundStyle(keepFollowers ? Color.secondary : Color.orange)
          .contentTransition(.opacity)
        }
      }
      .disabled(busy)
      .navigationTitle(l10n.t(.detailRegenerateHeader))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(l10n.t(.commonCancel), role: .cancel) { dismiss() }.disabled(busy)
        }
        ToolbarItem(placement: .confirmationAction) {
          if busy {
            ProgressView()
          } else {
            Button(l10n.t(.detailRegenerateConfirm)) { Task { await confirm() } }
              .accessibilityIdentifier("regenerate.confirm")
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .interactiveDismissDisabled(busy)
    .toastHost()
  }

  private func confirm() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      let wishlist = try await model.api.regenerateShareToken(id: wishlistID, keepFollowers: keepFollowers)
      dismiss()
      onDone(wishlist)
    } catch {
      model.show(error: error)
    }
  }
}
