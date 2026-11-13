import SwiftUI
import WidgetKit

struct ListeningEntry: TimelineEntry {
  let date: Date
  let snapshot: CompanionSnapshot?
}
struct ListeningProvider: TimelineProvider {
  func placeholder(in context: Context) -> ListeningEntry {
    ListeningEntry(date: Date(), snapshot: nil)
  }
  func getSnapshot(in context: Context, completion: @escaping (ListeningEntry) -> Void) {
    completion(ListeningEntry(date: Date(), snapshot: CompanionStorage.read()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<ListeningEntry>) -> Void) {
    completion(
      Timeline(
        entries: [ListeningEntry(date: Date(), snapshot: CompanionStorage.read())],
        policy: .after(Date().addingTimeInterval(900))))
  }
}
struct ListeningWidgetView: View {
  var entry: ListeningEntry
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("listen.", systemImage: "headphones").font(.caption.weight(.semibold))
      if let book = entry.snapshot {
        Text(book.title).font(.headline).lineLimit(2)
        Text(book.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        ProgressView(value: min(1, max(0, book.progress))).accessibilityLabel("Listening progress")
        Label("Continue listening", systemImage: "play.fill").font(.caption)
      } else {
        Text("Your next chapter.").font(.headline)
        Text("Open listen. and choose a book.").font(.caption).foregroundStyle(.secondary)
      }
    }.containerBackground(.fill.tertiary, for: .widget)
      .widgetURL(
        URL(
          string: entry.snapshot.map { "listen-mobile://book/\($0.bookID.uuidString)" }
            ?? "listen-mobile://continue"))
  }
}
@main struct ListenWidget: Widget {
  let kind = "listen.continue-listening"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: ListeningProvider()) {
      ListeningWidgetView(entry: $0)
    }.configurationDisplayName("Continue listening").description("Return to your latest audiobook.")
      .supportedFamilies([.systemSmall, .systemMedium])
  }
}
