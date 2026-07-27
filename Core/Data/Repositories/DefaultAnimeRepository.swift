import Foundation

public enum AnimeRepositoryError: Error, LocalizedError {
    case networkError
    case parseError

    public var errorDescription: String? {
        switch self {
        case .networkError: return "Lỗi kết nối mạng"
        case .parseError: return "Lỗi bóc tách dữ liệu anime"
        }
    }
}

public final class DefaultAnimeRepository: AnimeRepositoryProtocol {
    private let networkManager: NetworkManager

    public init(networkManager: NetworkManager = .shared) {
        self.networkManager = networkManager
    }

    public func fetchHomeMovies() async throws -> [Movie] {
        try await withCheckedThrowingContinuation { continuation in
            networkManager.fetchMovies(page: 1) { movies in
                continuation.resume(returning: movies)
            }
        }
    }

    public func fetchMovieDetails(for link: String) async throws -> MovieDetails {
        try await withCheckedThrowingContinuation { continuation in
            networkManager.fetchMovieDetails(url: link) { details in
                if let details = details {
                    continuation.resume(returning: details)
                } else {
                    continuation.resume(throwing: AnimeRepositoryError.parseError)
                }
            }
        }
    }

    public func fetchEpisodes(for link: String) async throws -> [Episode] {
        try await withCheckedThrowingContinuation { continuation in
            networkManager.fetchEpisodes(url: link) { episodes in
                continuation.resume(returning: episodes)
            }
        }
    }

    public func searchAnime(query: String) async throws -> [Movie] {
        try await withCheckedThrowingContinuation { continuation in
            networkManager.fetchSearchResults(query: query) { movies in
                continuation.resume(returning: movies)
            }
        }
    }
}
