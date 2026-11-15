import Foundation

/// Same orderings as the web app (frontend/src/app/pages/shared-wishlist/sort-items.ts).
nonisolated enum ItemSort: String, CaseIterable, Identifiable, Sendable {
  case newest, oldest, priority, priceAsc, priceDesc, title

  var id: String { rawValue }

  var label: TKey {
    switch self {
    case .newest: .sharedSortNewest
    case .oldest: .sharedSortOldest
    case .priority: .sharedSortPriority
    case .priceAsc: .sharedSortPriceAsc
    case .priceDesc: .sharedSortPriceDesc
    case .title: .sharedSortTitle
    }
  }
}

nonisolated enum ItemFilter: String, CaseIterable, Identifiable, Sendable {
  case all, open, bought

  var id: String { rawValue }

  var label: TKey {
    switch self {
    case .all: .sharedFilterAll
    case .open: .sharedFilterOpen
    case .bought: .sharedFilterBought
    }
  }

  var emptyText: TKey {
    switch self {
    case .all: .sharedEmptyAll
    case .open: .sharedEmptyOpen
    case .bought: .sharedEmptyBought
    }
  }

  func includes(_ item: Item) -> Bool {
    switch self {
    case .all: true
    case .open: !item.isFullyBought
    case .bought: item.isFullyBought
    }
  }
}

/// Remembers the last filtered and sorted list, so redraws that change nothing about the wishes (busy
/// spinners, typing a name, …) don't sort again. A plain class: updating it never triggers a redraw, and
/// the result is ready in the very first frame – unlike @State filled in `onChange`, which shows an empty
/// list first and then inserts every row while the screen is still being pushed.
final class SortedItemsCache {
  private struct Key: Equatable {
    var items: [Item]
    var filter: ItemFilter?
    var sort: ItemSort
    var locale: Locale
    var boughtLast: Bool
  }

  private var key: Key?
  private var result: [Item] = []

  func items(_ items: [Item], filter: ItemFilter? = nil, sort: ItemSort, locale: Locale, boughtLast: Bool) -> [Item] {
    // Unchanged arrays share their storage, so this comparison is usually instant.
    let key = Key(items: items, filter: filter, sort: sort, locale: locale, boughtLast: boughtLast)
    if key == self.key { return result }
    let visible = filter.map { items.filter($0.includes) } ?? items
    result = ItemSorter.sorted(visible, by: sort, locale: locale, boughtLast: boughtLast)
    self.key = key
    return result
  }
}

nonisolated enum ItemSorter {
  /// Sorts a copy; with `boughtLast`, fully bought wishes sink below everything still needed.
  static func sorted(_ items: [Item], by sort: ItemSort, locale: Locale, boughtLast: Bool) -> [Item] {
    // Swift's sort isn't stable, so the original position breaks remaining ties like JS's stable sort.
    let indexed = items.enumerated().map { ($0.offset, $0.element) }
    return indexed.sorted { lhs, rhs in
      if boughtLast, lhs.1.isFullyBought != rhs.1.isFullyBought { return !lhs.1.isFullyBought }
      let result = compare(lhs.1, rhs.1, sort, locale)
      return result == .orderedSame ? lhs.0 < rhs.0 : result == .orderedAscending
    }.map(\.1)
  }

  private static func newest(_ a: Item, _ b: Item) -> ComparisonResult {
    b.createdAt == a.createdAt ? .orderedSame : (b.createdAt < a.createdAt ? .orderedAscending : .orderedDescending)
  }

  /// Items without a price always go last, regardless of direction.
  private static func price(_ a: Item, _ b: Item, ascending: Bool) -> ComparisonResult {
    switch (a.price, b.price) {
    case (nil, nil): return .orderedSame
    case (nil, _): return .orderedDescending
    case (_, nil): return .orderedAscending
    case (let x?, let y?):
      if x == y { return .orderedSame }
      return (x < y) == ascending ? .orderedAscending : .orderedDescending
    }
  }

  private static func compare(_ a: Item, _ b: Item, _ sort: ItemSort, _ locale: Locale) -> ComparisonResult {
    func or(_ first: ComparisonResult, _ next: @autoclosure () -> ComparisonResult) -> ComparisonResult {
      first == .orderedSame ? next() : first
    }
    switch sort {
    case .newest: return newest(a, b)
    case .oldest: return newest(b, a)
    case .priority:
      let byPriority: ComparisonResult =
        a.priority == b.priority ? .orderedSame : (a.priority > b.priority ? .orderedAscending : .orderedDescending)
      return or(byPriority, newest(a, b))
    case .priceAsc: return or(price(a, b, ascending: true), newest(a, b))
    case .priceDesc: return or(price(a, b, ascending: false), newest(a, b))
    case .title: return a.title.compare(b.title, options: [], range: nil, locale: locale)
    }
  }
}
