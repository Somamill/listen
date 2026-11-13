import XCTest
import AVFoundation
import ZIPFoundation
@testable import Listen

@MainActor final class ParityTests: XCTestCase {
    var root: URL!
    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func archive(_ name: String, path: String, type: Entry.EntryType = .file) throws -> URL {
        let url = root.appendingPathComponent(name + ".zip")
        let zip = try Archive(url: url, accessMode: .create)
        let bytes = Data("test".utf8)
        try zip.addEntry(with: path, type: type, uncompressedSize: Int64(bytes.count), provider: { offset, count in
            bytes.subdata(in: Int(offset)..<min(bytes.count, Int(offset) + count))
        })
        return url
    }
    func testZipExtractionRejectsTraversalAndSymlinks() throws {
        let valid = try archive("valid", path: "Book/Disc 1/01.mp3")
        let expanded = try ArchiveImporter.expand(valid)
        defer { try? FileManager.default.removeItem(at: expanded) }
        XCTAssertEqual(try Data(contentsOf: expanded.appendingPathComponent("Book/Disc 1/01.mp3")), Data("test".utf8))
        for (index, path) in ["../escaped.mp3", "/absolute.mp3", "Book/../../escaped.mp3"].enumerated() {
            XCTAssertThrowsError(try ArchiveImporter.expand(archive("bad\(index)", path: path)))
        }
        XCTAssertThrowsError(try ArchiveImporter.expand(archive("link", path: "link.mp3", type: .symlink)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escaped.mp3").path))
    }
    func testFolderAndBrowserPaths() throws {
        XCTAssertEqual(try FolderPath.normalize(" Fiction / Series // Book "), "Fiction/Series/Book")
        XCTAssertThrowsError(try FolderPath.normalize("Fiction/../escape"))
        let books = [AudioBook(title: "One", folder: "Fiction/Series/One"), AudioBook(title: "Two", folder: "Fiction/Series/Two"), AudioBook(title: "Other", folder: "History")]
        XCTAssertEqual(FolderPath.children(of: "Fiction", in: books), ["Fiction/Series"])
        XCTAssertEqual(FolderPath.children(of: "Fiction/Series", in: books), ["Fiction/Series/One", "Fiction/Series/Two"])
        for path in ["../x.mp3", "/x.mp3", "book//x.mp3", "book/./x.mp3", "book\\x.mp3"] { XCTAssertFalse(LocalTransfer.safeRelativePath(path)) }
        XCTAssertTrue(LocalTransfer.safeRelativePath("Book/Disc 2/01.mp3"))
    }
    func testLegacyBookmarksAndActivityPersistence() throws {
        let old = "{\"id\":\"\(UUID().uuidString)\",\"position\":15,\"note\":\"My note\"}"
        let bookmark = try JSONDecoder().decode(Bookmark.self, from: Data(old.utf8))
        XCTAssertNil(bookmark.kind); XCTAssertEqual(bookmark.note, "My note")
        let activity = ListeningActivity(root: root)
        activity.record(seconds: 2); activity.record(seconds: .nan); activity.record(seconds: 500)
        let id = UUID(); activity.event(book: id, position: 5, kind: "skip"); activity.event(book: id, position: 5, kind: "skip")
        activity.save()
        let reopened = ListeningActivity(root: root)
        XCTAssertEqual(reopened.snapshot.secondsByDay.values.reduce(0, +), 2)
        XCTAssertEqual(reopened.snapshot.events.count, 1)
    }
    func testSmartRewindAndPeakLimitedGain() {
        XCTAssertEqual(AudioController.rewindAmount(pausedFor: 3, limit: 30), 0)
        XCTAssertGreaterThan(AudioController.rewindAmount(pausedFor: 600, limit: 30), AudioController.rewindAmount(pausedFor: 10, limit: 30))
        XCTAssertEqual(AudioController.rewindAmount(pausedFor: 100000, limit: 7), 7)
        var samples: [Float] = [-0.8, -0.2, 0, 0.3, 0.9]
        samples.withUnsafeMutableBufferPointer { VolumeBoost.process($0.baseAddress!, count: $0.count, gain: 2) }
        XCTAssertEqual(samples, [-1, -0.4, 0, 0.6, 1])
    }
    func testServerOriginPolicyAndCredentialStorage() throws {
        for value in ["http://books.example", "https://name:secret@books.example", "https://books.example/?token=x"] { XCTAssertThrowsError(try MediaServerAPI.validated(value)) }
        let base = URL(string: "https://books.example/library")!
        XCTAssertTrue(OriginRedirectPolicy.sameOrigin(base, URL(string: "https://books.example/file")!))
        XCTAssertFalse(OriginRedirectPolicy.sameOrigin(base, URL(string: "https://evil.example/file")!))
        XCTAssertFalse(OriginRedirectPolicy.sameOrigin(base, URL(string: "http://books.example/file")!))
        let server = MediaServer(name: "Home", kind: .audiobookshelf, baseURL: base.absoluteString)
        let api = try MediaServerAPI(server: server, token: "test-only-secret")
        let request = try api.request(api.url(["api", "libraries"]))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only-secret")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(server), as: UTF8.self).contains("test-only-secret"))
        XCTAssertThrowsError(try api.request(URL(string: "https://evil.example/file")!))
    }
    func testKeychainTokenReplacementWhenEntitled() throws {
        let id = UUID()
        defer { ServerCredential.remove(id) }
        do {
            try ServerCredential.save("first", id: id)
            try ServerCredential.save("second", id: id)
            XCTAssertEqual(ServerCredential.read(id), "second")
        } catch let error as ServerCredentialError where error.status == -34018 {
            throw XCTSkip("Unsigned simulator has no Keychain entitlement; verify with a provisioned device build.")
        }
    }
    func testQueuedImportsAndRecoveryBookmarkLimit() async throws {
        let store = LibraryStore(root: root.appendingPathComponent("Library"))
        let sample = try XCTUnwrap(Bundle.main.url(forResource: "Sample", withExtension: "mp3"))
        async let first = store.importFiles([sample], enrich: false)
        async let second = store.importFiles([sample], enrich: false)
        let ids = await [first, second]
        XCTAssertEqual(ids.map(\.count), [1, 1]); XCTAssertEqual(store.books.count, 2)
        let cloud = CloudLibrary(store: store); cloud.enabled = false
        let player = AudioController(store: store, cloud: cloud)
        let firstBook = try XCTUnwrap(store.books.first)
        let secondBook = try XCTUnwrap(store.books.last)
        player.bookID = firstBook.id
        player.bookmark()
        for position in 0..<110 { player.recovery("skip", at: Double(position * 2)) }
        player.recovery("skip", at: 218)
        let marks = try XCTUnwrap(player.book).bookmarks
        XCTAssertEqual(marks.filter { $0.kind != nil }.count, 100)
        XCTAssertEqual(marks.filter { $0.kind == nil }.count, 1)
        player.queue = []
        player.enqueue(firstBook.id); player.enqueue(secondBook.id); player.enqueue(secondBook.id, next: true)
        XCTAssertEqual(player.queue, [secondBook.id, firstBook.id]); player.queue = []
    }
    func testServerBrowsingWithMockAPIResponses() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ServerFixtureProtocol.self]
        let abs = try MediaServerAPI(server: MediaServer(name: "Fixture", kind: .audiobookshelf, baseURL: "https://fixture.invalid"), token: "fixture-token", configuration: config)
        let libraries = try await abs.items()
        XCTAssertEqual(libraries.map(\.title), ["Books"])
        let books = try await abs.items(parent: "lib", page: 1)
        XCTAssertEqual(books.map(\.title), ["Example Book"])
        XCTAssertEqual(books.first?.author, "Example Author")
        let jellyfin = try MediaServerAPI(server: MediaServer(name: "Fixture", kind: .jellyfin, baseURL: "https://fixture.invalid", userID: "user"), token: "fixture-token", configuration: config)
        let views = try await jellyfin.items()
        XCTAssertEqual(views.first?.id, "view")
    }
    func testBrowserUploadAuthenticationAndStop() async throws {
        let transfer = LocalTransfer(); transfer.start()
        defer { transfer.stop(); transfer.clear() }
        for _ in 0..<100 { if transfer.running { break }; try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(transfer.running)
        let link = try XCTUnwrap(URLComponents(string: transfer.address))
        let token = try XCTUnwrap(link.fragment)
        var base = link; base.fragment = nil
        let upload = try XCTUnwrap(base.url).appendingPathComponent("upload/Book/01.mp3")
        var request = URLRequest(url: upload); request.httpMethod = "PUT"; request.httpBody = Data("test".utf8)
        let (_, denied) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((denied as? HTTPURLResponse)?.statusCode, 401)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (_, accepted) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((accepted as? HTTPURLResponse)?.statusCode, 200)
        for _ in 0..<30 { if !transfer.files.isEmpty { break }; try await Task.sleep(for: .milliseconds(25)) }
        let file = try XCTUnwrap(transfer.files.first)
        XCTAssertEqual(try Data(contentsOf: file), Data("test".utf8))
        let (_, duplicate) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((duplicate as? HTTPURLResponse)?.statusCode, 409)
        transfer.stop(); XCTAssertFalse(transfer.running); XCTAssertTrue(transfer.address.isEmpty)
    }

}

private final class ServerFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let body: String
        if request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token", path == "/api/libraries" {
            body = #"{"libraries":[{"id":"lib","name":"Books"}]}"#
        } else if path == "/api/libraries/lib/items", request.url!.query!.contains("page=1") {
            body = #"{"results":[{"id":"book","media":{"metadata":{"title":"Example Book","authorName":"Example Author"}}}]}"#
        } else if path == "/Users/user/Views", request.value(forHTTPHeaderField: "X-Emby-Token") == "fixture-token" {
            body = #"{"Items":[{"Id":"view","Name":"Audiobooks","IsFolder":true}]}"#
        } else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
