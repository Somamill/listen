import Foundation
import AVFoundation
import UIKit

struct Importer {
    static func supported(_ url: URL) -> Bool { ["mp3","m4b","m4a","flac","wav","aac","aif","aiff"].contains(url.pathExtension.lowercased()) }
    static func copy(_ sources: [URL], into root: URL) async throws -> AudioBook {
        var book = AudioBook(title: sources[0].deletingPathExtension().lastPathComponent)
        let directory = root.appendingPathComponent(book.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            var elapsed: Double = 0
            for (index, source) in sources.enumerated() {
                try Task.checkCancellation()
                if try source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw ListenError.message("Import real audio files rather than symbolic links.") }
                let filename = String(format: "%04d-", index + 1) + source.lastPathComponent
                let local = directory.appendingPathComponent(filename)
                try await Task.detached {
                    var failure: NSError?
                    var copyError: Error?
                    NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &failure) { coordinated in
                        do { try FileManager.default.copyItem(at: coordinated, to: local) } catch { copyError = error }
                    }
                    if let error = failure ?? copyError as NSError? { throw error }
                }.value
                let asset = AVURLAsset(url: local)
                guard try await asset.load(.isPlayable), !(try await asset.load(.hasProtectedContent)) else { throw ListenError.message("This file cannot be played or is DRM-protected: \(source.lastPathComponent)") }
                let duration = try await asset.load(.duration).seconds
                guard duration.isFinite && duration > 0 else { throw ListenError.message("The audio duration could not be read: \(source.lastPathComponent)") }
                let metadata = try await asset.load(.commonMetadata)
                if index == 0 {
                    let album = try await AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierAlbumName).first?.load(.stringValue)
                    let title = try await AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierTitle).first?.load(.stringValue)
                    book.title = sources.count > 1 ? (album ?? source.deletingLastPathComponent().lastPathComponent) : (title ?? book.title)
                    if let author = try await AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtist).first?.load(.stringValue), !author.isEmpty { book.author = author }
                    if let data = try await AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first?.load(.dataValue), let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.9) {
                        try jpeg.write(to: directory.appendingPathComponent("cover.jpg"), options: .atomic); book.coverFilename = "cover.jpg"
                    }
                }
                let groups = try await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: Locale.preferredLanguages)
                if groups.isEmpty {
                    let nero = ["m4a","m4b"].contains(local.pathExtension.lowercased()) ? ((try? MP4Chapters.read(from:local)) ?? []) : []
                    if nero.isEmpty { book.chapters.append(Chapter(title: sources.count > 1 ? source.deletingPathExtension().lastPathComponent : book.title, start: elapsed)) }
                    else { book.chapters += nero.filter { $0.start >= 0 && $0.start < duration }.map { Chapter(title:$0.title,start:elapsed+$0.start) } }
                } else {
                    for group in groups {
                        let title = try await AVMetadataItem.metadataItems(from: group.items, filteredByIdentifier: .commonIdentifierTitle).first?.load(.stringValue)
                        book.chapters.append(Chapter(title: title ?? "Chapter \(book.chapters.count + 1)", start: elapsed + group.timeRange.start.seconds))
                    }
                }
                book.tracks.append(AudioTrack(filename: filename, duration: duration)); elapsed += duration
            }
            return book
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
}
