import Foundation
import AVFoundation
import UIKit

struct M4BConverter {
    static func convert(_ original: AudioBook, directory: URL) async throws -> AudioBook {
        guard !original.tracks.isEmpty else { throw ListenError.message("There is no audio to convert.") }
        let composition = AVMutableComposition()
        guard let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw ListenError.message("An audio track could not be created.") }
        var cursor = CMTime.zero
        for track in original.tracks {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: directory.appendingPathComponent(track.filename))
            guard let audio = try await asset.loadTracks(withMediaType: .audio).first else { throw ListenError.message("An input file has no audio track.") }
            let duration = try await asset.load(.duration)
            try target.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audio, at: cursor); cursor = cursor + duration
        }
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else { throw ListenError.message("AAC conversion is unavailable on this device.") }
        let temporary = directory.appendingPathComponent("conversion-\(UUID().uuidString).m4a")
        let output = directory.appendingPathComponent("book-\(UUID().uuidString).m4b")
        defer { try? FileManager.default.removeItem(at: temporary) }
        export.outputURL = temporary; export.outputFileType = .m4a; export.shouldOptimizeForNetworkUse = true
        func item(_ key: AVMetadataIdentifier, _ text: String) -> AVMetadataItem {
            let value = AVMutableMetadataItem(); value.identifier = key; value.value = text as NSString; return value
        }
        var metadata = [item(.commonIdentifierTitle, original.title),item(.commonIdentifierArtist, original.author),item(.commonIdentifierAlbumName, original.title)]
        if let cover = original.coverFilename, let data = try? Data(contentsOf: directory.appendingPathComponent(cover)) {
            let artwork = AVMutableMetadataItem(); artwork.identifier = .commonIdentifierArtwork; artwork.value = data as NSData; artwork.dataType = kCMMetadataBaseDataType_JPEG as String; metadata.append(artwork)
        }
        export.metadata = metadata
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void,Never>) in export.exportAsynchronously { continuation.resume() } }
        }, onCancel: { export.cancelExport() })
        guard export.status == .completed else { throw export.error ?? ListenError.message("Conversion was cancelled. Original files are unchanged.") }
        let chapters = original.chapters.isEmpty ? [Chapter(title: original.title, start: 0)] : original.chapters
        try await Task.detached { try MP4Chapters.write(chapters: chapters, input: temporary, output: output) }.value
        do {
            let verified = AVURLAsset(url: output)
            let duration = try await verified.load(.duration).seconds
            guard try await verified.load(.isPlayable), abs(duration-original.duration) < max(1, original.duration*0.001) else { throw ListenError.message("Converted audio verification failed. Original files are unchanged.") }
            var book = original
            book.tracks = [AudioTrack(filename: output.lastPathComponent, duration: duration)]; book.chapters = chapters; book.metadataUpdatedAt = Date()
            // Retain originals. Updating the library record happens only after verification.
            return book
        } catch { try? FileManager.default.removeItem(at: output); throw error }
    }
}
