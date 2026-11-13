import SwiftUI

struct FolderChooser: View {
  let books: [AudioBook]
  let path: String
  let select: (String?) -> Void
  @Environment(\.dismiss) var dismiss
  var body: some View {
    List {
      Button(path.isEmpty ? "Show all books" : "Show this folder") {
        select(path.isEmpty ? nil : path)
        dismiss()
      }
      ForEach(FolderPath.children(of: path, in: books), id: \.self) { child in
        NavigationLink {
          FolderChooser(books: books, path: child, select: select)
        } label: {
          Label(child.split(separator: "/").last.map(String.init) ?? child, systemImage: "folder")
        }
      }
    }.navigationTitle(
      path.isEmpty ? "Folders" : path.split(separator: "/").last.map(String.init) ?? "Folder")
  }
}
struct PlaybackQueueView: View {
  @EnvironmentObject var player: AudioController
  @EnvironmentObject var store: LibraryStore
  @Environment(\.dismiss) var dismiss
  var body: some View {
    NavigationStack {
      List {
        if player.queue.isEmpty {
          ContentUnavailableView(
            "Nothing queued yet", systemImage: "list.bullet",
            description: Text("Touch and hold a book to choose Play Next or Add to Queue."))
        }
        ForEach(Array(player.queue.enumerated()), id: \.element) { index, id in
          if let book = store.books.first(where: { $0.id == id }) {
            Button {
              player.queue.remove(at: index)
              Task { await player.open(book) }
              dismiss()
            } label: {
              VStack(alignment: .leading) {
                Text(book.title)
                Text(book.author).font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }.onMove { player.queue.move(fromOffsets: $0, toOffset: $1) }.onDelete {
          player.queue.remove(atOffsets: $0)
        }
      }.navigationTitle("Up next").toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        ToolbarItem(placement: .primaryAction) { EditButton() }
        ToolbarItem(placement: .secondaryAction) {
          Button("Shuffle", systemImage: "shuffle") { player.queue.shuffle() }.disabled(
            player.queue.count < 2)
        }
        ToolbarItem(placement: .secondaryAction) {
          Button("Clear", role: .destructive) { player.queue = [] }.disabled(player.queue.isEmpty)
        }
      }
    }
  }
}
struct ListeningActivityView: View {
  @ObservedObject var activity: ListeningActivity
  @EnvironmentObject var store: LibraryStore
  @EnvironmentObject var player: AudioController
  @Environment(\.dismiss) var dismiss
  var body: some View {
    NavigationStack {
      List {
        Section("Listening time") {
          LabeledContent(
            "Today",
            value: timeLabel(activity.snapshot.secondsByDay[ListeningActivity.dayKey(), default: 0])
          )
          LabeledContent(
            "Recorded total", value: timeLabel(activity.snapshot.secondsByDay.values.reduce(0, +)))
          Text("Counts elapsed listening time, not book duration. Stored locally; not analytics.")
            .font(.footnote).foregroundStyle(.secondary)
        }
        Section("Recent recovery points") {
          ForEach(activity.snapshot.events.prefix(100)) { event in
            if let book = store.books.first(where: { $0.id == event.bookID }) {
              Button {
                Task {
                  if player.bookID != book.id { await player.open(book, autoplay: false) }
                  player.seek(event.position)
                }
                dismiss()
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(book.title)
                  Text("\(timeLabel(event.position)) — \(event.kind)").font(.subheadline)
                  Text(event.date.formatted()).font(.caption).foregroundStyle(.secondary)
                }
              }
            }
          }
        }
      }.navigationTitle("Listening history").toolbar { Button("Done") { dismiss() } }
    }
  }
}
struct BookmarkEditor: View {
  let bookID: UUID
  let mark: Bookmark
  @EnvironmentObject var store: LibraryStore
  @Environment(\.dismiss) var dismiss
  @State private var note = ""
  var body: some View {
    NavigationStack {
      Form {
        TextField("Bookmark note", text: $note, axis: .vertical).accessibilityIdentifier("bookmarkNote")
        Text(timeLabel(mark.position)).foregroundStyle(.secondary)
      }.navigationTitle("Bookmark note").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            if var book = store.books.first(where: { $0.id == bookID }),
              let index = book.bookmarks.firstIndex(where: { $0.id == mark.id })
            {
              book.bookmarks[index].note = note
              book.metadataUpdatedAt = Date()
              store.update(book)
            }
            dismiss()
          }
        }
      }.onAppear { note = mark.note }
    }
  }
}
struct SleepTimerEditor: View {
  @EnvironmentObject var player: AudioController
  @Environment(\.dismiss) var dismiss
  @State private var minutes = 30
  var body: some View {
    NavigationStack {
      Form {
        Stepper("\(minutes) minutes", value: $minutes, in: 1...360)
        Text("Playback fades over the last eight seconds when Fade sleep timer is enabled.").font(
          .footnote
        ).foregroundStyle(.secondary)
      }.navigationTitle("Sleep timer").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Start") {
            player.sleep(minutes: minutes)
            dismiss()
          }
        }
      }
    }
  }
}
