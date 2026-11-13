import Foundation
import UIKit

struct MetadataService {
    struct Response: Decodable { let results: [Result] }
    struct Result: Decodable {
        let collectionName: String?
        let artistName: String?
        let artworkUrl100: String?
    }
    static func normalized(_ value: String) -> Set<String> {
        Set(value.folding(options: [.caseInsensitive,.diacriticInsensitive], locale: .current).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 })
    }
    static func confidence(_ query: String, _ candidate: String) -> Double {
        let wanted = normalized(query); let actual = normalized(candidate)
        guard !wanted.isEmpty else { return 0 }
        return Double(wanted.intersection(actual).count) / Double(wanted.union(actual).count)
    }
    static func enrich(_ original: AudioBook, directory: URL) async throws -> AudioBook {
        var parts = URLComponents(string: "https://itunes.apple.com/search")!
        parts.queryItems = [URLQueryItem(name: "term", value: original.title + (original.author == "Unknown author" ? "" : " " + original.author)), URLQueryItem(name: "entity", value: "audiobook"), URLQueryItem(name: "limit", value: "8")]
        var request = URLRequest(url: parts.url!); request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ListenError.message("Book metadata is unavailable. Your existing details were kept.") }
        let results = try JSONDecoder().decode(Response.self, from: data).results
        let ranked = results.map { ($0, confidence(original.title, $0.collectionName ?? "")) }.sorted { $0.1 > $1.1 }
        guard let (result, score) = ranked.first, score >= 0.65 else { throw ListenError.message("No confident metadata match. You can edit this book’s details manually.") }
        // Never replace a known author with a conflicting author from a similar title.
        if original.author != "Unknown author", let author = result.artistName, confidence(original.author, author) < 0.5 { throw ListenError.message("The metadata author did not match. Existing details were kept.") }
        var book = original
        if let title = result.collectionName { book.title = title }
        if let author = result.artistName { book.author = author }
        if let value = result.artworkUrl100, let url = URL(string: value.replacingOccurrences(of: "100x100", with: "600x600")), url.scheme == "https" {
            let (image, response) = try await URLSession.shared.data(from: url)
            if (response as? HTTPURLResponse)?.statusCode == 200, image.count <= 8_000_000, let decoded = UIImage(data: image), let jpeg = decoded.jpegData(compressionQuality: 0.9) {
                try jpeg.write(to: directory.appendingPathComponent("cover.jpg"), options: .atomic); book.coverFilename = "cover.jpg"
            }
        }
        book.metadataUpdatedAt = Date(); return book
    }
}
