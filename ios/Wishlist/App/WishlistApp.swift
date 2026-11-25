import SwiftUI

@main
struct WishlistApp: App {
  @State private var l10n: L10n
  @State private var model: AppModel
  private let imagePipeline: ImagePipeline

  init() {
    // Downloaded pictures are kept on disk here; decoded ones in ImagePipeline's memory cache.
    URLCache.shared = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
    let l10n = L10n()
    _l10n = State(initialValue: l10n)
    #if DEBUG
      if let testing = UITestEnvironment.current {
        let model = AppModel(
          config: testing.config, l10n: l10n, session: testing.session, defaults: testing.defaults,
          tokenStore: MemoryTokenStore())
        if let login = testing.login { model.setSession(login) }
        model.cachesLists = ProcessInfo.processInfo.environment["UITEST_LIST_CACHE"] != "0"
        _model = State(initialValue: model)
        imagePipeline = ImagePipeline(session: testing.session)
        return
      }
    #endif
    _model = State(initialValue: AppModel(l10n: l10n))
    imagePipeline = .shared
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(model)
        .environment(l10n)
        .environment(\.locale, l10n.locale)
        .environment(\.imagePipeline, imagePipeline)
        .task { await model.refreshUser() }
    }
  }
}

struct RootView: View {
  @Environment(AppModel.self) private var model
  @State private var router = Router()

  /// UI tests start straight into the app.
  private static var showsSplash: Bool {
    #if DEBUG
      UITestEnvironment.current == nil
    #else
      true
    #endif
  }

  var body: some View {
    NavigationStack(path: $router.path) {
      Group {
        if model.isLoggedIn {
          WishlistsView()
        } else {
          LoginView()
        }
      }
      .navigationDestination(for: Route.self) { route in
        switch route {
        case .wishlist(let token):
          // A regular push: measured on an iPhone, the zoom from a list row always dropped a frame.
          SharedWishlistView(token: token)
        case .status:
          StatusView()
            .crossFadeTransitionIfAvailable()
        }
      }
    }
    .environment(router)
    .toastHost()
    .overlay {
      if Self.showsSplash {
        // The login screen has nothing to load; the start page waits for its lists.
        SplashOverlay(isContentReady: !model.isLoggedIn || model.isFirstScreenReady)
      }
    }
    .environment(\.openURL, OpenURLAction { url in
      if url.host() == model.config.webURL.host() || url.scheme == model.config.urlScheme,
        let destination = DeepLink.destination(from: url, scheme: model.config.urlScheme)
      {
        router.open(destination)
        return .handled
      }
      // Shop links open in an in-app browser on iOS 26, so returning to the list is one swipe away.
      if #available(iOS 26.0, *) {
        return .systemAction(prefersInApp: true)
      }
      return .systemAction
    })
    .onOpenURL { url in
      if let destination = DeepLink.destination(from: url, scheme: model.config.urlScheme) {
        router.open(destination)
      }
    }
    // Universal Links and Handoff from Safari (the domains come from the apple-app-site-association file).
    .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
      if let url = activity.webpageURL, let destination = DeepLink.destination(from: url, scheme: model.config.urlScheme) {
        router.open(destination)
      }
    }
    .onChange(of: model.isLoggedIn) { _, loggedIn in
      // Logging out (or an expired session) starts over; a fresh login keeps a list opened as guest.
      if !loggedIn { router.popToRoot() }
    }
  }
}
