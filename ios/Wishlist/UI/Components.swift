import SwiftUI

struct PriorityStars: View {
  @Environment(L10n.self) private var l10n
  let value: Int
  var showLabel = false
  var onChange: ((Int) -> Void)?

  var body: some View {
    if let onChange {
      editable(onChange)
    } else {
      // Shown in every list row, so kept to plain images without effects.
      HStack(spacing: 2) {
        ForEach(1...5, id: \.self) { level in
          Image(systemName: level <= value ? "star.fill" : "star")
        }
        .font(.caption)
        .foregroundStyle(.orange)
        if showLabel {
          Text(l10n.priorityLabel(value))
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(l10n.priorityLabel(value))
    }
  }

  private func editable(_ onChange: @escaping (Int) -> Void) -> some View {
    HStack(spacing: 6) {
      ForEach(1...5, id: \.self) { level in
        Button {
          onChange(level)
        } label: {
          Image(systemName: level <= value ? "star.fill" : "star")
            .font(.title2)
            .foregroundStyle(.orange)
            .symbolEffect(.bounce, value: level == value)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l10n.priorityLabel(level))
        .accessibilityIdentifier("priority.\(level)")
        .accessibilityAddTraits(level == value ? .isSelected : [])
      }
      if showLabel {
        Text(l10n.priorityLabel(value))
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .padding(.leading, 4)
          .contentTransition(.opacity)
      }
    }
    .sensoryFeedback(.selection, trigger: value)
  }
}

/// Rounded square used as leading visual in lists.
struct Tile<Content: View>: View {
  var size: CGFloat = 44
  var tint: Color = .accentColor
  @ViewBuilder var content: Content

  var body: some View {
    content
      .frame(width: size, height: size)
      .background(tint.gradient.opacity(0.16), in: .rect(cornerRadius: size * 0.28))
      .clipShape(.rect(cornerRadius: size * 0.28))
      .foregroundStyle(tint)
      .accessibilityHidden(true)
  }
}

/// Simple wrapping layout for link chips.
struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(proposal: proposal, subviews: subviews)
    let height = rows.last.map { $0.y + $0.height } ?? 0
    let width = rows.map(\.width).max() ?? 0
    return CGSize(width: proposal.width ?? width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for row in arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews) {
      var x = bounds.minX
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(
          at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
        x += min(size.width, bounds.width) + spacing
      }
    }
  }

  private struct Row {
    var indices: [Int] = []
    var y: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
    let maxWidth = proposal.width ?? .infinity
    var rows: [Row] = [Row()]
    for (index, subview) in subviews.enumerated() {
      let size = subview.sizeThatFits(.unspecified)
      let width = min(size.width, maxWidth)
      if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + width > maxWidth {
        let last = rows[rows.count - 1]
        rows.append(Row(y: last.y + last.height + spacing))
      }
      var row = rows[rows.count - 1]
      row.width += (row.indices.isEmpty ? 0 : spacing) + width
      row.height = max(row.height, size.height)
      row.indices.append(index)
      rows[rows.count - 1] = row
    }
    return rows
  }
}

/// Lists that arrive while their screen is still sliding in wait for the slide to end: building a whole
/// list in the middle of the push dropped a frame on an iPhone 15. The spinner is shown meanwhile, so
/// the wait is hardly noticeable; content that is already there (cached) is never held back.
enum PushTiming {
  /// A navigation push takes about half a second.
  static let duration: Duration = .milliseconds(500)

  static func waitForPushToFinish(since appeared: ContinuousClock.Instant) async {
    let remaining = duration - (ContinuousClock.now - appeared)
    if remaining > .zero { try? await Task.sleep(for: remaining) }
  }
}
