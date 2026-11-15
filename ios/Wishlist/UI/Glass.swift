import SwiftUI

// Liquid Glass on iOS 26+, materials and classic button styles on iOS 18–25.

extension View {
  /// Floating surface (toasts, banners, panels).
  @ViewBuilder
  func glassSurface<S: InsettableShape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
    if #available(iOS 26.0, *) {
      glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
    } else {
      background {
        shape.fill(.regularMaterial)
        if let tint { shape.fill(tint.opacity(0.18)) }
      }
      .overlay { shape.strokeBorder(.white.opacity(0.15)) }
      .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
  }

  /// Primary call to action.
  @ViewBuilder
  func prominentButtonStyle() -> some View {
    if #available(iOS 26.0, *) {
      buttonStyle(.glassProminent)
    } else {
      buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
    }
  }

  /// Secondary action next to a primary one.
  @ViewBuilder
  func secondaryButtonStyle() -> some View {
    if #available(iOS 26.0, *) {
      buttonStyle(.glass)
    } else {
      buttonStyle(.bordered).buttonBorderShape(.capsule)
    }
  }

  /// Card on a grouped background, used for wishes in the shared view.
  func cardBackground(cornerRadius: CGFloat = 24) -> some View {
    background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: cornerRadius))
  }

  /// iOS 26 shows a subtitle under the navigation title; older versions show nothing extra.
  @ViewBuilder
  func navigationSubtitleIfAvailable(_ subtitle: String) -> some View {
    if #available(iOS 26.0, *) {
      navigationSubtitle(subtitle)
    } else {
      self
    }
  }

  /// Zoom transition from a matched source (iOS 18+).
  func zoomTransition(id: some Hashable, in namespace: Namespace.ID) -> some View {
    navigationTransition(.zoom(sourceID: id, in: namespace))
  }

  /// Gentle cross-fade for utility screens on iOS 27, regular push elsewhere.
  @ViewBuilder
  func crossFadeTransitionIfAvailable() -> some View {
    if #available(iOS 27.0, *) {
      navigationTransition(.crossFade)
    } else {
      self
    }
  }

  /// Segmented control that becomes the new tab-style picker on iOS 27.
  @ViewBuilder
  func filterPickerStyle() -> some View {
    if #available(iOS 27.0, *) {
      pickerStyle(.tabs)
    } else {
      pickerStyle(.segmented)
    }
  }

  /// Soft edge where content scrolls under the floating glass toolbars on iOS 26.
  @ViewBuilder
  func softScrollEdges() -> some View {
    if #available(iOS 26.0, *) {
      scrollEdgeEffectStyle(.soft, for: .all)
    } else {
      self
    }
  }
}

extension ToolbarContent {
  /// iOS 27 drops low-priority items into the overflow menu first when space runs out.
  @ToolbarContentBuilder
  func visibilityPriorityIfAvailable(high: Bool) -> some ToolbarContent {
    if #available(iOS 27.0, *) {
      visibilityPriority(high ? .high : .low)
    } else {
      self
    }
  }
}

/// Groups neighbouring glass elements so they blend and morph together on iOS 26.
struct GlassGroup<Content: View>: View {
  var spacing: CGFloat = 12
  @ViewBuilder var content: Content

  var body: some View {
    if #available(iOS 26.0, *) {
      GlassEffectContainer(spacing: spacing) { content }
    } else {
      content
    }
  }
}

/// System close button (glass "×" on iOS 26), a text button before.
struct CloseButton: View {
  @Environment(L10n.self) private var l10n
  let action: () -> Void

  var body: some View {
    if #available(iOS 26.0, *) {
      Button(role: .close, action: action)
    } else {
      Button(l10n.t(.commonClose), action: action)
    }
  }
}

/// Soft brand-coloured backdrop for headers.
struct BrandBackdrop: View {
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    MeshGradient(
      width: 3, height: 3,
      points: [
        [0, 0], [0.5, 0], [1, 0],
        [0, 0.5], [0.6, 0.45], [1, 0.5],
        [0, 1], [0.5, 1], [1, 1],
      ],
      colors: colorScheme == .dark
        ? [.indigo.opacity(0.55), .purple.opacity(0.45), .accentColor.opacity(0.5),
           .accentColor.opacity(0.3), .purple.opacity(0.25), .indigo.opacity(0.2),
           .clear, .clear, .clear]
        : [.accentColor.opacity(0.35), .purple.opacity(0.22), .orange.opacity(0.18),
           .accentColor.opacity(0.18), .pink.opacity(0.12), .accentColor.opacity(0.12),
           .clear, .clear, .clear]
    )
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
