import SwiftUI

struct SettingsView:View {
    @EnvironmentObject var cloud:CloudLibrary
    @EnvironmentObject var goodreads:GoodreadsConnection
    @AppStorage("automaticMetadata") private var metadata=true
    @AppStorage("automaticConversion") private var conversion=false
    @AppStorage("smartRewind") private var rewind=true
    @AppStorage("appearance") private var appearance="system"
    @State private var disconnect=false
    var body:some View {
        NavigationStack {
            Form {
                Section("Library & iCloud"){
                    Toggle("Sync books and listening progress",isOn:$cloud.enabled).onChange(of:cloud.enabled){_,_ in Task{await cloud.sync()}}
                    Text(cloud.status).font(.footnote).foregroundStyle(.secondary)
                    Button("Sync now",systemImage:"arrow.triangle.2.circlepath"){Task{await cloud.sync()}}.disabled(cloud.syncing || !cloud.enabled)
                    Text("Books download before playback and remain available offline. Signed builds need an enabled iCloud container. This app’s iCloud library is separate from your Mac’s existing audiobook folder; use Files to import from it.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Imports & metadata"){
                    Toggle("Find metadata and covers automatically",isOn:$metadata)
                    Text("Uses embedded tags first, then sends the title and known author to Apple Books Search. Audio is never uploaded for metadata. Only confident title/author matches are applied.").font(.footnote).foregroundStyle(.secondary)
                    Toggle("Convert imported MP3 books to M4B",isOn:$conversion)
                    Text("Conversion produces AAC audio with chapter markers. MP3-to-AAC is lossy and needs extra storage. Original imported files are kept. Leave off to play MP3 directly, or convert any book later.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Playback"){
                    Toggle("Smart rewind after a pause",isOn:$rewind)
                    Text("Rewinds 10 seconds after pauses longer than 10 seconds. Speed, sleep timer, chapters, bookmarks, and AirPlay are in the player.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Appearance"){
                    Picker("Appearance",selection:$appearance){Text("Follow system").tag("system");Text("Light").tag("light");Text("Dark").tag("dark")}
                }
                Section("Goodreads"){
                    Text("An independent in-app website session. Goodreads may expire your login or change its pages; CSV import remains available. No Goodreads password or cookie is shared through iCloud.").font(.footnote).foregroundStyle(.secondary)
                    Button("Disconnect Goodreads",role:.destructive){disconnect=true}.disabled(goodreads.books.isEmpty && goodreads.profileID==nil)
                }
                Section("About listen."){
                    LabeledContent("Version",value:"0.1.0 · iOS preview")
                    Text("Part of dot.").font(.headline)
                    Text("A quieter way to read, listen, and learn.").foregroundStyle(.secondary)
                    Link("Source & setup",destination:URL(string:"https://github.com/Somamill/listen")!)
                    Text("For DRM-free audio you have permission to use. No torrent client, torrent catalog, advertising, or analytics is included.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings").confirmationDialog("Disconnect Goodreads on this device?",isPresented:$disconnect,titleVisibility:.visible){Button("Disconnect",role:.destructive){goodreads.disconnect()}}
        }
    }
}
