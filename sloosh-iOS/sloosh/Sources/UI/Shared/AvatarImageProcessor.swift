import UIKit
import SwiftUI

public enum AvatarImageProcessor {
    public static let maxDimension: CGFloat = 256.0
    public static let maxByteSize: Int = 50 * 1024 // 50 KB

    /// Processes an input UIImage into a compressed base64 Data URI string (< 50KB)
    public static func processAvatar(
        image: UIImage,
        maxDimension: CGFloat = maxDimension,
        maxBytes: Int = maxByteSize
    ) -> String? {
        // 1. Center square crop & scale
        guard let squareResized = cropAndResize(image: image, targetSize: CGSize(width: maxDimension, height: maxDimension)) else {
            return nil
        }

        // 2. Iterative JPEG compression
        var quality: CGFloat = 0.85
        guard var jpegData = squareResized.jpegData(compressionQuality: quality) else {
            return nil
        }

        while jpegData.count > maxBytes && quality > 0.15 {
            quality -= 0.1
            if let compressed = squareResized.jpegData(compressionQuality: quality) {
                jpegData = compressed
            }
        }

        // 3. Format as Base64 Data URI
        let base64String = jpegData.base64EncodedString()
        let dataUri = "data:image/jpeg;base64,\(base64String)"
        
        // Cache immediately in memory
        ImageCache.shared.insertImage(squareResized, forKey: dataUri)
        
        return dataUri
    }

    /// Center square crops and scales to targetSize
    public static func cropAndResize(image: UIImage, targetSize: CGSize) -> UIImage? {
        let size = image.size
        let minSide = min(size.width, size.height)
        guard minSide > 0 else { return nil }

        let cropX = (size.width - minSide) / 2.0
        let cropY = (size.height - minSide) / 2.0
        let scaleRatio = targetSize.width / minSide

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // fixed 1.0 pixel scaling
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(
                x: -cropX * scaleRatio,
                y: -cropY * scaleRatio,
                width: size.width * scaleRatio,
                height: size.height * scaleRatio
            ))
        }
    }

    /// Fast decoding of Base64 Data URI or cached image
    public static func decodeImage(from source: String?) -> UIImage? {
        guard let source = source, !source.isEmpty else { return nil }

        if let cached = ImageCache.shared.image(forKey: source) {
            return cached
        }

        var base64Part = source
        if source.starts(with: "data:image") {
            if let commaIndex = source.firstIndex(of: ",") {
                base64Part = String(source[source.index(after: commaIndex)...])
            }
        }

        if let data = Data(base64Encoded: base64Part, options: .ignoreUnknownCharacters),
           let image = UIImage(data: data) {
            ImageCache.shared.insertImage(image, forKey: source)
            return image
        }

        return nil
    }
}
