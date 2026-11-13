import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct GoodreadsView: View {
    @EnvironmentObject var goodreads:GoodreadsConnection
    @EnvironmentObject var store:LibraryStore
    @State private var shelf="to-read"
    @State private var csv=false
    @State private var profile=""
    private let shelves=[("to-read","Want to Read"),("currently-reading","Currently Reading"),("read","Read"),("did-not-finish","Did Not Finish")]
    var body:some View {
        NavigationStack {
            List {
                Section {
                    Text(goodreads.status).font(.subheadline).foregroundStyle(.secondary)
                    Button(goodreads.profileID == nil ? "Connect Goodreads":"Open Goodreads connection",systemImage:"person.crop.circle.badge.checkmark"){goodreads.connect()}.accessibilityIdentifier("connectGoodreads")
                    if goodreads.profileID != nil {Button("Refresh shelves",systemImage:"arrow.clockwise"){goodreads.refresh()}.disabled(goodreads.refreshing)}
                    DisclosureGroup("Other ways to bring your shelves") {
                        TextField("Goodreads profile or My Books link",text:$profile).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        Button("Connect profile link"){goodreads.setProfile(profile)}.disabled(profile.isEmpty)
                        Button("Import Goodreads CSV",systemImage:"doc"){csv=true}
                        Text("CSV is a saved snapshot. The in-app website connection refreshes while listen. is open. Sign-in and reading history stay on this device.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if !goodreads.books.isEmpty {
                    Section {
                        Picker("Reading shelf",selection:$shelf){ForEach(shelves,id:\.0){item in Text(item.1).tag(item.0)}}.accessibilityIdentifier("readingShelf")
                    }
                    Section(shelves.first(where:{$0.0==shelf})?.1 ?? "Shelf") {
                        let rows=goodreads.books.filter{$0.shelf==shelf}
                        if rows.isEmpty {Text("No saved books on this shelf.").foregroundStyle(.secondary)}
                        ForEach(rows){book in
                            VStack(alignment:.leading,spacing:8){
                                HStack(alignment:.top,spacing:12){
                                    AsyncImage(url:book.cover.flatMap(URL.init(string:))){image in image.resizable().scaledToFit()}placeholder:{Image(systemName:"book.closed").foregroundStyle(ListenTheme.accent)}.frame(width:48,height:64).accessibilityHidden(true)
                                    VStack(alignment:.leading,spacing:4){Text(book.title).font(.headline);Text(book.author).font(.subheadline).foregroundStyle(.secondary)}
                                }
                                if let local=store.books.first(where:{MetadataService.confidence($0.title,book.title)>0.65}){NavigationLink("Possible library match",value:local.id)}
                                if let url=URL(string:book.url),url.scheme=="https",url.host?.hasSuffix("goodreads.com")==true{Link("View on Goodreads",destination:url)}
                            }.padding(.vertical,8)
                        }
                    }
                } else {
                    Section {Text("Want to Read, Currently Reading, Read, and Did Not Finish stay separate. Your audiobook listening progress syncs through iCloud; Goodreads reading status is not changed automatically.").foregroundStyle(.secondary)}
                }
            }.navigationTitle("Goodreads").navigationDestination(for:UUID.self){BookDetail(bookID:$0)}
                .sheet(isPresented:$goodreads.showSignIn){NavigationStack{GoodreadsWebsite(connection:goodreads).navigationTitle("Goodreads").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){goodreads.showSignIn=false;goodreads.refresh()}}}}}
                .fileImporter(isPresented:$csv,allowedContentTypes:[.commaSeparatedText],allowsMultipleSelection:false){result in if case let .success(urls)=result,let url=urls.first{goodreads.importCSV(url)}}
        }
    }
}
struct GoodreadsWebsite:UIViewRepresentable {
    @ObservedObject var connection:GoodreadsConnection
    func makeUIView(context:Context)->WKWebView{connection.webView}
    func updateUIView(_ uiView:WKWebView,context:Context){}
}
