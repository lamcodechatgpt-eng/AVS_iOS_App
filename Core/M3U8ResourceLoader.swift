import Foundation
import AVFoundation
import UniformTypeIdentifiers

/// Phục vụ playlist m3u8 từ memory cho AVPlayer qua custom URL scheme.
/// AVPlayer nhiều khi không recognize HLS khi URL là `file://` (không có
/// Content-Type header). Custom scheme + Resource Loader cho phép set
/// explicit MIME `application/vnd.apple.mpegurl`, AVPlayer chắc chắn parse
/// như HLS. Segments trong playlist là HTTPS tuyệt đối → AVPlayer tự fetch
/// trực tiếp, không cần proxy.
final class M3U8ResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    static let customScheme = "avshls"

    private let payload: Data

    init(payload: Data) {
        self.payload = payload
        super.init()
    }

    /// URL "ảo" để gắn vào AVURLAsset. Phải bắt đầu bằng customScheme để
    /// AVPlayer gọi delegate thay vì cố fetch HTTP.
    static func makePlaceholderURL() -> URL {
        return URL(string: "\(customScheme)://stream/playlist.m3u8")!
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard loadingRequest.request.url?.path.hasSuffix("playlist.m3u8") == true else {
            loadingRequest.finishLoading(with: NSError(domain: NSURLErrorDomain,
                                                        code: NSURLErrorUnsupportedURL))
            return true
        }
        if let info = loadingRequest.contentInformationRequest {
            info.contentType = UTType.m3uPlaylist.identifier
            info.contentLength = Int64(payload.count)
            info.isByteRangeAccessSupported = true
        }

        if let dataRequest = loadingRequest.dataRequest {
            let rawOffset = dataRequest.currentOffset != 0 ? dataRequest.currentOffset : dataRequest.requestedOffset
            let offset = max(0, Int(rawOffset))
            let length = dataRequest.requestedLength
            if offset < payload.count {
                let end = offset + min(max(0, length), payload.count - offset)
                let chunk = payload.subdata(in: offset..<end)
                dataRequest.respond(with: chunk)
            }
        }
        loadingRequest.finishLoading()
        return true
    }
}
