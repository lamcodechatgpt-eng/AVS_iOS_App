import Foundation
import AVFoundation

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
        loadingRequest.contentInformationRequest?.contentType = "application/vnd.apple.mpegurl"
        loadingRequest.contentInformationRequest?.contentLength = Int64(payload.count)
        loadingRequest.contentInformationRequest?.isByteRangeAccessSupported = true

        if let dataRequest = loadingRequest.dataRequest {
            let offset = Int(dataRequest.requestedOffset)
            let length = dataRequest.requestedLength
            let end = min(offset + length, payload.count)
            if offset < payload.count {
                let chunk = payload.subdata(in: offset..<end)
                dataRequest.respond(with: chunk)
            }
        }
        loadingRequest.finishLoading()
        return true
    }
}
