import Foundation

enum AnimeRepositoryError: Error, LocalizedError {
    case networkError
    case parseError

    var errorDescription: String? {
        switch self {
        case .networkError: return "Lỗi kết nối mạng"
        case .parseError: return "Lỗi bóc tách dữ liệu anime"
        }
    }
}

final class DefaultAnimeRepository: AnimeRepositoryProtocol {
    private let networkManager: NetworkManager

    init(networkManager: NetworkManager = .shared) {
        self.networkManager = networkManager
    }

    func fetchHomeMovies() async throws -> [Movie] {
        try await withCheckedThrowingContinuation { continuation in
            networkManager.fetchMoviesPage(1) { movies in
                continuation.resume(returning: movies)
            }
        }
    }

    func fetchMovieDetails(for link: String) async throws -> MovieDetails {
        try await withCheckedThrowingContinuation { continuation in
            networkManager.fetchMovieDetails(movieUrl: link) { details in
                if let details = details {
                    continuation.resume(returning: details)
                } else {
                    continuation.resume(throwing: AnimeRepositoryError.parseError)
                }
            }
        }
    }

    func fetchEpisodes(for link: String) async throws -> [Episode] {
        try await withCheckedThrowingContinuation { continuation in
            networkManager.fetchEpisodes(movieUrl: link) { episodes in
                continuation.resume(returning: episodes)
            }
        }
    }

    func searchAnime(query: String) async throws -> [Movie] {
        try await withCheckedThrowingContinuation { continuation in
            networkManager.fetchSearchSuggestions(keyword: query) { movies in
                continuation.resume(returning: movies)
            }
        }
    }
}
