import Foundation

struct CompanionSnapshot: Codable {
  var bookID: UUID
  var title: String
  var author: String
  var progress: Double
  var updatedAt: Date
}
enum CompanionStorage {
  static let group = "group.io.github.somamill.listen.mobile"
  static var directory: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
  }
  static func read() -> CompanionSnapshot? {
    guard let root = directory,
      let data = try? Data(contentsOf: root.appendingPathComponent("now-listening.json"))
    else { return nil }
    return try? JSONDecoder().decode(CompanionSnapshot.self, from: data)
  }
}
