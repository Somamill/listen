import AVFoundation
import MediaPlayer
import Combine
import UIKit

@MainActor final class AudioController: ObservableObject {
    @Published var bookID: UUID?
    @Published var playing = false
    @Published var position: Double = 0
    @Published var loading = false
    @Published var rate: Float = 1 { didSet { UserDefaults.standard.set(rate, forKey: "playbackRate"); if playing { player?.rate = rate }; nowPlaying() } }
    @Published var sleepUntil: Date?
    @Published var sleepChapterEnd: Double?
    private(set) var player: AVPlayer?
    private var observer: Any?
    private var completion: NSObjectProtocol?
    private var lastSave = Date.distantPast
    private var pausedAt: Date?
    private var index = 0
    private let store: LibraryStore
    private let cloud: CloudLibrary
    var book: AudioBook? { store.books.first { $0.id == bookID } }
    init(store: LibraryStore, cloud: CloudLibrary) {
        self.store = store; self.cloud = cloud
        rate = (UserDefaults.standard.object(forKey: "playbackRate") as? Float) ?? 1
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            Task { @MainActor in
                if type == AVAudioSession.InterruptionType.began.rawValue { self?.pause() }
            }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            if note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { Task { @MainActor in self?.pause() } }
        }
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        commands.skipForwardCommand.preferredIntervals = [30]
        commands.skipBackwardCommand.preferredIntervals = [15]
        commands.skipForwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(30) }; return .success }
        commands.skipBackwardCommand.addTarget { [weak self] _ in Task { @MainActor in self?.skip(-15) }; return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(event.positionTime) }; return .success
        }
    }
    func open(_ book: AudioBook, autoplay: Bool = true) async {
        guard !loading else { return }
        pause(); loading = true; defer { loading = false }
        do {
            if book.tracks.contains(where: { !FileManager.default.fileExists(atPath: store.file(book, $0).path) }) { try await cloud.download(book) }
            bookID = book.id; position = book.state.finished ? 0 : book.state.position
            if book.state.finished && autoplay { store.position(book.id, seconds: 0, finished: false) }
            try await Self.activateSession()
            loadTrack(at: position, autoplay: autoplay)
        } catch { store.error = error.localizedDescription }
    }
    private func loadTrack(at absolute: Double, autoplay: Bool) {
        guard let book else { return }
        if let observer { player?.removeTimeObserver(observer); self.observer = nil }
        if let completion { NotificationCenter.default.removeObserver(completion) }
        player?.pause()
        let track = book.trackPosition(at: absolute); index = track.index
        guard book.tracks.indices.contains(index) else { return }
        let item = AVPlayerItem(url: store.file(book, book.tracks[index])); item.audioTimePitchAlgorithm = .spectral
        player = AVPlayer(playerItem: item)
        player?.seek(to: CMTime(seconds: track.offset, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        observer = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        completion = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in Task { @MainActor in self?.ended() } }
        position = absolute; playing = autoplay; cloud.activeBookID = autoplay ? bookID : nil
        if autoplay { player?.playImmediately(atRate: rate) }; nowPlaying()
    }
    func tick() {
        guard let book, let player else { return }
        let current = player.currentTime().seconds
        if current.isFinite { position = min(book.duration, book.offset(for: index) + current) }
        if (sleepUntil.map { Date() >= $0 } ?? false) || (sleepChapterEnd.map { position >= $0 } ?? false) { sleepUntil = nil; sleepChapterEnd = nil; pause(); return }
        if playing && Date().timeIntervalSince(lastSave) >= 10 { persist() }
        if player.currentItem?.status == .failed { pause(); store.error = player.currentItem?.error?.localizedDescription ?? "Playback could not start." }
        nowPlaying()
    }
    func persist() {
        if let bookID { store.position(bookID, seconds: position) }; lastSave = Date()
    }
    func pause() { player?.pause(); playing = false; pausedAt = Date(); cloud.activeBookID = nil; persist(); nowPlaying() }
    nonisolated static func activateSession() async throws {
        try await Task.detached {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay,.allowBluetoothA2DP])
        }.value
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
                AVAudioSession.sharedInstance().activate(options: []) { active, error in
                    if let error { continuation.resume(throwing: error) }
                    else if active { continuation.resume() }
                    else { continuation.resume(throwing: ListenError.message("An audio output is not available.")) }
                }
            }
        } else { try await Task.detached { try AVAudioSession.sharedInstance().setActive(true) }.value }
        #else
        try await Task.detached { try AVAudioSession.sharedInstance().setActive(true) }.value
        #endif
    }
    func resume() {
        guard player != nil, !loading else { return }
        loading = true
        Task {
            defer { loading = false }
            do {
                try await Self.activateSession()
                if let book, book.state.updatedAt > lastSave { loadTrack(at: book.state.position, autoplay: true); return }
                if UserDefaults.standard.object(forKey: "smartRewind") as? Bool ?? true, let pausedAt, Date().timeIntervalSince(pausedAt) > 10 { seek(max(0, position-10)) }
                pausedAt = nil; player?.playImmediately(atRate: rate); playing = true; cloud.activeBookID = bookID; nowPlaying()
            } catch { store.error = error.localizedDescription }
        }
    }
    func toggle() { playing ? pause() : resume() }
    func seek(_ value: Double) {
        guard let book else { return }
        let value = max(0,min(value,book.duration)); let track = book.trackPosition(at: value)
        if track.index != index { loadTrack(at: value, autoplay: playing) }
        else { player?.seek(to: CMTime(seconds: track.offset, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero); position = value }
        persist(); nowPlaying()
    }
    func skip(_ interval: Double) { seek(position+interval) }
    private func ended() {
        guard let book else { return }
        if index+1 < book.tracks.count { loadTrack(at: book.offset(for: index+1), autoplay: true) }
        else {
            pause(); position = book.duration; store.position(book.id, seconds: position, finished: true)
            if sleepUntil != nil || sleepChapterEnd != nil { sleepUntil = nil; sleepChapterEnd = nil; return }
            if !book.folder.isEmpty, let next = store.books.first(where: { $0.folder == book.folder && $0.id != book.id && !$0.state.finished }) { Task { await open(next) } }
        }
    }
    func bookmark() {
        guard var book else { return }; book.bookmarks.append(Bookmark(position: position, note: timeLabel(position))); book.metadataUpdatedAt = Date(); store.update(book)
    }
    private func nowPlaying() {
        guard let book else { return }
        var info: [String:Any] = [MPMediaItemPropertyTitle:book.title, MPMediaItemPropertyArtist:book.author,MPMediaItemPropertyPlaybackDuration:book.duration,MPNowPlayingInfoPropertyElapsedPlaybackTime:position,MPNowPlayingInfoPropertyPlaybackRate:playing ? rate : 0,MPNowPlayingInfoPropertyDefaultPlaybackRate:rate]
        if let filename = book.coverFilename, let image = UIImage(contentsOfFile: store.directory(book).appendingPathComponent(filename).path) { info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image } }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
