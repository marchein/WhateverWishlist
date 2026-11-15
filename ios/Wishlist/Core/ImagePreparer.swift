import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct PreparedImage: Sendable {
  let data: Data
  let mimeType: String
  let fileExtension: String
}

/// The backend accepts JPEG, PNG, GIF and WebP up to 5 MB. Photos from the library are often HEIC
/// and larger, so anything else is converted to a JPEG that fits.
nonisolated enum ImagePreparer {
  static let maxBytes = 5 * 1024 * 1024

  static func prepare(_ data: Data) throws -> PreparedImage {
    if let type = detect(data), data.count <= maxBytes {
      return PreparedImage(data: data, mimeType: type.mime, fileExtension: type.ext)
    }
    for (side, quality) in [(4096, 0.85), (2560, 0.8), (2048, 0.75), (1600, 0.7), (1200, 0.65)] {
      if let jpeg = jpeg(from: data, maxPixelSize: side, quality: quality), jpeg.count <= maxBytes {
        return PreparedImage(data: jpeg, mimeType: "image/jpeg", fileExtension: "jpg")
      }
    }
    throw LocalizedAppError(key: detect(data) == nil ? .errorsUNSUPPORTEDIMAGE : .editorImageTooLarge)
  }

  static func detect(_ data: Data) -> (mime: String, ext: String)? {
    let bytes = [UInt8](data.prefix(12))
    if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return ("image/jpeg", "jpg") }
    if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return ("image/png", "png") }
    let header = String(decoding: bytes, as: UTF8.self)
    if header.hasPrefix("GIF87a") || header.hasPrefix("GIF89a") { return ("image/gif", "gif") }
    if bytes.count == 12, header.hasPrefix("RIFF"), String(decoding: bytes[8..<12], as: UTF8.self) == "WEBP" {
      return ("image/webp", "webp")
    }
    return nil
  }

  private static func jpeg(from data: Data, maxPixelSize: Int, quality: Double) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
      return nil
    }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    return CGImageDestinationFinalize(destination) ? output as Data : nil
  }
}
