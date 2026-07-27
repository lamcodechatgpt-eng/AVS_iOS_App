import XCTest
@testable import AVS_iOS_App

final class ArchitectureAndExtractorTests: XCTestCase {

    func testDependencyContainerRegistrationAndResolution() async {
        await MainActor.run {
            let container = DependencyContainer.shared
            container.reset()
            container.registerDefaults()

            let playbackRepo = container.resolve(PlaybackRepositoryProtocol.self)
            XCTAssertNotNil(playbackRepo)

            let animeRepo = container.resolve(AnimeRepositoryProtocol.self)
            XCTAssertNotNil(animeRepo)
        }
    }

    func testVideoExtractorRegistryResolvesHydrax() {
        let registry = VideoExtractorRegistry.shared
        let url = "https://hydrax.net/v/12345"
        let extractor = registry.resolveExtractor(for: url)

        XCTAssertNotNil(extractor)
        XCTAssertEqual(extractor?.name, "Hydrax")
    }

    func testVideoExtractorRegistryResolvesStreamTape() {
        let registry = VideoExtractorRegistry.shared
        let url = "https://streamtape.com/e/abcde"
        let extractor = registry.resolveExtractor(for: url)

        XCTAssertNotNil(extractor)
        XCTAssertEqual(extractor?.name, "StreamTape")
    }

    func testVideoExtractorRegistryResolvesFileMoon() {
        let registry = VideoExtractorRegistry.shared
        let url = "https://filemoon.sx/e/xyz"
        let extractor = registry.resolveExtractor(for: url)

        XCTAssertNotNil(extractor)
        XCTAssertEqual(extractor?.name, "FileMoon")
    }

    func testVideoExtractorRegistryFallbackToDefault() {
        let registry = VideoExtractorRegistry.shared
        let url = "https://animevietsub.meme/player/123"
        let extractor = registry.resolveExtractor(for: url)

        XCTAssertNotNil(extractor)
        XCTAssertEqual(extractor?.name, "AnimeVietsub Standard Server")
    }

    func testHydraxExtraction() async throws {
        let extractor = HydraxExtractor()
        let source = try await extractor.extract(url: "https://hydrax.net/v/123", referer: "https://animevietsub.meme/")

        XCTAssertEqual(source.url.absoluteString, "https://hydrax.net/v/123")
        XCTAssertEqual(source.referer, "https://animevietsub.meme/")
    }

    func testImagePipelineInstance() {
        let pipeline = ImagePipeline.shared
        XCTAssertNotNil(pipeline)
    }

    func testPlaybackProgressCalculation() {
        let progress = PlaybackProgress(episodeURL: "https://animevietsub.meme/tap-1.html", positionSeconds: 1200, totalDurationSeconds: 1240)

        XCTAssertGreaterThan(progress.percentage, 0.95)
        XCTAssertTrue(progress.isCompleted)
    }
}
