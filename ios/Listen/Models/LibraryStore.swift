import AVFoundation
import Combine
import Foundation

@MainActor final class LibraryStore: ObservableObject {
  @Published var books: [AudioBook] = []
  @Published var busy = false
  @Published var activity = ""
  @Published var waitingImports = 0
  @Published var error: String?
  @Published var notice: String?
  let root: URL
  let deviceID: String
  var onChange: (() -> Void)?
  init(root: URL? = nil) {
    self.root =
      root
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Library", isDirectory: true)
    self.deviceID = UserDefaults.standard.string(forKey: "deviceID") ?? UUID().uuidString
    UserDefaults.standard.set(deviceID, forKey: "deviceID")
    do {
      try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
      let data = try Data(contentsOf: self.root.appendingPathComponent("index.json"))
      books = try JSONDecoder().decode([AudioBook].self, from: data)
    } catch CocoaError.fileReadNoSuchFile {} catch {
      self.error =
        "The saved library could not be read. Files have been retained. \(error.localizedDescription)"
    }
  }
  func directory(_ book: AudioBook) -> URL {
    root.appendingPathComponent(book.id.uuidString, isDirectory: true)
  }
  func file(_ book: AudioBook, _ track: AudioTrack) -> URL {
    directory(book).appendingPathComponent(track.filename)
  }
  func save(notify: Bool = true) {
    do {
      try JSONEncoder().encode(books).write(
        to: root.appendingPathComponent("index.json"), options: .atomic)
      if notify { onChange?() }
    } catch { self.error = "Could not save the library: \(error.localizedDescription)" }
  }
  func update(_ book: AudioBook) {
    guard let i = books.firstIndex(where: { $0.id == book.id }) else { return }
    books[i] = book
    save()
  }
  func position(_ id: UUID, seconds: Double, finished: Bool? = nil) {
    guard let i = books.firstIndex(where: { $0.id == id }) else { return }
    books[i].state.position = max(0, min(seconds, books[i].duration))
    if let finished { books[i].state.finished = finished }
    books[i].state.updatedAt = Date()
    books[i].state.deviceID = deviceID
    save()
  }
  @discardableResult func importFiles(
    _ urls: [URL], combine: Bool = true, enrich: Bool = true, convert: Bool = false
  ) async -> [UUID] {
    let scope = urls.map { ($0, $0.startAccessingSecurityScopedResource()) }
    defer { for (url, active) in scope where active { url.stopAccessingSecurityScopedResource() } }
    waitingImports += 1
    while busy {
      do { try await Task.sleep(for: .milliseconds(150)) } catch {
        waitingImports -= 1
        return []
      }
    }
    waitingImports -= 1
    busy = true
    defer {
      busy = false
      activity = ""
    }
    var created: [UUID] = []
    var expandedRoots: [URL] = []
    defer { for root in expandedRoots { try? FileManager.default.removeItem(at: root) } }
    do {
      var imported: [AudioBook] = []
      // Scope remains open through inspection and copying of external-provider files.
      let scoped = urls.map { ($0, $0.startAccessingSecurityScopedResource()) }
      defer {
        for (url, active) in scoped where active { url.stopAccessingSecurityScopedResource() }
      }
      var sources: [URL] = []
      var inputRoots: [URL] = []
      for url in urls {
        if url.pathExtension.lowercased() == "zip" {
          activity = "Checking and extracting archive…"
          let expanded = try await Task.detached { try ArchiveImporter.expand(url) }.value
          expandedRoots.append(expanded)
          inputRoots.append(expanded)
        } else {
          inputRoots.append(url)
        }
      }
      for url in inputRoots {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
          let items = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
          while let child = items?.nextObject() as? URL {
            if Importer.supported(child) { sources.append(child) }
          }
        } else if Importer.supported(url) {
          sources.append(url)
        }
      }
      guard !sources.isEmpty else {
        throw ListenError.message(
          "Choose MP3, M4B, M4A, FLAC, WAV, AAC, or AIFF files, or a folder containing them.")
      }
      sources.sort {
        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
      }
      let groups: [[URL]]
      if combine, inputRoots.count == 1,
        (try? inputRoots[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
      {
        let base = inputRoots[0].standardizedFileURL
        let grouped = Dictionary(grouping: sources) { source -> String in
          var folder = source.deletingLastPathComponent().standardizedFileURL
          while folder != base
            && folder.lastPathComponent.range(
              of: #"^(?:disc|disk|cd)\s*[-_ ]?\d+$"#,
              options: [.regularExpression, .caseInsensitive]) != nil
          { folder.deleteLastPathComponent() }
          return folder.path
        }
        groups = grouped.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map {
          grouped[$0]!
        }
      } else {
        groups = combine ? [sources] : sources.map({ [$0] })
      }
      for group in groups {
        activity = "Importing \(group.first!.deletingPathExtension().lastPathComponent)…"
        var book = try await Importer.copy(group, into: root)
        // Commit a playable local book before optional network work or conversion.
        books.insert(book, at: 0)
        save()
        imported.append(book)
        created.append(book.id)
        if enrich {
          activity = "Looking up book details…"
          do {
            book = try await MetadataService.enrich(book, directory: directory(book))
            update(book)
          } catch {
            notice =
              "The audio was imported. Online metadata was unavailable; embedded details were kept."
          }
        }
        if convert && book.tracks.contains(where: { $0.filename.lowercased().hasSuffix(".mp3") }) {
          activity = "Converting to M4B…"
          do {
            book = try await M4BConverter.convert(book, directory: directory(book))
            update(book)
          } catch {
            notice =
              "Imported the original audio. M4B conversion did not finish: \(error.localizedDescription)"
          }
        }
      }
      notice = "Imported \(imported.count) audiobook\(imported.count == 1 ? "" : "s")."
    } catch { self.error = error.localizedDescription }
    return created
  }
  func convert(_ book: AudioBook) async {
    guard !busy else { return }
    busy = true
    activity = "Converting to M4B…"
    defer {
      busy = false
      activity = ""
    }
    do {
      update(try await M4BConverter.convert(book, directory: directory(book)))
      notice = "M4B created. Original imported files are retained in the library."
    } catch { self.error = error.localizedDescription }
  }
  func enrich(_ book: AudioBook) async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do { update(try await MetadataService.enrich(book, directory: directory(book))) } catch {
      self.error = error.localizedDescription
    }
  }
  func remove(_ book: AudioBook) {
    // Local removal only. No cloud deletion is implied, so another device can restore it.
    do {
      try FileManager.default.removeItem(at: directory(book))
      books.removeAll { $0.id == book.id }
      save()
    } catch { self.error = error.localizedDescription }
  }
}
