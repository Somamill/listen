import SwiftUI

@main @MainActor struct ListenApp: App {
  @StateObject private var store: LibraryStore
  @StateObject private var cloud: CloudLibrary
  @StateObject private var player: AudioController
  @StateObject private var goodreads: GoodreadsConnection
  @StateObject private var servers: ServerLibrary
  @StateObject private var transfer: LocalTransfer
  @Environment(\.scenePhase) private var phase
  @AppStorage("appearance") private var appearance = "system"
  init() {
    #if DEBUG
    let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
    #else
    let testing = false
    #endif
    let root =
      testing
      ? FileManager.default.temporaryDirectory.appendingPathComponent("listen-ui-tests") : nil
    if testing {
      try? FileManager.default.removeItem(at: root!)
      UserDefaults.standard.set(false, forKey: "cloudEnabled")
    }
    let library = LibraryStore(root: root)
    let sync = CloudLibrary(store: library)
    _store = StateObject(wrappedValue: library)
    _cloud = StateObject(wrappedValue: sync)
    let audio = AudioController(store: library, cloud: sync)
    _player = StateObject(wrappedValue: audio)
    MobileCompanionBridge.store = library
    MobileCompanionBridge.player = audio
    _goodreads = StateObject(wrappedValue: GoodreadsConnection())
    _servers = StateObject(wrappedValue: ServerLibrary(root: library.root))
    _transfer = StateObject(wrappedValue: LocalTransfer())
    if testing, let sample = Bundle.main.url(forResource: "Sample", withExtension: "mp3") {
      Task { await library.importFiles([sample], enrich: false) }
    }
  }
  var body: some Scene {
    WindowGroup {
      RootView().environmentObject(store).environmentObject(cloud).environmentObject(player)
        .environmentObject(goodreads).environmentObject(servers).environmentObject(transfer)
        .tint(ListenTheme.accent).preferredColorScheme(
          appearance == "system" ? nil : appearance == "dark" ? .dark : .light
        )
        .task { await cloud.sync() }
        .onChange(of: phase) { _, next in
          if next == .active {
            Task {
              await cloud.sync()
              await MobileCompanionBridge.importShared(store)
              if UserDefaults.standard.bool(forKey: "intentContinue") {
                UserDefaults.standard.set(false, forKey: "intentContinue")
                await MobileCompanionBridge.open()
              }
            }
            if goodreads.profileID != nil { goodreads.refresh() }
          } else {
            player.persist()
            cloud.schedule()
            if next == .background { transfer.stop() }
          }
        }
        .onOpenURL { url in
          if url.scheme == "listen-mobile" {
            Task {
              await MobileCompanionBridge.open(
                url.host == "book" ? url.pathComponents.last.flatMap(UUID.init(uuidString:)) : nil)
            }
          } else if url.isFileURL {
            Task {
              await store.importFiles(
                [url],
                enrich: UserDefaults.standard.object(forKey: "automaticMetadata") as? Bool ?? true)
            }
          }
        }
    }
  }
}
