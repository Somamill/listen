import SwiftUI
import AVKit

struct PlayerView: View {
    var onDone: () -> Void = {}
    @EnvironmentObject var player: AudioController
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var chapters = false
    @State private var bookmarks = false
    @State private var scrub: Double?
    @State private var bookmarked = false
    var body: some View {
        Group {
            if let book = player.book {
                ScrollView {
                    VStack(spacing: sizeClass == .compact ? 16 : 24) {
                        BookArtwork(book: book,root:store.root).frame(maxWidth: sizeClass == .compact ? 220 : 320).aspectRatio(1,contentMode:.fit)
                        VStack(spacing:8) { Text(book.title).font(.title.weight(.bold)).multilineTextAlignment(.center); Text(book.author).foregroundStyle(.secondary) }
                        if let current = book.chapters.last(where: { $0.start <= player.position }) { Text(current.title).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                        VStack {
                            Slider(value: Binding(get:{scrub ?? player.position},set:{scrub=$0}),in:0...max(1,book.duration),onEditingChanged:{editing in if !editing,let value=scrub {player.seek(value);scrub=nil}}).accessibilityLabel("Playback position")
                            HStack { Text(timeLabel(scrub ?? player.position)); Spacer(); Text("−"+timeLabel(max(0,book.duration-(scrub ?? player.position)))) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        HStack(spacing:32) {
                            Button {player.skip(-15)} label:{Image(systemName:"gobackward.15").font(.title).frame(width:48,height:48)}.accessibilityLabel("Rewind 15 seconds")
                            Button {player.toggle()} label:{Image(systemName:player.playing ? "pause.circle.fill":"play.circle.fill").font(.system(size:72)).frame(minWidth:80,minHeight:80)}.accessibilityLabel(player.playing ? "Pause":"Play").accessibilityIdentifier("playerPlayPause")
                            Button {player.skip(30)} label:{Image(systemName:"goforward.30").font(.title).frame(width:48,height:48)}.accessibilityLabel("Forward 30 seconds")
                        }.buttonStyle(.plain)
                        HStack {
                            Menu {
                                ForEach([0.5,0.75,1,1.25,1.5,1.75,2,2.5,3],id:\.self) { speed in Button("\(speed.formatted())×") {player.rate=Float(speed)} }
                            } label:{Text("\(Double(player.rate).formatted())×").font(.headline).frame(minWidth:44,minHeight:44)}.accessibilityLabel("Playback speed")
                            Spacer()
                            Menu {
                                ForEach([15,30,45,60],id:\.self){minutes in Button("\(minutes) minutes"){player.sleepUntil=Date().addingTimeInterval(Double(minutes*60));player.sleepChapterEnd=nil}}
                                if let end=Optional(book.chapters.first(where:{$0.start>player.position})?.start ?? book.duration) { Button("End of chapter"){player.sleepChapterEnd=end;player.sleepUntil=nil} }
                                Button("Turn off",role:.cancel){player.sleepUntil=nil;player.sleepChapterEnd=nil}
                            } label:{Image(systemName:"moon.zzz").font(.title3).frame(width:44,height:44)}.accessibilityLabel("Sleep timer")
                            Spacer()
                            Button {player.bookmark();bookmarked=true} label:{Image(systemName:"bookmark").font(.title3).frame(width:44,height:44)}.accessibilityLabel("Add bookmark").accessibilityIdentifier("addBookmark")
                            Spacer()
                            AirPlayRoutePicker().frame(width:44,height:44).accessibilityLabel("Audio output")
                        }
                        if bookmarked {Text("Bookmark saved").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("bookmarkSaved")}
                        if let until=player.sleepUntil {Text("Sleep timer ends \(until.formatted(date:.omitted,time:.shortened))").font(.footnote).foregroundStyle(.secondary)}
                        if player.sleepChapterEnd != nil {Text("Sleep timer: end of chapter").font(.footnote).foregroundStyle(.secondary)}
                        HStack {
                            Button("Chapters",systemImage:"list.bullet"){chapters=true}.frame(minHeight:44)
                            Spacer()
                            Button("Bookmarks (\(book.bookmarks.count))",systemImage:"bookmark"){bookmarks=true}.frame(minHeight:44)
                        }
                    }.padding(24).frame(maxWidth:560).frame(maxWidth:.infinity)
                }.background(ListenTheme.background)
                .sheet(isPresented:$chapters){NavigationStack{List(book.chapters){chapter in Button{player.seek(chapter.start);chapters=false}label:{HStack{Text(chapter.title);Spacer();Text(timeLabel(chapter.start)).foregroundStyle(.secondary)}}}.navigationTitle("Chapters").toolbar{Button("Done"){chapters=false}}}}
                .sheet(isPresented:$bookmarks){NavigationStack{List{ForEach(book.bookmarks){mark in Button{player.seek(mark.position);bookmarks=false}label:{Label(mark.note,systemImage:"bookmark")}}.onDelete{indexes in var changed=book;changed.bookmarks.remove(atOffsets:indexes);changed.metadataUpdatedAt=Date();store.update(changed)}}.navigationTitle("Bookmarks").toolbar{Button("Done"){bookmarks=false}}}}
            } else {ContentUnavailableView("Choose an audiobook",systemImage:"headphones")}
        }.navigationTitle("Now listening").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){onDone();dismiss()}.accessibilityIdentifier("closePlayer")}}
    }
}
struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context:Context)->AVRoutePickerView {let view=AVRoutePickerView();view.prioritizesVideoDevices=false;return view}
    func updateUIView(_ uiView:AVRoutePickerView,context:Context){}
}
