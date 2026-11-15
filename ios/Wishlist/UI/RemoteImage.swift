import ImageIO
import SwiftUI
import UIKit

/// Downloads, downsamples and caches wish pictures.
///
/// `AsyncImage` decodes every picture at full size on each appearance, which makes lists with many
/// shop images stutter. Here each picture is decoded once, off the main thread, at the size it is
/// shown at, and kept in memory; the data itself stays in the shared URLCache.
nonisolated final class ImagePipeline: @unchecked Sendable {
  static let shared = ImagePipeline()

  private let session: URLSession
  private let memory = NSCache<NSString, UIImage>()
  private let lock = NSLock()
  private var running: [String: Download] = [:]

  /// One shared download and how many callers still wait for it (guarded by `lock`).
  private nonisolated final class Download: @unchecked Sendable {
    let task: Task<UIImage, Error>
    var waiters = 0
    init(task: Task<UIImage, Error>) { self.task = task }
  }

  init(session: URLSession = .shared) {
    self.session = session
    memory.totalCostLimit = 160 * 1024 * 1024
    memory.countLimit = 400
  }

  func cached(_ url: URL, maxPixelSize: Int) -> UIImage? {
    memory.object(forKey: Self.key(url, maxPixelSize) as NSString)
  }

  func image(for url: URL, maxPixelSize: Int) async throws -> UIImage {
    let key = Self.key(url, maxPixelSize)
    if let image = memory.object(forKey: key as NSString) { return image }

    // Several views showing the same picture share one download. It is cancelled once nobody waits for
    // it any more, so pictures scrolled past quickly don't keep the network busy for the visible ones.
    let priority = Task.currentPriority
    let download = lock.withLock {
      let download: Download
      if let existing = running[key], !existing.task.isCancelled {
        download = existing
      } else {
        download = Download(
          task: Task.detached(priority: priority) { [self] in
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
              throw URLError(.badServerResponse)
            }
            try Task.checkCancellation()
            guard let image = Self.downsample(data, maxPixelSize: maxPixelSize) else {
              throw URLError(.cannotDecodeContentData)
            }
            memory.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
            return image
          })
        running[key] = download
      }
      download.waiters += 1
      return download
    }
    defer {
      lock.withLock {
        download.waiters -= 1
        if download.waiters == 0, running[key] === download { running[key] = nil }
      }
    }
    return try await withTaskCancellationHandler {
      try await download.task.value
    } onCancel: {
      lock.withLock {
        if download.waiters <= 1 { download.task.cancel() }
      }
    }
  }

  /// Warms the cache for pictures that are about to scroll into view.
  func prefetch(_ urls: [URL], maxPixelSize: Int) {
    for url in urls where cached(url, maxPixelSize: maxPixelSize) == nil {
      Task.detached(priority: .utility) { [self] in
        _ = try? await image(for: url, maxPixelSize: maxPixelSize)
      }
    }
  }

  private static func key(_ url: URL, _ maxPixelSize: Int) -> String {
    "\(maxPixelSize)|\(url.absoluteString)"
  }

  private static func cost(of image: UIImage) -> Int {
    guard let cgImage = image.cgImage else { return 1 }
    return cgImage.bytesPerRow * cgImage.height
  }

  static func downsample(_ data: Data, maxPixelSize: Int) -> UIImage? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return UIImage(cgImage: image)
  }
}

extension EnvironmentValues {
  @Entry var imagePipeline: ImagePipeline = .shared
}

/// Display sizes (longest side, in points) the pictures are decoded for.
enum ImageSize {
  static let thumbnail: CGFloat = 60
  static let editor: CGFloat = 96
  static let card: CGFloat = 320
}

/// Network picture with placeholder, backed by ImagePipeline.
struct RemoteImage: View {
  @Environment(\.imagePipeline) private var pipeline
  @Environment(\.displayScale) private var displayScale

  let url: URL?
  var contentMode: ContentMode = .fill
  /// Longest side the picture is shown at, in points.
  var maxPointSize: CGFloat
  var onFailure: (() -> Void)?

  @State private var loaded: UIImage?
  @State private var loadedURL: URL?
  @State private var failedURL: URL?

  private var pixelSize: Int { Int((maxPointSize * displayScale).rounded(.up)) }

  var body: some View {
    let image: UIImage? = url.flatMap { url in
      loadedURL == url ? loaded : pipeline.cached(url, maxPixelSize: pixelSize)
    }
    ZStack {
      if let image {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: contentMode)
          .transition(.opacity)
      } else if url == nil || failedURL == url {
        Image(systemName: "gift")
          .font(.title2)
          .foregroundStyle(.tertiary)
      } else {
        Color(.tertiarySystemFill)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task(id: url) { await load() }
  }

  private func load() async {
    guard let url, pipeline.cached(url, maxPixelSize: pixelSize) == nil else { return }
    do {
      let image = try await pipeline.image(for: url, maxPixelSize: pixelSize)
      guard !Task.isCancelled else { return }
      withAnimation(.easeOut(duration: 0.15)) {
        loaded = image
        loadedURL = url
      }
    } catch {
      guard !Task.isCancelled else { return }
      failedURL = url
      onFailure?()
    }
  }
}
