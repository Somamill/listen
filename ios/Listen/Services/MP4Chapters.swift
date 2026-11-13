import Foundation

/// Adds Nero-style chapter markers to AAC/MP4 audio. Patches chunk offsets if
/// expanding a fast-start moov moves media data. Audio bytes are never reencoded here.
struct MP4Chapters {
    struct Box { var type: String; var start: Int; var length: Int; var header: Int }
    static func number(_ data: Data, _ range: Range<Int>) throws -> UInt64 {
        guard range.lowerBound >= 0, range.upperBound <= data.count else { throw ListenError.message("Invalid MP4 structure.") }
        return data[range].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
    static func bytes(_ value: UInt64, count: Int) -> Data { Data((0..<count).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }
    static func boxes(_ data: Data, from start: Int = 0) throws -> [Box] {
        var result: [Box] = []; var offset = start
        while offset < data.count {
            guard data.count - offset >= 8 else { throw ListenError.message("Incomplete MP4 box.") }
            let size = try number(data, offset..<offset+4)
            let header = size == 1 ? 16 : 8
            let rawLength = size == 1 ? try number(data, offset+8..<offset+16) : (size == 0 ? UInt64(data.count-offset) : size)
            guard rawLength <= UInt64(data.count-offset), rawLength >= UInt64(header) else { throw ListenError.message("Invalid MP4 box length.") }
            let length = Int(rawLength)
            result.append(Box(type: String(data: data[offset+4..<offset+8], encoding: .ascii) ?? "", start: offset, length: length, header: header)); offset += length
        }
        return result
    }
    static func atom(_ type: String, _ payload: Data) throws -> Data {
        guard payload.count <= Int(UInt32.max)-8 else { throw ListenError.message("MP4 metadata is too large.") }
        return bytes(UInt64(payload.count+8), count: 4) + Data(type.utf8) + payload
    }
    static func chapterAtom(_ chapters: [Chapter]) throws -> Data {
        guard !chapters.isEmpty, chapters.count <= 255 else { throw ListenError.message("M4B conversion supports 1–255 chapters. Original audio is preserved.") }
        var payload = Data([1,0,0,0,0,0,0,0,UInt8(chapters.count)])
        for chapter in chapters {
            guard chapter.start.isFinite, chapter.start >= 0, chapter.start < Double(UInt64.max)/10_000_000 else { throw ListenError.message("Invalid chapter time.") }
            var title = chapter.title
            while title.utf8.count > 255 { title.removeLast() }
            payload += bytes(UInt64(chapter.start*10_000_000), count: 8)
            payload.append(UInt8(title.utf8.count)); payload += Data(title.utf8)
        }
        return try atom("chpl", payload)
    }
    static func addingChapters(_ data: Data, chapters: [Chapter]) throws -> Data {
        let marker = try chapterAtom(chapters)
        var result = Data(); var found = false
        for box in try boxes(data) {
            let payload = Data(data[box.start+box.header..<box.start+box.length])
            if box.type == "udta" {
                var children = Data()
                for child in try boxes(payload) where child.type != "chpl" { children += payload[child.start..<child.start+child.length] }
                result += try atom("udta", children + marker); found = true
            } else { result += data[box.start..<box.start+box.length] }
        }
        if !found { result += try atom("udta", marker) }
        return result
    }
    static func patchOffsets(_ data: Data, threshold: UInt64, delta: UInt64) throws -> Data {
        var result = Data()
        for box in try boxes(data) {
            var payload = Data(data[box.start+box.header..<box.start+box.length])
            if ["trak","mdia","minf","stbl"].contains(box.type) {
                payload = try patchOffsets(payload, threshold: threshold, delta: delta)
            } else if box.type == "stco" || box.type == "co64" {
                let count = try number(payload, 4..<8); let width = box.type == "stco" ? 4 : 8
                guard count <= UInt64(max(0,payload.count-8)/width) else { throw ListenError.message("Invalid MP4 offset table.") }
                for i in 0..<Int(count) {
                    let start = 8+i*width; let old = try number(payload, start..<start+width)
                    if old >= threshold {
                        let (new, overflow) = old.addingReportingOverflow(delta)
                        guard !overflow, width == 8 || new <= UInt32.max else { throw ListenError.message("The audiobook is too large for this MP4 offset format.") }
                        payload.replaceSubrange(start..<start+width, with: bytes(new, count: width))
                    }
                }
            }
            result += try atom(box.type, payload)
        }
        return result
    }
    static func read(from input: URL) throws -> [Chapter] {
        let reader = try FileHandle(forReadingFrom: input); defer { try? reader.close() }
        let total = try reader.seekToEnd(); var offset: UInt64 = 0
        while offset < total {
            try reader.seek(toOffset: offset)
            guard let header = try reader.read(upToCount: 16), header.count >= 8 else { return [] }
            let size = try number(header, 0..<4)
            let length = size == 1 ? try number(header, 8..<16) : (size == 0 ? total-offset : size)
            let headerSize: UInt64 = size == 1 ? 16 : 8
            guard length >= headerSize, length <= total-offset else { return [] }
            if String(data:header[4..<8],encoding:.ascii) == "moov" {
                guard length < 64_000_000 else { return [] }
                try reader.seek(toOffset:offset+headerSize)
                guard let data = try reader.read(upToCount:Int(length-headerSize)) else { return [] }
                for box in try boxes(data) where box.type == "udta" {
                    let children = Data(data[box.start+box.header..<box.start+box.length])
                    for child in try boxes(children) where child.type == "chpl" {
                        let payload = Data(children[child.start+child.header..<child.start+child.length])
                        guard payload.count >= 9 else { return [] }
                        var cursor = 9; var result: [Chapter] = []
                        for _ in 0..<Int(payload[8]) {
                            guard cursor+9 <= payload.count else { throw ListenError.message("Invalid chapter marker.") }
                            let start = Double(try number(payload,cursor..<cursor+8))/10_000_000
                            let count = Int(payload[cursor+8]); cursor += 9
                            guard cursor+count <= payload.count else { throw ListenError.message("Invalid chapter title.") }
                            result.append(Chapter(title:String(decoding:payload[cursor..<cursor+count],as:UTF8.self),start:start)); cursor += count
                        }
                        return result
                    }
                }
                return []
            }
            offset += length
        }
        return []
    }
    static func write(chapters: [Chapter], input: URL, output: URL) throws {
        let reader = try FileHandle(forReadingFrom: input); defer { try? reader.close() }
        let total = try reader.seekToEnd(); try reader.seek(toOffset: 0)
        var moovOffset: UInt64?; var moovSize: UInt64 = 0; var moovHeader = 8
        var offset: UInt64 = 0
        while offset < total {
            try reader.seek(toOffset: offset)
            guard let header = try reader.read(upToCount: 16), header.count >= 8 else { throw ListenError.message("Invalid exported MP4.") }
            let size = try number(header, 0..<4); let type = String(data: header[4..<8], encoding: .ascii)
            let length = size == 1 ? try number(header, 8..<16) : (size == 0 ? total-offset : size)
            guard length >= (size == 1 ? 16 : 8), length <= total-offset else { throw ListenError.message("Invalid exported MP4 length.") }
            if type == "moov" { moovOffset = offset; moovSize = length; moovHeader = size == 1 ? 16 : 8; break }
            offset += length
        }
        guard let position = moovOffset, moovSize < 64_000_000 else { throw ListenError.message("The exported MP4 has no usable metadata index.") }
        try reader.seek(toOffset: position + UInt64(moovHeader))
        guard let moov = try reader.read(upToCount: Int(moovSize)-moovHeader) else { throw ListenError.message("Could not read MP4 metadata.") }
        var replacement = try atom("moov", addingChapters(moov, chapters: chapters))
        guard UInt64(replacement.count) >= moovSize else { throw ListenError.message("Unexpected MP4 index layout.") }
        replacement = try atom("moov", patchOffsets(Data(replacement.dropFirst(8)), threshold: position+moovSize, delta: UInt64(replacement.count)-moovSize))
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let writer = try FileHandle(forWritingTo: output); defer { try? writer.close() }
        func copy(_ start: UInt64, _ count: UInt64) throws {
            try reader.seek(toOffset: start); var remaining = count
            while remaining > 0 {
                guard let chunk = try reader.read(upToCount: Int(min(remaining, 1_048_576))), !chunk.isEmpty else { throw ListenError.message("The audio ended unexpectedly.") }
                try writer.write(contentsOf: chunk); remaining -= UInt64(chunk.count)
            }
        }
        do { try copy(0, position); try writer.write(contentsOf: replacement); try copy(position+moovSize, total-position-moovSize); try writer.synchronize() }
        catch { try? FileManager.default.removeItem(at: output); throw error }
    }
}
