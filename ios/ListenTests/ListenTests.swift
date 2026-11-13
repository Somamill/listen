import AVFoundation
import XCTest

@testable import Listen

@MainActor final class ListenTests: XCTestCase {
  var root: URL!
  override func setUp() {
    super.setUp()
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }
  override func tearDown() {
    try? FileManager.default.removeItem(at: root)
    super.tearDown()
  }
  func testProgressConflictResolutionAndTrackBoundaries() {
    var book = AudioBook(
      title: "Test",
      tracks: [
        AudioTrack(filename: "1.mp3", duration: 10), AudioTrack(filename: "2.mp3", duration: 20),
      ])
    XCTAssertEqual(book.trackPosition(at: 15).index, 1)
    XCTAssertEqual(book.trackPosition(at: 15).offset, 5)
    XCTAssertEqual(book.trackPosition(at: 10).index, 1)
    XCTAssertEqual(book.trackPosition(at: 100).offset, 20)
    book.state = ListeningState(
      position: 4, updatedAt: Date(timeIntervalSince1970: 10), deviceID: "a")
    book.state.merge(
      ListeningState(position: 2, updatedAt: Date(timeIntervalSince1970: 9), deviceID: "b"))
    XCTAssertEqual(book.state.position, 4)
    book.state.merge(
      ListeningState(position: 8, updatedAt: Date(timeIntervalSince1970: 11), deviceID: "b"))
    XCTAssertEqual(book.state.position, 8)
  }
  func testGoodreadsCSVPreservesShelvesQuotesAndCommas() throws {
    let csv =
      "Book Id,Title,Author,Exclusive Shelf\n1,\"A book, with commas\",An Author,to-read\n2,\"A \"\"quoted\"\" title\",Another Author,read\n3,Third,Third Author,currently-reading\n"
    let books = try GoodreadsConnection.parseCSV(csv)
    XCTAssertEqual(books.count, 3)
    XCTAssertEqual(books[0].title, "A book, with commas")
    XCTAssertEqual(books[1].title, "A \"quoted\" title")
    XCTAssertEqual(books.map(\.shelf), ["to-read", "read", "currently-reading"])
    XCTAssertThrowsError(try GoodreadsConnection.parseCSV("Book Id,Title,Author\n1,\"unfinished,A"))
  }
  func testMetadataConfidenceAndCloudPaths() {
    XCTAssertGreaterThan(
      MetadataService.confidence(
        "A Short History of Nearly Everything", "A Short History of Nearly Everything"), 0.99)
    XCTAssertLessThan(
      MetadataService.confidence(
        "A Short History of Nearly Everything", "A Completely Different Novel"), 0.4)
    XCTAssertTrue(CloudLibrary.safeFilename("book.m4b"))
    XCTAssertFalse(CloudLibrary.safeFilename("../book.mp3"))
    XCTAssertFalse(CloudLibrary.safeFilename("a/b.mp3"))
  }
  func testChapterAtomPatchesFastStartChunkOffsets() throws {
    let entry = MP4Chapters.bytes(4, count: 4) + Data([0, 0, 0, 0])
    let stco = try MP4Chapters.atom(
      "stco",
      Data(repeating: 0, count: 4) + MP4Chapters.bytes(1, count: 4)
        + MP4Chapters.bytes(1000, count: 4))
    let patched = try MP4Chapters.patchOffsets(stco, threshold: 100, delta: 50)
    XCTAssertEqual(try MP4Chapters.number(patched, 16..<20), 1050)
    let atom = try MP4Chapters.chapterAtom([
      Chapter(title: "Start", start: 0), Chapter(title: "Second", start: 12.5),
    ])
    XCTAssertEqual(String(data: atom[4..<8], encoding: .ascii), "chpl")
    XCTAssertEqual(atom[16], 2)
    XCTAssertThrowsError(try MP4Chapters.boxes(entry))
  }
  func sample() throws -> URL {
    let url = try XCTUnwrap(Bundle.main.url(forResource: "Sample", withExtension: "mp3"))
    guard try Data(contentsOf: url).count > 90_000 else { throw ListenError.message("The packaged sample audio is missing or empty. Hydrate source resources and rebuild.") }
    return url
  }
  func testImportAndRealAACConversionRetainSourcesAndChapters() async throws {
    let source = try sample()
    let first = root.appendingPathComponent("01.mp3")
    let second = root.appendingPathComponent("02.mp3")
    try FileManager.default.copyItem(at: source, to: first)
    try FileManager.default.copyItem(at: source, to: second)
    let book = try await Importer.copy([first, second], into: root)
    XCTAssertEqual(book.tracks.count, 2)
    XCTAssertEqual(book.chapters.count, 2)
    XCTAssertGreaterThan(book.duration, 23)
    let directory = root.appendingPathComponent(book.id.uuidString)
    let result = try await M4BConverter.convert(book, directory: directory)
    XCTAssertEqual(result.tracks.count, 1)
    XCTAssertTrue(result.tracks[0].filename.hasSuffix(".m4b"))
    XCTAssertEqual(result.chapters.count, 2)
    let output = directory.appendingPathComponent(result.tracks[0].filename)
    let asset = AVURLAsset(url: output)
    let playable = try await asset.load(.isPlayable)
    XCTAssertTrue(playable)
    let convertedDuration = try await asset.load(.duration).seconds
    XCTAssertEqual(convertedDuration, book.duration, accuracy: 1)
    let audio = try await asset.loadTracks(withMediaType: .audio)
    let descriptions = try await audio[0].load(.formatDescriptions)
    XCTAssertEqual(CMFormatDescriptionGetMediaSubType(descriptions[0]), kAudioFormatMPEG4AAC)
    XCTAssertTrue(try Data(contentsOf: output).range(of: Data("chpl".utf8)) != nil)
    let readChapters = try MP4Chapters.read(from: output)
    XCTAssertEqual(readChapters.count, 2)
    XCTAssertEqual(readChapters[1].start, book.chapters[1].start, accuracy: 0.01)
    let reimported = try await Importer.copy([output], into: root)
    XCTAssertEqual(reimported.chapters.count, 2)
    let evidence = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("verified-conversion.m4b")
    try? FileManager.default.removeItem(at: evidence)
    try FileManager.default.copyItem(at: output, to: evidence)
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: directory.appendingPathComponent(book.tracks[0].filename).path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
  }
  func testFolderImportKeepsBookSubfoldersSeparate() async throws {
    let inbox = root.appendingPathComponent("Inbox")
    let one = inbox.appendingPathComponent("Book One")
    let two = inbox.appendingPathComponent("Book Two")
    try FileManager.default.createDirectory(at: one, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: two, withIntermediateDirectories: true)
    for path in [
      one.appendingPathComponent("01.mp3"), one.appendingPathComponent("02.mp3"),
      two.appendingPathComponent("01.mp3"),
    ] { try FileManager.default.copyItem(at: sample(), to: path) }
    let store = LibraryStore(root: root.appendingPathComponent("Books"))
    await store.importFiles([inbox], combine: true, enrich: false)
    XCTAssertEqual(store.books.count, 2)
    XCTAssertEqual(store.books.map { $0.tracks.count }.sorted(), [1, 2])
    XCTAssertNil(store.error)
  }

  func testLibraryPersistenceAndPlayback() async throws {
    let store = LibraryStore(root: root.appendingPathComponent("library"))
    await store.importFiles([try sample()], enrich: false)
    XCTAssertEqual(store.books.count, 1)
    XCTAssertNil(store.error)
    let book = try XCTUnwrap(store.books.first)
    let cloud = CloudLibrary(store: store)
    cloud.enabled = false
    let player = AudioController(store: store, cloud: cloud)
    await player.open(book)
    XCTAssertTrue(player.playing)
    try await Task.sleep(for: .seconds(2))
    player.tick()
    XCTAssertGreaterThan(player.position, 0)
    player.bookmark()
    player.pause()
    XCTAssertFalse(player.playing)
    let reopened = LibraryStore(root: store.root)
    XCTAssertEqual(reopened.books.first?.bookmarks.filter { $0.kind == nil }.count, 1)
    XCTAssertGreaterThan(reopened.books.first?.state.position ?? 0, 0)
  }
}
