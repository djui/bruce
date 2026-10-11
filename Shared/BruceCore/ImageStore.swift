import SwiftUI
import ImageIO
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

/// Remote image loader shared by both apps.
///
/// SwiftUI's `AsyncImage` cancels its download whenever the view is torn down or re-created
/// (lazy stacks while scrolling, or the frequent `AppModel` updates while real data streams in)
/// and then stays on the placeholder. Here every URL is fetched once in an unstructured task that
/// outlives the view, de-duplicated while in flight, and kept in a memory cache (plus `URLCache` on disk).
final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()

    private let cache = NSCache<NSURL, PlatformImage>()
    private var inFlight: [URL: Task<(PlatformImage, Int)?, Never>] = [:]
    private let lock = NSLock()
    private let session: URLSession

    private init() {
        cache.totalCostLimit = 96 << 20   // decoded bytes, not image count
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 256 << 20)
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: cfg)
    }

    func cached(_ url: URL) -> PlatformImage? { cache.object(forKey: url as NSURL) }

    /// Target pixel size from the Cloudinary transform (w_/h_ × dpr_3), so we never decode more than displayed.
    static func maxPixels(for url: URL) -> Int {
        let p = url.absoluteString
        func v(_ k: String) -> Int? {
            guard let r = p.range(of: "\(k)_") else { return nil }
            return Int(p[r.upperBound...].prefix { $0.isNumber })
        }
        return max(v("w") ?? 400, v("h") ?? 400) * (v("dpr") ?? 3)
    }

    /// ImageIO thumbnail decode (off the main thread, already decompressed, downsampled to the display size).
    static func decode(_ data: Data, maxPixels: Int) -> PlatformImage? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, opts) else { return nil }
        let thumbOpts = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                         kCGImageSourceShouldCacheImmediately: true,
                         kCGImageSourceCreateThumbnailWithTransform: true,
                         kCGImageSourceThumbnailMaxPixelSize: maxPixels] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts) else { return nil }
        #if canImport(UIKit)
        return UIImage(cgImage: cg)
        #else
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        #endif
    }

    func image(for url: URL) async -> PlatformImage? {
        if let img = cached(url) { return img }
        let task: Task<(PlatformImage, Int)?, Never> = lock.withLock {
            if let t = inFlight[url] { return t }
            let px = Self.maxPixels(for: url)
            let t = Task.detached(priority: .userInitiated) { [session] () -> (PlatformImage, Int)? in
                // One retry: transient failures should not leave a permanent placeholder.
                for attempt in 0..<2 {
                    if let (data, resp) = try? await session.data(from: url),
                       (resp as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                       let img = Self.decode(data, maxPixels: px) {
                        let cost = (img.cgImageCost)
                        return (img, cost)
                    }
                    if attempt == 0 { try? await Task.sleep(nanoseconds: 600_000_000) }
                }
                return nil
            }
            inFlight[url] = t
            return t
        }
        let result = await task.value
        lock.withLock { inFlight[url] = nil }
        if let (img, cost) = result { cache.setObject(img, forKey: url as NSURL, cost: cost); return img }
        return nil
    }
}

private extension PlatformImage {
    var cgImageCost: Int {
        #if canImport(UIKit)
        guard let cg = cgImage else { return 1 }
        #else
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 1 }
        #endif
        return cg.bytesPerRow * cg.height
    }
}

/// Drop-in replacement for `AsyncImage` that uses `ImageStore`.
struct StoredImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: PlatformImage?

    var body: some View {
        Group {
            if let image = image ?? url.flatMap({ ImageStore.shared.cached($0) }) {
                #if canImport(UIKit)
                Image(uiImage: image).resizable().scaledToFill()
                #else
                Image(nsImage: image).resizable().scaledToFill()
                #endif
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            image = await ImageStore.shared.image(for: url)
        }
    }
}
