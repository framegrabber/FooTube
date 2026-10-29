import FooTubeCore
import ImageIO
import os
import SwiftUI
import UIKit

/// Remote artwork (thumbnails, avatars) filling its frame, gray until loaded. Callers set the frame
/// and clip shape.
///
/// Replaces `AsyncImage`, whose load is lost when its view goes offscreen mid-load (new subscriptions
/// showed empty avatars until restart). Here a load runs to completion in `RemoteImageLoader` even when
/// the view disappears, and every appearance looks again (memory cache, then the running load, then a
/// new download), so a failed or interrupted load is retried the next time the image is shown.
struct RemoteImage: View {
    let url: URL?
    /// Largest size in points the image is shown at; it is decoded at this size, not at full resolution.
    let size: CGSize

    @Environment(\.displayScale) private var displayScale
    @State private var loaded: RemoteImageLoader.Loaded?

    var body: some View {
        let current = request
        Color.gray.opacity(0.2)
            .overlay {
                if let image = image(for: current) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .task(id: current) {
                guard let request = current, image(for: request) == nil else { return }
                if let image = await RemoteImageLoader.shared.image(for: request) {
                    loaded = RemoteImageLoader.Loaded(request: request, image: image)
                }
            }
    }

    private var request: RemoteImageLoader.Request? {
        url.map {
            RemoteImageLoader.Request(
                url: $0,
                pixelWidth: Int((size.width * displayScale).rounded(.up)),
                pixelHeight: Int((size.height * displayScale).rounded(.up)),
            )
        }
    }

    private func image(for request: RemoteImageLoader.Request?) -> UIImage? {
        guard let request else { return nil }
        if let loaded, loaded.request == request {
            return loaded.image
        }
        return RemoteImageLoader.shared.cached(request)
    }
}

/// Downloads artwork through a shared `URLCache` and decodes it downsampled to the size it is shown at
/// (full-size decodes would quickly exhaust the Apple TV HD's 2 GB). Decoded images stay in a small
/// memory cache; concurrent requests for the same image share one load.
@MainActor
final class RemoteImageLoader {
    struct Request: Hashable, Sendable {
        let url: URL
        let pixelWidth: Int
        let pixelHeight: Int
    }

    struct Loaded {
        let request: Request
        let image: UIImage
    }

    static let shared = RemoteImageLoader()

    private nonisolated static let logger = Logger(subsystem: AppInfo.logSubsystem, category: "images")

    private let session: URLSession
    private let memory = NSCache<NSString, UIImage>()
    private var running: [Request: Task<UIImage?, Never>] = [:]

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 200 << 20)
        session = URLSession(configuration: configuration)
        memory.totalCostLimit = 64 << 20 // decoded bytes, about 110 thumbnails at 640×360
    }

    func cached(_ request: Request) -> UIImage? {
        memory.object(forKey: Self.key(request))
    }

    /// The image, or nil if it could not be loaded. Not cancelled with the caller: the load finishes
    /// and fills the cache for the next appearance. URLs outside `ArtworkURL` (YouTube's image hosts
    /// over https) are never requested: synced documents could carry any URL.
    func image(for request: Request) async -> UIImage? {
        guard ArtworkURL.isAllowed(request.url) else { return nil }
        if let image = cached(request) {
            return image
        }
        if let task = running[request] {
            return await task.value
        }
        let session = session
        let task = Task { await Self.load(request, session: session) }
        running[request] = task
        let image = await task.value
        running[request] = nil
        if let image, let cgImage = image.cgImage {
            memory.setObject(image, forKey: Self.key(request), cost: cgImage.bytesPerRow * cgImage.height)
        }
        return image
    }

    private static func key(_ request: Request) -> NSString {
        "\(request.pixelWidth)x\(request.pixelHeight) \(request.url.absoluteString)" as NSString
    }

    @concurrent
    private nonisolated static func load(_ request: Request, session: URLSession) async -> UIImage? {
        do {
            let (data, response) = try await session.data(from: request.url)
            if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
                logger.error("Image \(request.url.absoluteString, privacy: .public): HTTP \(http.statusCode)")
                return nil
            }
            guard let image = downsample(data, toFill: request) else {
                logger.error("Image \(request.url.absoluteString, privacy: .public): undecodable")
                return nil
            }
            return image
        } catch {
            logger.error("Image \(request.url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Decodes at the smallest size that still fills `pixelWidth`×`pixelHeight` (aspect fill), never
    /// larger than the source.
    private nonisolated static func downsample(_ data: Data, toFill request: Request) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        let scale = min(1, max(Double(request.pixelWidth) / Double(width), Double(request.pixelHeight) / Double(height)))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int((Double(max(width, height)) * scale).rounded(.up))),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
