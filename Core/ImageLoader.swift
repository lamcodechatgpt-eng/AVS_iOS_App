import UIKit

final class ImageLoader {
    static let shared = ImageLoader()

    private let memory = NSCache<NSString, UIImage>()
    private let session: URLSession
    private let fileManager = FileManager.default
    private let diskCacheURL: URL

    private init() {
        memory.countLimit = 500
        memory.totalCostLimit = 100 * 1024 * 1024

        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024,
                                   diskCapacity: 300 * 1024 * 1024,
                                   directory: nil)
        config.timeoutIntervalForRequest = 15
        config.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: config)

        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        diskCacheURL = caches.appendingPathComponent("ImageCache", isDirectory: true)
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    private func diskCachePath(for key: String) -> URL {
        let hash = "\(key.hashValue)".data(using: .utf8)?.base64EncodedString() ?? key
        return diskCacheURL.appendingPathComponent(hash)
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

        let diskPath = diskCachePath(for: url.absoluteString)
        if let data = try? Data(contentsOf: diskPath), let img = UIImage(data: data) {
            let decoded = img.decodedImage()
            self.memory.setObject(decoded, forKey: key, cost: Int(decoded.scale * decoded.size.width * decoded.size.height))
            DispatchQueue.main.async {
                guard let iv = imageView, iv.tag == key.hashValue else { return }
                iv.image = decoded
            }
            return nil
        }

        let task = session.dataTask(with: url) { [weak self, weak imageView] data, _, err in
            guard let self = self, let data = data, err == nil else { return }
            guard let img = UIImage(data: data) else { return }
            let decoded = img.decodedImage()
            self.memory.setObject(decoded, forKey: key, cost: Int(decoded.scale * decoded.size.width * decoded.size.height))
            try? data.write(to: diskPath)
            DispatchQueue.main.async {
                guard let iv = imageView, iv.tag == key.hashValue else { return }
                UIView.transition(with: iv, duration: 0.2, options: .transitionCrossDissolve, animations: {
                    iv.image = decoded
                })
            }
        }
        task.resume()
        return task
    }

    func prefetch(_ urls: [URL]) {
        for url in urls {
            let key = url.absoluteString as NSString
            if memory.object(forKey: key) != nil { continue }
            let diskPath = diskCachePath(for: url.absoluteString)
            if let data = try? Data(contentsOf: diskPath), let img = UIImage(data: data) {
                let decoded = img.decodedImage()
                memory.setObject(decoded, forKey: key, cost: Int(decoded.scale * decoded.size.width * decoded.size.height))
                continue
            }
            let task = session.dataTask(with: url) { [weak self] data, _, _ in
                guard let self = self, let data = data, let img = UIImage(data: data) else { return }
                let decoded = img.decodedImage()
                self.memory.setObject(decoded, forKey: key, cost: Int(decoded.scale * decoded.size.width * decoded.size.height))
                try? data.write(to: self.diskCachePath(for: url.absoluteString))
            }
            task.resume()
        }
    }

    func purge() {
        memory.removeAllObjects()
        try? fileManager.removeItem(at: diskCacheURL)
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }
}

extension UIImage {
    func decodedImage() -> UIImage {
        guard let image = cgImage else { return self }
        let size = CGSize(width: image.width, height: image.height)
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo.rawValue) else { return self }
        let rect = CGRect(origin: .zero, size: size)
        context.draw(image, in: rect)
        guard let decoded = context.makeImage() else { return self }
        return UIImage(cgImage: decoded, scale: scale, orientation: imageOrientation)
    }
}
