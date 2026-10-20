import AppKit
import ScreenCaptureKit

/// An inclusive rectangle in pixel coordinates (top-left origin).
struct PixelRect: Equatable {
    var minX: Int, minY: Int, maxX: Int, maxY: Int
    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }
}

/// Raw RGBA snapshot of one display plus the edge-detection scans that run on it.
final class PixelBuffer {
    let image: CGImage
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(image: CGImage) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let drawn = data.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn, w > 0, h > 0 else { return nil }
        self.image = image
        self.width = w
        self.height = h
        self.bytes = data
    }

    private func offset(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }

    /// Largest per-channel difference between two pixels (by byte offset).
    private func difference(_ a: Int, _ b: Int) -> Int {
        max(abs(Int(bytes[a]) - Int(bytes[b])),
            abs(Int(bytes[a + 1]) - Int(bytes[b + 1])),
            abs(Int(bytes[a + 2]) - Int(bytes[b + 2])))
    }

    /// Walks from (x, y) by (dx, dy) until the colour changes beyond `tolerance`.
    /// Returns the last coordinate (x for horizontal, y for vertical scans) that still matched.
    /// High tolerances compare against the previous pixel so smooth gradients don't stop the scan.
    func scan(x: Int, y: Int, dx: Int, dy: Int, tolerance: Int) -> Int {
        let compareToPrevious = tolerance > 15
        var cx = x, cy = y
        var reference = offset(x, y)
        while true {
            let nx = cx + dx, ny = cy + dy
            guard nx >= 0, ny >= 0, nx < width, ny < height else { break }
            let next = offset(nx, ny)
            if difference(next, reference) > tolerance { break }
            cx = nx; cy = ny
            if compareToPrevious { reference = next }
        }
        return dx != 0 ? cx : cy
    }

    /// Shrinks `rect` to the bounding box of pixels that differ from its top-left (background) colour.
    func fit(_ rect: PixelRect, tolerance: Int) -> PixelRect? {
        let background = offset(rect.minX, rect.minY)
        func rowHasContent(_ y: Int, _ r: PixelRect) -> Bool {
            (r.minX...r.maxX).contains { difference(offset($0, y), background) > tolerance }
        }
        func columnHasContent(_ x: Int, _ r: PixelRect) -> Bool {
            (r.minY...r.maxY).contains { difference(offset(x, $0), background) > tolerance }
        }
        var r = rect
        while r.minY <= r.maxY, !rowHasContent(r.minY, r) { r.minY += 1 }
        guard r.minY <= r.maxY else { return nil }
        while !rowHasContent(r.maxY, r) { r.maxY -= 1 }
        while !columnHasContent(r.minX, r) { r.minX += 1 }
        while !columnHasContent(r.maxX, r) { r.maxX -= 1 }
        return r
    }
}

/// Captures every display once with ScreenCaptureKit at native pixel resolution.
enum ScreenCapturer {
    enum CaptureError: LocalizedError {
        case noDisplays
        var errorDescription: String? { "No displays could be captured." }
    }

    static func capture(screens: [NSScreen]) async throws -> [(NSScreen, PixelBuffer)] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var shots: [(NSScreen, PixelBuffer)] = []
        for screen in screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let display = content.displays.first(where: { $0.displayID == number.uint32Value })
            else { continue }
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            config.captureResolution = .best
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            if let buffer = PixelBuffer(image: image) { shots.append((screen, buffer)) }
        }
        guard !shots.isEmpty else { throw CaptureError.noDisplays }
        return shots
    }
}
