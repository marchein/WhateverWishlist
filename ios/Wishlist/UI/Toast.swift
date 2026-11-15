import SwiftUI

/// Shows the model's current toast at the bottom. Applied to the root and to every sheet, because sheets
/// cover whatever is underneath them.
struct ToastHost: ViewModifier {
  @Environment(AppModel.self) private var model

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .bottom) {
        if let toast = model.toast {
          ToastView(toast: toast)
            .id(toast.id)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onTapGesture { model.toast = nil }
        }
      }
      .animation(.spring(duration: 0.35), value: model.toast)
      .sensoryFeedback(trigger: model.toast) { _, toast in
        switch toast?.kind {
        case .success: .success
        case .error: .error
        case nil: nil
        }
      }
  }
}

private struct ToastView: View {
  let toast: Toast

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Image(systemName: toast.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        .foregroundStyle(toast.kind == .success ? .green : .red)
        .symbolEffect(.bounce, value: toast.id)
      Text(toast.message)
        .font(.subheadline.weight(.medium))
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
    .frame(maxWidth: 520)
    .glassSurface(in: .capsule, tint: toast.kind == .success ? .green : .red)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isStaticText)
    .accessibilityIdentifier("toast")
  }
}

extension View {
  func toastHost() -> some View {
    modifier(ToastHost())
  }
}
