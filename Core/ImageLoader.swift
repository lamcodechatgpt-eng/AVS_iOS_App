import UIKit

/// NSCache-backed lazy image loader.
/// - Memory cache: NSCache (auto-evicted on memory pressure)
/// - Disk cache: URLCache.shared (default 50MB which iOS sets)
/// Cancellable per-cell so reused cells don't paint stale images.
final class ImageLoader {
    static let shared = ImageLoader()

    private let memory = NSCache<NSString, UIImage>()
    private let session: URLSession

    private init() {
        memory.countLimit = 300
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024,
                                   diskCapacity: 200 * 1024 * 1024,
                                   directory: nil)
        config.timeoutIntervalForRequest = 12
        session = URLSession(configuration: config)
    }

    @discardableResult
    func load(_ url: URL, into imageView: UIImageView, placeholder: UIImage? = nil) -> URLSessionDataTask? {
        let key = url.absoluteString as NSString
        if let cached = memory.object(forKey: key) {
            imageView.image = cached
            return nil
        }
        imageView.image = placeholder
        imageView.tag = key.hashValue
        let task = session.dataTask(with: url) { [weak self, weak imageView] data, _, _ in
            guard let data = data, let img = UIImage(data: data) else { return }
            self?.memory.setObject(img, forKey: key)
            DispatchQueue.main.async {
                guard let iv = imageView, iv.tag == key.hashValue else { return }
                UIView.transition(with: iv, duration: 0.2, options: .transitionCrossDissolve, animations: {
                    iv.image = img
                })
            }
        }
        task.resume()
        return task
    }

    func purge() { memory.removeAllObjects() }
}
