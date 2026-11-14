import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Small in-memory thumbnails for image attachments: decoded off the main thread the first time a
/// tile shows, kept per attachment, and dropped when the attachment is removed.
@MainActor
enum AttachmentThumbnails {
    /// Longest side in pixels: a tile at 2x.
    private static let maxPixels = 160
    private static let cache: NSCache<NSUUID, NSImage> = {
        let cache = NSCache<NSUUID, NSImage>()
        cache.countLimit = 200
        return cache
    }()

    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    static func cached(_ id: UUID) -> NSImage? { cache.object(forKey: id as NSUUID) }

    static func load(_ id: UUID, url: URL) async -> NSImage? {
        if let hit = cached(id) { return hit }
        let maxPixels = maxPixels
        let cgImage = await Task.detached(priority: .utility) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        guard let cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: .zero)
        cache.setObject(image, forKey: id as NSUUID)
        return image
    }

    static func drop(_ id: UUID) { cache.removeObject(forKey: id as NSUUID) }
}
