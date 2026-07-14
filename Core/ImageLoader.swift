import UIKit

/// NSCache-backed lazy image loader.
/// - Memory cache: NSCache (auto-evicted on memory pressure)
/// - Disk cache: URLCache.shared (default 50MB which iOS sets)
/// Cancellable per-cell so reused cells don't paint stale images.
final class ImageLoader {
    static let shared = ImageLoader()

    private let memory = NSCache<NSString, UIImage>()
    private let session: URLSession
    private var activeTokens: [ObjectIdentifier: UUID] = [:]
    private var activeURLs: [ObjectIdentifier: String] = [:]

    private final class Target {
        weak var imageView: UIImageView?
        let identifier: ObjectIdentifier
        let token: UUID

        init(imageView: UIImageView, identifier: ObjectIdentifier, token: UUID) {
            self.imageView = imageView
            self.identifier = identifier
            self.token = token
        }
    }

    private struct PendingRequest {
        let id: UUID
        let task: URLSessionDataTask
        var targets: [Target]
        let keepAliveWithoutTargets: Bool
    }

    /// Main-thread-owned requests keyed by URL. Hero, grid and prefetch consumers
    /// share one download instead of racing duplicate requests for the same poster.
    private var pendingRequests: [String: PendingRequest] = [:]

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
        activeURLs[identifier] = url.absoluteString

        let target = Target(imageView: imageView, identifier: identifier, token: token)
        if var pending = pendingRequests[url.absoluteString] {
            pending.targets.append(target)
            pending.task.priority = URLSessionTask.highPriority
            pendingRequests[url.absoluteString] = pending
            return pending.task
        }

        let requestID = UUID()
        let task = session.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap { UIImage(data: $0) }
            if let image = image { self?.memory.setObject(image, forKey: key) }
            DispatchQueue.main.async {
                guard let self = self,
                      self.pendingRequests[url.absoluteString]?.id == requestID,
                      let completed = self.pendingRequests.removeValue(forKey: url.absoluteString) else { return }
                for target in completed.targets {
                    guard self.activeTokens[target.identifier] == target.token else { continue }
                    self.activeTokens.removeValue(forKey: target.identifier)
                    self.activeURLs.removeValue(forKey: target.identifier)
                    guard let imageView = target.imageView, let image = image else { continue }
                    UIView.transition(with: imageView,
                                      duration: 0.2,
                                      options: .transitionCrossDissolve,
                                      animations: { imageView.image = image })
                }
            }
        }
        task.priority = URLSessionTask.highPriority
        pendingRequests[url.absoluteString] = PendingRequest(id: requestID,
                                                             task: task,
                                                             targets: [target],
                                                             keepAliveWithoutTargets: false)
        task.resume()
        return task
    }

    func cancelLoad(for imageView: UIImageView) {
        dispatchPrecondition(condition: .onQueue(.main))
        let identifier = ObjectIdentifier(imageView)
        guard let token = activeTokens.removeValue(forKey: identifier) else { return }
        guard let url = activeURLs.removeValue(forKey: identifier),
              var pending = pendingRequests[url] else { return }
        pending.targets.removeAll { $0.identifier == identifier && $0.token == token }
        if pending.targets.isEmpty && !pending.keepAliveWithoutTargets {
            pending.task.cancel()
            pendingRequests.removeValue(forKey: url)
        } else {
            pendingRequests[url] = pending
        }
    }

    func prefetch(_ urls: [URL]) {
        dispatchPrecondition(condition: .onQueue(.main))
        for url in urls {
            let key = url.absoluteString as NSString
            let requestKey = url.absoluteString
            if memory.object(forKey: key) != nil || pendingRequests[requestKey] != nil { continue }
            let requestID = UUID()
            let task = session.dataTask(with: url) { [weak self] data, _, _ in
                let image = data.flatMap { UIImage(data: $0) }
                if let image = image { self?.memory.setObject(image, forKey: key) }
                DispatchQueue.main.async {
                    guard let self = self,
                          self.pendingRequests[requestKey]?.id == requestID,
                          let completed = self.pendingRequests.removeValue(forKey: requestKey) else { return }
                    for target in completed.targets {
                        guard self.activeTokens[target.identifier] == target.token else { continue }
                        self.activeTokens.removeValue(forKey: target.identifier)
                        self.activeURLs.removeValue(forKey: target.identifier)
                        guard let imageView = target.imageView, let image = image else { continue }
                        imageView.image = image
                    }
                }
            }
            task.priority = URLSessionTask.lowPriority
            pendingRequests[requestKey] = PendingRequest(id: requestID,
                                                         task: task,
                                                         targets: [],
                                                         keepAliveWithoutTargets: true)
            task.resume()
        }
    }

    func purge() { memory.removeAllObjects() }
}
