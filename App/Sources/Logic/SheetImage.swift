// Decodes a sheet photo no larger than a screen can use, so a 48 MP score never sits decoded in memory.
// What a reader gets wrong: the thumbnail is made from the file, not from a full decode that is then scaled.
import ImageIO
import UIKit

enum SheetImage {
    static let maxPixel = 4096

    /// The image at `url` with its longest side at most `maxPixel`, turned upright; nil when it cannot be read.
    nonisolated static func load(_ url: URL, maxPixel: Int = SheetImage.maxPixel) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
    }
}
