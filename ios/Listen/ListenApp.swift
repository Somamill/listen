import SwiftUI

@main @MainActor struct ListenApp: App {
    @StateObject private var store: LibraryStore
    @StateObject private var cloud: CloudLibrary
    @StateObject private var player: AudioController
    @StateObject private var goodreads: GoodreadsConnection
    @Environment(\.scenePhase) private var phase
    @AppStorage("appearance") private var appearance = "system"
    init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
        let root = testing ? FileManager.default.temporaryDirectory.appendingPathComponent("listen-ui-tests") : nil
        if testing { try? FileManager.default.removeItem(at: root!); UserDefaults.standard.set(false, forKey: "cloudEnabled") }
        let library = LibraryStore(root: root); let sync = CloudLibrary(store: library)
        _store = StateObject(wrappedValue: library); _cloud = StateObject(wrappedValue: sync)
        _player = StateObject(wrappedValue: AudioController(store: library, cloud: sync)); _goodreads = StateObject(wrappedValue: GoodreadsConnection())
        if testing, let sample = Bundle.main.url(forResource: "Sample", withExtension: "mp3") {
            Task { await library.importFiles([sample], enrich: false) }
        }
    }
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).environmentObject(cloud).environmentObject(player).environmentObject(goodreads)
                .tint(ListenTheme.accent).preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
                .task { await cloud.sync() }
                .onChange(of: phase) { _, next in
                    if next == .active { Task { await cloud.sync() }; if goodreads.profileID != nil { goodreads.refresh() } }
                    else { player.persist(); cloud.schedule() }
                }
                .onOpenURL { url in Task { await store.importFiles([url], enrich: UserDefaults.standard.object(forKey: "automaticMetadata") as? Bool ?? true) } }
        }
    }
}
