import AVFoundation
import os
import UniformTypeIdentifiers

/// An `AVURLAsset` for a resolved stream. For HLS it serves the filtered master playlist and the
/// I-frame playlists it declares (scrubbing thumbnails) from memory under a custom URL scheme;
/// variant and segment URLs stay absolute googlevideo URLs and are loaded by AVFoundation directly.
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
        case let .hls(filtered):
            // ID in the path, not the host: IDs may contain "_", which is not a valid hostname character.
            let url = URL(string: "\(Self.scheme)://playlist/\(stream.videoID.rawValue).m3u8")!
            var playlists = [url: Data(filtered.text.utf8)]
            // AVPlayer requests the master's relative I-frame URIs resolved against it.
            for (uri, playlist) in filtered.iFramePlaylists {
                if let iFrameURL = URL(string: uri, relativeTo: url)?.absoluteURL {
                    playlists[iFrameURL] = Data(playlist.utf8)
                }
            }
            let loader = PlaylistLoader(videoID: stream.videoID, master: url, playlists: playlists)
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
    private static let logger = Logger(subsystem: AppInfo.logSubsystem, category: "playback")

    let videoID: VideoID
    let master: URL
    /// The master and its I-frame playlists by the URL AVPlayer requests.
    let playlists: [URL: Data]
    let createdAt = ContinuousClock.now

    init(videoID: VideoID, master: URL, playlists: [URL: Data]) {
        self.videoID = videoID
        self.master = master
        self.playlists = playlists
    }

    func resourceLoader(
        _: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest,
    ) -> Bool {
        guard let url = loadingRequest.request.url?.absoluteURL, let playlist = playlists[url] else { return false }
        if url != master {
            let line = "\(videoID) I-frame playlist \(url.lastPathComponent) requested \(ContinuousClock.now - createdAt) after load"
            Self.logger.info("\(line, privacy: .public)")
        }
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
