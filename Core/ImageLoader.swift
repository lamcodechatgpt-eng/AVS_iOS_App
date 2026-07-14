import UIKit

/// NSCache-backed lazy image loader.
/// - Memory cache: NSCache (auto-evicted on memory pressure)
/// - Disk cache: URLCache.shared (default 50MB which iOS sets)
/// Cancellable per-cell so reused cells don't paint stale images.
final class ImageLoader {
    static let shared = ImageLoader()

    private let memory = NSCache<NSString, UIImage>()
    private let session: URLSession
    private var activeTasks: [ObjectIdentifier: URLSessionDataTask] = [:]
    private var activeTokens: [ObjectIdentifier: UUID] = [:]

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
        dispatchPrecondition(condition: .onQueue(.main))
        let key = url.absoluteString as NSString
        let identifier = ObjectIdentifier(imageView)
        cancelLoad(for: imageView)
        if let cached = memory.object(forKey: key) {
            imageView.image = cached
            return nil
        }
        imageView.image = placeholder
        let token = UUID()
        activeTokens[identifier] = token
        let task = session.dataTask(with: url) { [weak self, weak imageView] data, _, _ in
            let image = data.flatMap { UIImage(data: $0) }
            if let image = image { self?.memory.setObject(image, forKey: key) }
            DispatchQueue.main.async {
                guard let self = self, self.activeTokens[identifier] == token else { return }
                self.activeTokens.removeValue(forKey: identifier)
                self.activeTasks.removeValue(forKey: identifier)
                guard let iv = imageView, let image = image else { return }
                UIView.transition(with: iv, duration: 0.2, options: .transitionCrossDissolve, animations: {
                    iv.image = image
                })
            }
        }
        activeTasks[identifier] = task
        task.resume()
        return task
    }

    func cancelLoad(for imageView: UIImageView) {
        dispatchPrecondition(condition: .onQueue(.main))
        let identifier = ObjectIdentifier(imageView)
        activeTasks.removeValue(forKey: identifier)?.cancel()
        activeTokens.removeValue(forKey: identifier)
    }

    func prefetch(_ urls: [URL]) {
        for url in urls {
            let key = url.absoluteString as NSString
            if memory.object(forKey: key) != nil { continue }
            session.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let img = UIImage(data: data) else { return }
                self?.memory.setObject(img, forKey: key)
            }.resume()
        }
    }

    func purge() { memory.removeAllObjects() }
}
