import Foundation

struct Chapter: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var start: Double
}
struct AudioTrack: Codable, Identifiable, Equatable {
    var id = UUID()
    var filename: String
    var duration: Double
}
struct Bookmark: Codable, Identifiable, Equatable {
    var id = UUID()
    var position: Double
    var note: String
}
struct ListeningState: Codable, Equatable {
    var position: Double = 0
    var finished = false
    var updatedAt = Date.distantPast
    var deviceID = ""
    mutating func merge(_ other: Self) {
        if other.updatedAt > updatedAt || (other.updatedAt == updatedAt && other.deviceID > deviceID) { self = other }
    }
}
struct AudioBook: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var author: String = "Unknown author"
    var narrator: String = ""
    var folder: String = ""
    var tracks: [AudioTrack] = []
    var chapters: [Chapter] = []
    var bookmarks: [Bookmark] = []
    var coverFilename: String? = nil
    var state = ListeningState()
    var createdAt = Date()
    var metadataUpdatedAt = Date()
    var duration: Double { tracks.reduce(0) { $0 + $1.duration } }
    var progress: Double { duration > 0 ? min(1, max(0, state.position / duration)) : 0 }
    func trackPosition(at position: Double) -> (index: Int, offset: Double) {
        var remaining = max(0, position)
        for (index, track) in tracks.enumerated() {
            if remaining < track.duration || index == tracks.count - 1 { return (index, min(remaining, track.duration)) }
            remaining -= track.duration
        }
        return (0, 0)
    }
    func offset(for index: Int) -> Double { tracks.prefix(index).reduce(0) { $0 + $1.duration } }
}
struct GoodreadsBook: Codable, Identifiable {
    var id: String
    var title: String
    var author: String
    var shelf: String
    var cover: String?
    var url: String
}

enum ListenError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}
func timeLabel(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let total = max(0, Int(seconds)); let hours = total / 3600
    return hours > 0 ? String(format: "%d:%02d:%02d", hours, (total / 60) % 60, total % 60) : String(format: "%d:%02d", total / 60, total % 60)
}
