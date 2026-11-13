import Combine
import Foundation

struct ListeningEvent: Codable, Identifiable {
  var id = UUID()
  var bookID: UUID
  var position: Double
  var kind: String
  var date = Date()
}
struct ActivitySnapshot: Codable {
  var secondsByDay: [String: Double] = [:]
  var events: [ListeningEvent] = []
}
@MainActor final class ListeningActivity: ObservableObject {
  @Published private(set) var snapshot: ActivitySnapshot
  private let url: URL
  init(root: URL) {
    url = root.appendingPathComponent("listening-activity.json")
    snapshot =
      (try? JSONDecoder().decode(ActivitySnapshot.self, from: Data(contentsOf: url)))
      ?? ActivitySnapshot()
  }
  static func dayKey(_ date: Date = Date()) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = Calendar(identifier: .gregorian)
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
  }
  func record(seconds: Double, date: Date = Date()) {
    guard seconds.isFinite, seconds > 0, seconds <= 5 else { return }
    snapshot.secondsByDay[Self.dayKey(date), default: 0] += seconds
  }
  func event(book: UUID, position: Double, kind: String) {
    if let last = snapshot.events.first, last.bookID == book, last.kind == kind,
      abs(last.position - position) < 1, Date().timeIntervalSince(last.date) < 2
    {
      return
    }
    snapshot.events.insert(ListeningEvent(bookID: book, position: position, kind: kind), at: 0)
    snapshot.events = Array(snapshot.events.prefix(1000))
    save()
  }
  func save() { try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic) }
}
enum FolderPath {
  static func normalize(_ value: String) throws -> String {
    let parts = value.split(separator: "/", omittingEmptySubsequences: true).map {
      String($0).trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
    guard parts.count <= 16,
      parts.allSatisfy({
        $0 != "." && $0 != ".." && !$0.contains("\0") && !$0.contains("\\") && $0.count <= 120
      })
    else {
      throw ListenError.message("Use folder names separated by /, without . or .. components.")
    }
    return parts.joined(separator: "/")
  }
  static func children(of path: String, in books: [AudioBook]) -> [String] {
    let prefix = path.isEmpty ? "" : path + "/"
    return Array(
      Set(
        books.compactMap { book -> String? in
          guard book.folder.hasPrefix(prefix) else { return nil }
          let tail = book.folder.dropFirst(prefix.count)
          guard let first = tail.split(separator: "/").first else { return nil }
          return prefix + first
        })
    ).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }
}
