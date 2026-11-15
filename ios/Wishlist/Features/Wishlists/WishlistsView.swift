import SwiftUI

struct WishlistsView: View {
  @Environment(AppModel.self) private var model
  @Environment(L10n.self) private var l10n
  @Environment(Router.self) private var router

  @State private var wishlists: [Wishlist] = []
  @State private var followed: [FollowedWishlist] = []
  @State private var loading = true
  @State private var creating = false
  @State private var openingLink = false
  @State private var confirmingLogout = false

  private var greeting: String { l10n.t(.wishlistsGreeting, ["name": model.user?.displayName ?? ""]) }

  var body: some View {
    Group {
      if loading && wishlists.isEmpty && followed.isEmpty {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if wishlists.isEmpty && followed.isEmpty {
        empty
      } else {
        list
      }
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle(l10n.t(.appTitle))
    .navigationSubtitleIfAvailable(greeting)
    .toolbar { toolbar }
    .task { await load() }
    .sheet(isPresented: $creating) {
      CreateWishlistSheet { wishlist in
        wishlists.insert(wishlist, at: 0)
        router.show(token: wishlist.shareToken)
      }
    }
    .sheet(isPresented: $openingLink) {
      OpenLinkSheet()
    }
    .confirmationDialog(l10n.t(.commonLogout), isPresented: $confirmingLogout, titleVisibility: .hidden) {
      Button(l10n.t(.commonLogout), role: .destructive) { model.logout() }
    }
  }

  // MARK: Content

  private var list: some View {
    List {
      if #unavailable(iOS 26.0) {
        Text(greeting)
          .font(.title3.weight(.semibold))
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
      }

      Section {
        if wishlists.isEmpty {
          Button {
            creating = true
          } label: {
            Label(l10n.t(.wishlistsCreateFirst), systemImage: "plus.circle.fill")
          }
        }
        ForEach(wishlists) { wishlist in
          NavigationLink(value: Route.wishlist(token: wishlist.shareToken)) {
            row(
              title: wishlist.title,
              subtitle: [
                l10n.t(.wishlistsWishCount, count: wishlist.itemCount ?? 0),
                l10n.formatDate(wishlist.eventDate),
              ]
            ) {
              Tile { Image(systemName: "gift.fill").font(.title3) }
            }
          }
          .contextMenu {
            ShareLink(item: model.config.shareURL(token: wishlist.shareToken)) {
              Label(l10n.t(.detailShare), systemImage: "square.and.arrow.up")
            }
            Button {
              UIPasteboard.general.url = model.config.shareURL(token: wishlist.shareToken)
              model.show(success: l10n.t(.detailLinkCopied))
            } label: {
              Label(l10n.t(.detailCopyLink), systemImage: "doc.on.doc")
            }
          }
        }
      } header: {
        sectionHeader(l10n.t(.wishlistsTitle), count: wishlists.count)
      }

      Section {
        if followed.isEmpty {
          Label(l10n.t(.wishlistsFollowedEmpty), systemImage: "bookmark")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        ForEach(followed) { wishlist in
          NavigationLink(value: Route.wishlist(token: wishlist.shareToken)) {
            row(
              title: wishlist.title,
              subtitle: [
                l10n.t(.wishlistsOwnerName, ["name": wishlist.ownerName]),
                l10n.t(.wishlistsWishCount, count: wishlist.itemCount ?? 0),
                l10n.formatDate(wishlist.eventDate),
              ]
            ) {
              Tile(tint: .orange) {
                Text(wishlist.ownerName.prefix(1).uppercased()).font(.title3.bold())
              }
            }
          }
          .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
              Task { await unfollow(wishlist) }
            } label: {
              Label(l10n.t(.wishlistsUnfollow), systemImage: "bookmark.slash")
            }
          }
          .contextMenu {
            Button(role: .destructive) {
              Task { await unfollow(wishlist) }
            } label: {
              Label(l10n.t(.wishlistsUnfollow), systemImage: "bookmark.slash")
            }
          }
        }
      } header: {
        sectionHeader(l10n.t(.wishlistsFollowed), count: followed.count)
      }
    }
    .refreshable { await load() }
    .softScrollEdges()
    .animation(.default, value: wishlists)
    .animation(.default, value: followed)
  }

  private var empty: some View {
    ScrollView {
      VStack(spacing: 24) {
        ContentUnavailableView {
          Label(greeting, systemImage: "gift")
            .symbolEffect(.bounce, options: .nonRepeating)
        } description: {
          Text(l10n.t(.wishlistsEmptyText))
        } actions: {
          Button {
            creating = true
          } label: {
            Label(l10n.t(.wishlistsCreateFirst), systemImage: "plus").padding(.vertical, 4)
          }
          .prominentButtonStyle()
          Button {
            openingLink = true
          } label: {
            Label(l10n.t(.openLinkTitle), systemImage: "link")
          }
        }
        .padding(.top, 60)
      }
    }
    .refreshable { await load() }
  }

  private func row(title: String, subtitle: [String], @ViewBuilder tile: () -> some View) -> some View {
    HStack(spacing: 14) {
      tile()
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.headline).lineLimit(2)
        Text(subtitle.filter { !$0.isEmpty }.joined(separator: " · "))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }

  private func sectionHeader(_ title: String, count: Int) -> some View {
    HStack {
      Text(title)
      if count > 0 {
        Text("\(count)")
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(.quaternary, in: .capsule)
      }
    }
  }

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      Menu {
        if let user = model.user {
          Section(user.email) {
            Text(user.displayName)
          }
        }
        Button {
          openingLink = true
        } label: {
          Label(l10n.t(.openLinkTitle), systemImage: "link")
        }
        NavigationLink(value: Route.status) {
          Label(l10n.t(.statusTitle), systemImage: "info.circle")
        }
        Divider()
        Button(role: .destructive) {
          confirmingLogout = true
        } label: {
          Label(l10n.t(.commonLogout), systemImage: "rectangle.portrait.and.arrow.right")
        }
        .accessibilityIdentifier("wishlists.logout")
      } label: {
        Label(l10n.t(.account), systemImage: "person.crop.circle")
      }
      .accessibilityIdentifier("wishlists.account")
    }
    .visibilityPriorityIfAvailable(high: false)

    ToolbarItem(placement: .primaryAction) {
      Button {
        creating = true
      } label: {
        Label(l10n.t(.wishlistsNew), systemImage: "plus")
      }
      .accessibilityIdentifier("wishlists.add")
    }
    .visibilityPriorityIfAvailable(high: true)
  }

  // MARK: Actions

  private func load() async {
    do {
      async let own = model.api.listWishlists()
      async let others = model.api.listFollowedWishlists()
      let (ownLists, otherLists) = try await (own, others)
      wishlists = ownLists
      followed = otherLists
      model.remember(ownLists: ownLists)
    } catch {
      model.show(error: error)
    }
    loading = false
    model.isFirstScreenReady = true
  }

  private func unfollow(_ wishlist: FollowedWishlist) async {
    do {
      _ = try await model.api.unfollow(token: wishlist.shareToken)
      followed.removeAll { $0.id == wishlist.id }
      model.show(success: l10n.t(.wishlistsUnfollowed, ["title": wishlist.title]))
    } catch {
      model.show(error: error)
    }
  }
}

struct CreateWishlistSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(L10n.self) private var l10n
  @Environment(\.dismiss) private var dismiss
  let onCreated: (Wishlist) -> Void

  @State private var title = ""
  @State private var hasDate = false
  @State private var date = Date()
  @State private var saving = false
  @FocusState private var focused: Bool

  private var valid: Bool { !title.trimmed.isEmpty && title.trimmed.count <= 120 }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField(l10n.t(.wishlistsTitlePlaceholder), text: $title)
            .focused($focused)
            .submitLabel(.done)
            .accessibilityIdentifier("createWishlist.title")
            .onSubmit { Task { await submit() } }
            .onChange(of: title) { _, value in if value.count > 120 { title = String(value.prefix(120)) } }
        } header: {
          Text(l10n.t(.detailEditTitle))
        } footer: {
          Text(l10n.t(.wishlistsCreateHint))
        }
        Section {
          Toggle(l10n.t(.wishlistsDateOptional), isOn: $hasDate.animation())
          if hasDate {
            DatePicker(l10n.t(.wishlistsDateOptional), selection: $date, displayedComponents: .date)
              .datePickerStyle(.graphical)
              .labelsHidden()
          }
        }
      }
      .disabled(saving)
      .navigationTitle(l10n.t(.wishlistsNew))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(l10n.t(.commonCancel), role: .cancel) { dismiss() }.disabled(saving)
        }
        ToolbarItem(placement: .confirmationAction) {
          if saving {
            ProgressView()
          } else {
            Button(l10n.t(.wishlistsCreate)) { Task { await submit() } }
              .disabled(!valid)
              .accessibilityIdentifier("createWishlist.create")
          }
        }
      }
      .onAppear { focused = true }
    }
    .presentationDetents(hasDate ? [.large] : [.medium, .large])
    .interactiveDismissDisabled(saving)
    .toastHost()
  }

  private func submit() async {
    guard !saving else { return }
    guard valid else {
      model.show(errorMessage: l10n.t(.wishlistsTitleRequired))
      return
    }
    saving = true
    defer { saving = false }
    do {
      let wishlist = try await model.api.createWishlist(
        WishlistInput(title: title.trimmed, description: nil, eventDate: hasDate ? L10n.dateOnlyString(date) : nil))
      dismiss()
      onCreated(wishlist)
    } catch {
      model.show(error: error)
    }
  }
}
