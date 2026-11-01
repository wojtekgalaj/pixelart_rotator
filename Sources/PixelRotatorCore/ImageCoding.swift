import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ImageFileError: LocalizedError, Sendable {
    public var message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

public enum ImageCoding {
    public static func decode(_ data: Data) throws -> PixelImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageFileError("Could not read that image.")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageFileError("Could not read that image.")
        }
        return try PixelImage(cgImage: cgImage)
    }

    public static func load(url: URL) throws -> PixelImage {
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    public static func pngData(_ image: PixelImage) throws -> Data {
        guard let cgImage = image.cgImage() else {
            throw ImageFileError("Could not encode that image.")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageFileError("Could not encode that image.")
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageFileError("Could not encode that image.")
        }
        return data as Data
    }

    public static func writePNG(_ image: PixelImage, to url: URL) throws {
        try pngData(image).write(to: url)
    }

    public static func writeGIF(_ frames: [PixelImage], fps: Double, to url: URL) throws {
        guard !frames.isEmpty else {
            throw ImageFileError("There are no frames to export.")
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            throw ImageFileError("Could not create a GIF.")
        }
        let loop: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ]
        CGImageDestinationSetProperties(destination, loop as CFDictionary)
        let delay = 1.0 / max(1, fps)
        let frameProps: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]
        ]
        for frame in frames {
            guard let cgImage = frame.cgImage() else { continue }
            CGImageDestinationAddImage(destination, cgImage, frameProps as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw ImageFileError("Could not write the GIF.")
        }
    }
}

extension PixelImage {
    init(cgImage: CGImage) throws {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            throw ImageFileError("That image is empty.")
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: info
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { throw ImageFileError("Could not read that image.") }
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = UInt16(pixels[i + 3])
            if alpha == 0 || alpha == 255 { continue }
            pixels[i] = UInt8(min(255, UInt16(pixels[i]) * 255 / alpha))
            pixels[i + 1] = UInt8(min(255, UInt16(pixels[i + 1]) * 255 / alpha))
            pixels[i + 2] = UInt8(min(255, UInt16(pixels[i + 2]) * 255 / alpha))
        }
        self.init(width: width, height: height, pixels: pixels)
    }
}
