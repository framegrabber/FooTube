import AVFoundation
import UniformTypeIdentifiers

/// An `AVURLAsset` for a resolved stream. For HLS it serves the filtered master playlist from
/// memory under a custom URL scheme; variant and segment URLs stay absolute googlevideo URLs and
/// are loaded by AVFoundation directly.
///
/// Keep this object alive while the asset plays: `AVAssetResourceLoader` holds its delegate weakly.
public final class PlaybackSource: Identifiable, Sendable {
    public let stream: ResolvedStream
    public let asset: AVURLAsset

    public var id: VideoID {
        stream.videoID
    }

    private let loader: PlaylistLoader?

    static let scheme = "footube-hls"

    public init(stream: ResolvedStream) {
        self.stream = stream
        switch stream.kind {
        case let .hls(playlist, _, _):
            // ID in the path, not the host: IDs may contain "_", which is not a valid hostname character.
            let url = URL(string: "\(Self.scheme)://playlist/\(stream.videoID.rawValue).m3u8")!
            let loader = PlaylistLoader(url: url, playlist: Data(playlist.utf8))
            let asset = AVURLAsset(url: url)
            asset.resourceLoader.setDelegate(loader, queue: PlaylistLoader.queue)
            self.loader = loader
            self.asset = asset
        case .muxed:
            loader = nil
            asset = AVURLAsset(url: stream.url)
        }
    }
}

private final class PlaylistLoader: NSObject, AVAssetResourceLoaderDelegate, Sendable {
    static let queue = DispatchQueue(label: "\(AppInfo.logSubsystem).playlist-loader")

    let url: URL
    let playlist: Data

    init(url: URL, playlist: Data) {
        self.url = url
        self.playlist = playlist
    }

    func resourceLoader(
        _: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest,
    ) -> Bool {
        guard loadingRequest.request.url == url else { return false }
        if let info = loadingRequest.contentInformationRequest {
            info.contentType = UTType.m3uPlaylist.identifier
            info.contentLength = Int64(playlist.count)
            info.isByteRangeAccessSupported = false
        }
        loadingRequest.dataRequest?.respond(with: playlist)
        loadingRequest.finishLoading()
        return true
    }
}
