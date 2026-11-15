import SwiftUI

/// Continues the launch screen (Info.plist → UILaunchScreen: LaunchBackground + LaunchLogo) inside the app:
/// it looks exactly the same, stays until the first screen has its content (at most `maxDuration`), then
/// lifts away. Without it the purple launch screen would cut straight to a loading spinner.
struct SplashOverlay: View {
  /// True once the first screen can be shown without a spinner.
  let isContentReady: Bool
  var maxDuration: Duration = .seconds(1.5)

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var timedOut = false
  @State private var leaving = false
  @State private var gone = false

  var body: some View {
    if !gone {
      ZStack {
        Color("LaunchBackground")
        // Same asset and size as the launch screen, centred on the whole screen like there.
        Image("LaunchLogo")
          .scaleEffect(leaving && !reduceMotion ? 1.35 : 1)
      }
      .ignoresSafeArea()
      .opacity(leaving ? 0 : 1)
      .allowsHitTesting(!leaving)
      .accessibilityHidden(true)
      .task {
        try? await Task.sleep(for: maxDuration)
        timedOut = true
      }
      .onChange(of: isContentReady || timedOut, initial: true) { _, ready in
        guard ready, !leaving else { return }
        withAnimation(.easeIn(duration: 0.35)) {
          leaving = true
        } completion: {
          gone = true
        }
      }
    }
  }
}
