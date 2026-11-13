import Foundation
import Combine

@MainActor final class CloudLibrary: ObservableObject {
    @Published var status = "Checking iCloud…"
    @Published var syncing = false
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "cloudEnabled") } }
    private var container: URL?
    private let store: LibraryStore
    private var timer: Timer?
    private var pending: Task<Void,Never>?
    var activeBookID: UUID?
    init(store: LibraryStore) {
        self.store = store
        enabled = UserDefaults.standard.object(forKey: "cloudEnabled") as? Bool ?? true
        store.onChange = { [weak self] in self?.schedule() }
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in await self?.sync() } }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in await self?.sync() } }
    }
    func schedule() {
        pending?.cancel()
        pending = Task { try? await Task.sleep(for: .seconds(3)); guard !Task.isCancelled else { return }; await sync() }
    }
    func cloudRoot() async -> URL? {
        if let container { return container }
        let url = await Task.detached { FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.io.github.somamill.listen.mobile") }.value
        container = url?.appendingPathComponent("Documents/Books", isDirectory: true)
        return container
    }
    static func hydrate(_ url: URL) async throws {
        let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey,.ubiquitousItemDownloadingStatusKey])
        if values.isUbiquitousItem != true { return }
        if values.ubiquitousItemDownloadingStatus == .current || values.ubiquitousItemDownloadingStatus == .downloaded { return }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        for _ in 0..<120 {
            try Task.checkCancellation()
            let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
            if status == .current || status == .downloaded { return }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw ListenError.message("iCloud is still downloading. Keep the app open and try again when your connection is ready.")
    }
    nonisolated static func coordinatedCopy(_ source: URL, _ target: URL) throws {
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordinationError: NSError?; var operationError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, writingItemAt: target, options: .forReplacing, error: &coordinationError) { from, to in
            do {
                let temp = to.deletingLastPathComponent().appendingPathComponent(".incoming-\(UUID().uuidString)")
                try FileManager.default.copyItem(at: from, to: temp)
                if FileManager.default.fileExists(atPath: to.path) { _ = try FileManager.default.replaceItemAt(to, withItemAt: temp) }
                else { try FileManager.default.moveItem(at: temp, to: to) }
            } catch { operationError = error }
        }
        if let error = coordinationError ?? operationError as NSError? { throw error }
    }
    func sync() async {
        guard enabled else { status = "iCloud sync is off"; return }
        guard !syncing else { return }
        syncing = true; defer { syncing = false }
        guard let cloud = await cloudRoot() else { status = "iCloud unavailable. Sign in to iCloud and use a signed build with its iCloud capability enabled."; return }
        do {
            try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
            // Import manifests before publishing. Files download only when opened.
            let directories = try FileManager.default.contentsOfDirectory(at: cloud, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
            for directory in directories {
                guard UUID(uuidString: directory.lastPathComponent) != nil else { continue }
                let manifest = directory.appendingPathComponent("book.json")
                try await Self.hydrate(manifest)
                let data = try await Task.detached { try Data(contentsOf: manifest) }.value
                var remote = try JSONDecoder().decode(AudioBook.self, from: data)
                guard remote.id.uuidString == directory.lastPathComponent, !remote.tracks.isEmpty, remote.tracks.allSatisfy({ Self.safeFilename($0.filename) && $0.duration.isFinite && $0.duration > 0 }), remote.coverFilename.map(Self.safeFilename) ?? true else { continue }
                if let index = store.books.firstIndex(where: { $0.id == remote.id }) {
                    let local = store.books[index]
                    if activeBookID == local.id { continue } // Never jump active playback to another device's position.
                    var state = local.state; state.merge(remote.state)
                    if local.metadataUpdatedAt > remote.metadataUpdatedAt { remote = local }
                    remote.state = state; store.books[index] = remote
                } else { store.books.append(remote) }
            }
            let values = NSUbiquitousKeyValueStore.default
            values.synchronize()
            for index in store.books.indices {
                let key = "progress-" + store.books[index].id.uuidString
                if activeBookID != store.books[index].id, let data = values.data(forKey: key), let state = try? JSONDecoder().decode(ListeningState.self, from: data) { store.books[index].state.merge(state) }
                if let data = try? JSONEncoder().encode(store.books[index].state) { values.set(data, forKey: key) }
            }
            store.save(notify: false)
            let snapshot = store.books; let root = store.root
            try await Task.detached {
                for book in snapshot {
                    let local = root.appendingPathComponent(book.id.uuidString, isDirectory: true)
                    let remote = cloud.appendingPathComponent(book.id.uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
                    for name in book.tracks.map(\.filename) + (book.coverFilename.map { [$0] } ?? []) {
                        let source = local.appendingPathComponent(name); let destination = remote.appendingPathComponent(name)
                        if FileManager.default.fileExists(atPath: source.path), !FileManager.default.fileExists(atPath: destination.path) { try Self.coordinatedCopy(source, destination) }
                    }
                    let data = try JSONEncoder().encode(book)
                    let path = remote.appendingPathComponent("book.json")
                    if (try? Data(contentsOf: path)) != data { try data.write(to: path, options: .atomic) }
                }
            }.value
            status = "Synced with iCloud. Uploads and downloads continue through iCloud Drive."
        } catch { status = "iCloud needs attention: \(error.localizedDescription)" }
    }
    nonisolated static func safeFilename(_ name: String) -> Bool { !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") }
    func download(_ book: AudioBook) async throws {
        guard let cloud = await cloudRoot() else { throw ListenError.message("This book is in iCloud. Sign in to iCloud and enable sync to download it.") }
        for name in book.tracks.map(\.filename) + (book.coverFilename.map { [$0] } ?? []) {
            let target = store.directory(book).appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: target.path) else { continue }
            let source = cloud.appendingPathComponent(book.id.uuidString).appendingPathComponent(name)
            status = "Downloading \(book.title)…"; try await Self.hydrate(source)
            try await Task.detached { try Self.coordinatedCopy(source, target) }.value
        }
        status = "Available offline"
    }
}
