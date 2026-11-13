import AppIntents
import Foundation
import WidgetKit

@MainActor enum MobileCompanionBridge {
  static weak var store: LibraryStore?
  static weak var player: AudioController?
  private static var lastWidgetBook: UUID?
  private static var lastWidgetUpdate = Date.distantPast
  private static var importingShared = false
  static func publish(_ book: AudioBook) {
    guard let root = CompanionStorage.directory else { return }
    let snapshot = CompanionSnapshot(
      bookID: book.id, title: book.title, author: book.author, progress: book.progress,
      updatedAt: Date())
    if let data = try? JSONEncoder().encode(snapshot) {
      try? data.write(to: root.appendingPathComponent("now-listening.json"), options: .atomic)
      if lastWidgetBook != book.id || Date().timeIntervalSince(lastWidgetUpdate) >= 60 {
        lastWidgetBook = book.id; lastWidgetUpdate = Date(); WidgetCenter.shared.reloadAllTimelines()
      }
    }
  }
  static func open(_ id: UUID? = nil) async {
    guard let store, let player else {
      UserDefaults.standard.set(true, forKey: "intentContinue")
      return
    }
    let wanted =
      id ?? UserDefaults.standard.string(forKey: "lastPlayedBook").flatMap(UUID.init(uuidString:))
    guard
      let book = store.books.first(where: { $0.id == wanted })
        ?? store.books.first(where: { !$0.state.finished })
    else { return }
    await player.open(book)
    if player.bookID == book.id {
      NotificationCenter.default.post(name: Notification.Name("listen.show-player"), object: nil)
    }
  }
  static func importShared(_ store: LibraryStore) async {
    guard !importingShared else { return }; importingShared = true; defer { importingShared = false }
    guard let inbox = CompanionStorage.directory?.appendingPathComponent("Inbox"),
      let folders = try? FileManager.default.contentsOfDirectory(
        at: inbox, includingPropertiesForKeys: nil)
    else { return }
    for folder in folders
    where FileManager.default.fileExists(atPath: folder.appendingPathComponent("ready.json").path) {
      let files =
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
        .filter { Importer.supported($0) || $0.pathExtension.lowercased() == "zip" } ?? []
      guard !files.isEmpty else { continue }
      let ids = await store.importFiles(
        files, enrich: UserDefaults.standard.object(forKey: "automaticMetadata") as? Bool ?? true,
        convert: UserDefaults.standard.bool(forKey: "automaticConversion"))
      if !ids.isEmpty && store.error == nil { try? FileManager.default.removeItem(at: folder) }
    }
  }
}
struct ContinueListeningIntent: AppIntent {
  static var title: LocalizedStringResource = "Continue listening in listen."
  static var description = IntentDescription("Resume the last audiobook in listen.")
  static var openAppWhenRun = true
  @MainActor func perform() async throws -> some IntentResult {
    await MobileCompanionBridge.open()
    return .result()
  }
}
struct ListenShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: ContinueListeningIntent(),
      phrases: [
        "Continue listening in \(.applicationName)", "Play my audiobook in \(.applicationName)",
      ], shortTitle: "Continue listening", systemImageName: "headphones")
  }
}
