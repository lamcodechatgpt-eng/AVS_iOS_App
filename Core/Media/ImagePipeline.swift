import UIKit

/// System xử lý ảnh hiệu năng cao: Downsampling, Two-Tier Caching (Memory + Disk), Prefetching
public final class ImagePipeline: @unchecked Sendable {
    public static let shared = ImagePipeline()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    private init() {
        memoryCache.countLimit = 150 // Tối đa 150 ảnh trong RAM
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // Tối đa 50MB RAM

        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("ImagePipelineCache")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Downsample ảnh khi load để giảm tiêu thụ bộ nhớ RAM
    public func loadImage(from urlString: String, targetSize: CGSize? = nil) async -> UIImage? {
        let key = urlString as NSString

        // 1. Check Memory Cache
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        // 2. Check Disk Cache
        let diskURL = diskCacheURL(forKey: urlString)
        if fileManager.fileExists(atPath: diskURL.path),
           let data = try? Data(contentsOf: diskURL),
           let image = downsample(imageData: data, to: targetSize) {
            memoryCache.setObject(image, forKey: key)
            return image
        }

        // 3. Network Fetch
        guard let url = URL(string: urlString),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let image = downsample(imageData: data, to: targetSize) else {
            return nil
        }

        // Save to Memory & Disk
        memoryCache.setObject(image, forKey: key)
        try? data.write(to: diskURL)

        return image
    }

    /// Prefetch danh sách ảnh trước khi hiển thị trong CollectionView
    public func prefetchImages(urls: [String], targetSize: CGSize? = nil) {
        Task(priority: .background) {
            for urlString in urls {
                _ = await loadImage(from: urlString, targetSize: targetSize)
            }
        }
    }

    public func clearCache() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private func diskCacheURL(forKey key: String) -> URL {
        let hash = String(key.hashValue)
        return cacheDirectory.appendingPathComponent(hash)
    }

    private func downsample(imageData: Data, to targetSize: CGSize?) -> UIImage? {
        guard let size = targetSize, size.width > 0, size.height > 0 else {
            return UIImage(data: imageData)
        }

        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, imageSourceOptions) else {
            return nil
        }

        let maxDimensionInPixels = max(size.width, size.height) * UIScreen.main.scale
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ] as CFDictionary

        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }

        return UIImage(cgImage: downsampledImage)
    }
}
