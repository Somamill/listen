import Foundation
import ZIPFoundation

struct ArchiveImporter {
  static let maximumBytes: UInt64 = 20 * 1024 * 1024 * 1024
  static func safePath(_ name: String) -> Bool {
    guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0") else {
      return false
    }
    return !name.split(separator: "/", omittingEmptySubsequences: false).contains(where: {
      $0 == ".." || $0 == "."
    })
  }
  static func expand(_ source: URL) throws -> URL {
    let archive = try Archive(url: source, accessMode: .read)
    let entries = Array(archive)
    guard entries.count <= 10_000 else {
      throw ListenError.message("This archive contains too many entries (limit: 10,000).")
    }
    var total: UInt64 = 0
    for entry in entries {
      guard safePath(entry.path), entry.type != .symlink else {
        throw ListenError.message(
          "The archive contains an unsafe path or symbolic link. Nothing was imported.")
      }
      let (sum, overflow) = total.addingReportingOverflow(entry.uncompressedSize)
      guard !overflow, sum <= maximumBytes else {
        throw ListenError.message("This archive exceeds the 20 GB import limit.")
      }
      total = sum
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "listen-zip-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    do {
      for entry in entries {
        try Task.checkCancellation()
        guard
          !entry.path.split(separator: "/").contains(where: {
            $0.hasPrefix(".") || $0 == "__MACOSX"
          })
        else { continue }
        let destination = root.appendingPathComponent(entry.path)
        if entry.type == .directory {
          try FileManager.default.createDirectory(
            at: destination, withIntermediateDirectories: true)
          continue
        }
        guard
          Importer.supported(destination)
            || ["jpg", "jpeg", "png"].contains(destination.pathExtension.lowercased())
        else { continue }
        try FileManager.default.createDirectory(
          at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try archive.extract(entry, to: destination, skipCRC32: false)
      }
      return root
    } catch {
      try? FileManager.default.removeItem(at: root)
      throw error
    }
  }
}
