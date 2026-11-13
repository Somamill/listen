import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
  @EnvironmentObject var store: LibraryStore
  @EnvironmentObject var player: AudioController
  @State private var showPlayer = false
  var body: some View {
    TabView {
      LibraryView().tabItem { Label("Library", systemImage: "books.vertical") }
      GoodreadsView().tabItem { Label("Goodreads", systemImage: "book.closed") }
      MediaServersView().tabItem { Label("Servers", systemImage: "externaldrive") }
      SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if let book = player.book {
        HStack(spacing: 12) {
          Button {
            showPlayer = true
          } label: {
            HStack {
              BookArtwork(book: book, root: store.root).frame(width: 44, height: 52)
              VStack(alignment: .leading) {
                Text(book.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(book.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
              }
              Spacer()
            }.contentShape(Rectangle())
          }.buttonStyle(.plain).accessibilityLabel("Open player for \(book.title)")
          Button {
            player.toggle()
          } label: {
            Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(
              width: 44, height: 44)
          }.accessibilityLabel(player.playing ? "Pause" : "Play").accessibilityIdentifier(
            "miniPlayPause")
        }.padding(.horizontal).padding(.vertical, 8).background(.regularMaterial)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("listen.show-player"))) {
      _ in showPlayer = true
    }
    .sheet(isPresented: $showPlayer) {
      NavigationStack { PlayerView(onDone: { showPlayer = false }) }
    }
    .alert(
      "Something needs attention",
      isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
    ) {
      Button("OK") { store.error = nil }
    } message: {
      Text(store.error ?? "")
    }
  }
}

struct LibraryView: View {
  @EnvironmentObject var store: LibraryStore
  @EnvironmentObject var player: AudioController
  @EnvironmentObject var cloud: CloudLibrary
  @AppStorage("automaticMetadata") private var automaticMetadata = true
  @AppStorage("automaticConversion") private var automaticConversion = false
  @State private var showImport = false
  @State private var showFolderImport = false
  @State private var combine = true
  @State private var search = ""
  @State private var shelf = "All"
  @State private var selected: UUID?
  @State private var selectedFolder: String?
  @State private var showFolders = false
  @State private var showQueue = false
  @State private var showActivity = false
  @State private var showBrowserTransfer = false
  @State private var showDownload = false
  @AppStorage("librarySort") private var sortOrder = "manual"
  @AppStorage("reverseSort") private var reverseSort = false
  var filtered: [AudioBook] {
    let result = store.books.filter { book in
      (selectedFolder == nil || book.folder == selectedFolder
        || book.folder.hasPrefix(selectedFolder! + "/"))
        && (search.isEmpty
          || (book.title + " " + book.author).localizedCaseInsensitiveContains(search))
        && (shelf == "All" || (shelf == "Finished" ? book.state.finished : !book.state.finished))
    }
    let sorted = result.sorted { a, b in
      switch sortOrder {
      case "title": return a.title.localizedStandardCompare(b.title) == .orderedAscending
      case "author": return a.author.localizedStandardCompare(b.author) == .orderedAscending
      case "recent": return a.createdAt > b.createdAt
      case "played": return a.state.updatedAt > b.state.updatedAt
      case "duration": return a.duration < b.duration
      case "filename":
        return (a.tracks.first?.filename ?? "").localizedStandardCompare(
          b.tracks.first?.filename ?? "") == .orderedAscending
      default: return false
      }
    }
    let chosen = sortOrder == "manual" ? result : sorted
    return reverseSort ? chosen.reversed() : chosen
  }
  var body: some View {
    NavigationSplitView {
      Group {
        if store.books.isEmpty {
          ContentUnavailableView {
            Label("Your next chapter starts here.", systemImage: "books.vertical")
          } description: {
            Text(
              "Bring your DRM-free audiobooks from Files or iCloud Drive. Your listening place stays with you."
            )
          } actions: {
            Button("Import audiobooks", systemImage: "plus") { showImport = true }.buttonStyle(
              .borderedProminent
            ).accessibilityIdentifier("emptyImport")
          }
        } else {
          List(selection: $selected) {
            Picker("Library shelf", selection: $shelf) {
              ForEach(["All", "Listening", "Finished"], id: \.self) { Text($0) }
            }.pickerStyle(.segmented).listRowSeparator(.hidden)
            if let selectedFolder {
              Label(selectedFolder, systemImage: "folder")
              Button("Show all folders") { self.selectedFolder = nil }
            }
            if store.waitingImports > 0 {
              Text("\(store.waitingImports) import(s) waiting").font(.footnote).foregroundStyle(
                .secondary)
            }
            if store.busy {
              HStack {
                ProgressView()
                Text(store.activity.isEmpty ? "Working…" : store.activity).font(.subheadline)
              }
            }
            if let notice = store.notice {
              Text(notice).font(.footnote).foregroundStyle(.secondary)
            }
            if filtered.isEmpty { ContentUnavailableView.search(text: search) }
            ForEach(filtered) { book in
              NavigationLink(value: book.id) { BookRow(book: book) }
                .accessibilityIdentifier("book-\(book.title)")
                .contextMenu {
                  Button(
                    book.state.finished ? "Mark unfinished" : "Mark finished",
                    systemImage: "checkmark.circle"
                  ) {
                    store.position(
                      book.id, seconds: book.state.position, finished: !book.state.finished)
                  }
                  Button("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    player.enqueue(book.id, next: true)
                  }
                  Button("Add to queue", systemImage: "text.badge.plus") { player.enqueue(book.id) }
                  Button("Play", systemImage: "play") {
                    Task { await player.open(book) }
                    selected = book.id
                  }
                }
            }.onMove { source, destination in
              guard search.isEmpty, shelf == "All", selectedFolder == nil, sortOrder == "manual",
                !reverseSort
              else { return }
              store.books.move(fromOffsets: source, toOffset: destination)
              store.save()
            }.moveDisabled(
              !search.isEmpty || shelf != "All" || selectedFolder != nil || sortOrder != "manual"
                || reverseSort)
          }.listStyle(.plain).scrollContentBackground(.hidden)
        }
      }
      .background(ListenTheme.background).navigationTitle("listen.")
      .searchable(text: $search, prompt: "Title or author")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Menu {
            Button("Import audio files", systemImage: "doc.badge.plus") { showImport = true }
            Button("Import a folder", systemImage: "folder.badge.plus") { showFolderImport = true }
            Button("Transfer from browser", systemImage: "wifi") { showBrowserTransfer = true }
            Button("Download a file", systemImage: "arrow.down.circle") { showDownload = true }
            Toggle("Combine selected files into one book", isOn: $combine)
          } label: {
            Image(systemName: "plus")
          }.accessibilityLabel("Import audiobooks").accessibilityIdentifier("importMenu")
        }
        ToolbarItem(placement: .secondaryAction) {
          Menu {
            Button("Folders", systemImage: "folder") { showFolders = true }
            Button("Up next", systemImage: "list.bullet") { showQueue = true }
            Button("Listening history", systemImage: "clock") { showActivity = true }
            Picker("Sort by", selection: $sortOrder) {
              Text("Manual").tag("manual")
              Text("Title").tag("title")
              Text("Author").tag("author")
              Text("Recently added").tag("recent")
              Text("Last played").tag("played")
              Text("Duration").tag("duration")
              Text("Filename").tag("filename")
            }
            Toggle("Reverse order", isOn: $reverseSort)
          } label: {
            Image(systemName: "line.3.horizontal.decrease")
          }.accessibilityLabel("Library options")
        }
        ToolbarItem(placement: .secondaryAction) {
          EditButton().disabled(!search.isEmpty || shelf != "All")
        }
        ToolbarItem(placement: .secondaryAction) {
          Button("Sync iCloud", systemImage: "icloud") { Task { await cloud.sync() } }
        }
      }
      .sheet(isPresented: $showBrowserTransfer) { BrowserTransferView() }
      .sheet(isPresented: $showDownload) { DownloadImportView() }
      .sheet(isPresented: $showFolders) {
        NavigationStack {
          FolderChooser(books: store.books, path: "") {
            selectedFolder = $0
            showFolders = false
          }
        }
      }
      .sheet(isPresented: $showQueue) { PlaybackQueueView() }
      .sheet(isPresented: $showActivity) { ListeningActivityView(activity: player.activity) }
      .fileImporter(
        isPresented: $showImport, allowedContentTypes: [.audio, .zip],
        allowsMultipleSelection: true, onCompletion: importResult
      )
      .fileImporter(
        isPresented: $showFolderImport, allowedContentTypes: [.folder],
        allowsMultipleSelection: false, onCompletion: importResult)
    } detail: {
      if let id = selected, let book = store.books.first(where: { $0.id == id }) {
        BookDetail(bookID: book.id)
      } else {
        ContentUnavailableView(
          "A little time. A whole new world.", systemImage: "headphones",
          description: Text("Choose a book to continue listening."))
      }
    }
  }
  func importResult(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      Task {
        await store.importFiles(
          urls, combine: combine, enrich: automaticMetadata, convert: automaticConversion)
      }
    case .failure(let error):
      if (error as NSError).code != NSUserCancelledError {
        store.error = error.localizedDescription
      }
    }
  }
}
struct BookRow: View {
  @Environment(\.dynamicTypeSize) private var textSize
  let book: AudioBook
  @EnvironmentObject var store: LibraryStore
  var body: some View {
    HStack(spacing: 16) {
      BookArtwork(book: book, root: store.root).frame(width: 60, height: 76)
      VStack(alignment: .leading, spacing: 5) {
        Text(book.title).font(.headline).lineLimit(textSize.isAccessibilitySize ? nil : 2)
        Text(book.author).font(.subheadline).foregroundStyle(.secondary).lineLimit(
          textSize.isAccessibilitySize ? nil : 1)
        if !book.folder.isEmpty {
          Label(book.folder, systemImage: "folder").font(.caption).foregroundStyle(.secondary)
        }
        ProgressView(value: book.progress).accessibilityLabel("Listening progress")
        Text(
          book.state.finished
            ? "Finished" : "\(timeLabel(max(0,book.duration-book.state.position))) remaining"
        ).font(.caption).foregroundStyle(.secondary)
      }
    }.padding(.vertical, 8)
  }
}
struct BookDetail: View {
  let bookID: UUID
  @EnvironmentObject var store: LibraryStore
  @EnvironmentObject var player: AudioController
  @Environment(\.horizontalSizeClass) private var sizeClass
  @State private var edit = false
  @State private var showPlayer = false
  var book: AudioBook? { store.books.first { $0.id == bookID } }
  var body: some View {
    Group {
      if let book {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            BookArtwork(book: book, root: store.root).frame(
              width: sizeClass == .compact ? 240 : 300, height: sizeClass == .compact ? 240 : 300
            ).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 8) {
              Text(book.title).font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
              Text(book.author).font(.title3).foregroundStyle(.secondary)
              if !book.narrator.isEmpty {
                Text("Narrated by \(book.narrator)").foregroundStyle(.secondary)
              }
              Text("\(timeLabel(book.duration)) • \(book.chapters.count) chapters").font(
                .subheadline
              ).foregroundStyle(.secondary)
            }
            Button {
              Task {
                await player.open(book)
                if player.bookID == book.id { showPlayer = true }
              }
            } label: {
              Label(
                player.loading
                  ? "Preparing audio…"
                  : book.state.position > 0 && !book.state.finished
                    ? "Continue listening" : "Start listening", systemImage: "play.fill"
              ).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent).disabled(player.loading || store.busy)
            .accessibilityIdentifier("startListening")
            ProgressView(value: book.progress)
            if book.tracks.count > 1
              || book.tracks.first?.filename.lowercased().hasSuffix(".mp3") == true
            {
              Button("Create M4B audiobook", systemImage: "waveform.badge.plus") {
                Task {
                  if player.bookID == book.id { player.pause() }
                  await store.convert(book)
                  if player.bookID == book.id,
                    let updated = store.books.first(where: { $0.id == book.id })
                  {
                    await player.open(updated, autoplay: false)
                  }
                }
              }.disabled(store.busy)
              Text(
                "Converts to AAC with chapter markers. MP3-to-AAC is lossy. Imported originals are kept."
              ).font(.footnote).foregroundStyle(.secondary)
            }
            if store.busy {
              HStack {
                ProgressView()
                Text(store.activity)
              }
            }
            Button("Find metadata and cover", systemImage: "sparkle.magnifyingglass") {
              Task { await store.enrich(book) }
            }.disabled(store.busy)
            if !book.chapters.isEmpty {
              Text("Chapters").font(.title2.weight(.semibold))
              ForEach(book.chapters) { chapter in
                Button {
                  Task {
                    if player.bookID != book.id { await player.open(book, autoplay: false) }
                    player.seek(chapter.start)
                    player.resume()
                    showPlayer = true
                  }
                } label: {
                  HStack {
                    Text(chapter.title).multilineTextAlignment(.leading)
                    Spacer()
                    Text(timeLabel(chapter.start)).font(.caption).monospacedDigit()
                  }.padding(.vertical, 8)
                }
              }
            }
          }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(ListenTheme.background).navigationTitle("Audiobook")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            Button("Edit", systemImage: "pencil") { edit = true }
            ShareLink(items: book.tracks.map { store.file(book, $0) }) {
              Label("Export audio", systemImage: "square.and.arrow.up")
            }
            .disabled(
              book.tracks.contains {
                !FileManager.default.fileExists(atPath: store.file(book, $0).path)
              })
          }
          .sheet(isPresented: $edit) { EditBookView(book: book) }
          .sheet(isPresented: $showPlayer) {
            NavigationStack { PlayerView(onDone: { showPlayer = false }) }
          }
      } else {
        ContentUnavailableView("Book unavailable", systemImage: "book.closed")
      }
    }
  }
}
struct EditBookView: View {
  @State var book: AudioBook
  @EnvironmentObject var store: LibraryStore
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      Form {
        Section("Book details") {
          TextField("Title", text: $book.title)
          TextField("Author", text: $book.author)
          TextField("Narrator", text: $book.narrator)
        }
        Section("Folder / queue") {
          TextField("Folder path, e.g. Fiction / History", text: $book.folder)
          Text("Unfinished books in the same folder continue in library order.").font(.footnote)
        }
        Section { Toggle("Finished", isOn: $book.state.finished) }
      }.navigationTitle("Edit audiobook").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            do {
              book.folder = try FolderPath.normalize(book.folder)
              book.metadataUpdatedAt = Date()
              book.state.updatedAt = Date()
              store.update(book)
              dismiss()
            } catch { store.error = error.localizedDescription }
          }.disabled(book.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}
