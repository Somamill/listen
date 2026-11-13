import Foundation
import WebKit
import Combine

@MainActor final class GoodreadsConnection: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var books: [GoodreadsBook] = []
    @Published var status = "Connect Goodreads to bring your reading shelves here."
    @Published var refreshing = false
    @Published var showSignIn = false
    @Published var profileID: String?
    let webView: WKWebView
    private let file: URL
    private var timer: Timer?
    private var collecting: [String:GoodreadsBook] = [:]
    private var page = 1
    override init() {
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = root.appendingPathComponent("goodreads-shelves.json")
        profileID = UserDefaults.standard.string(forKey: "goodreadsProfileID")
        super.init(); webView.navigationDelegate = self
        if let data = try? Data(contentsOf: file), let rows = try? JSONDecoder().decode([GoodreadsBook].self, from: data) { books = rows; status = "Saved Goodreads shelves · refresh to check for changes" }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    func connect() {
        showSignIn = true
        if webView.url == nil { webView.load(URLRequest(url: URL(string: "https://www.goodreads.com/user/sign_in")!)) }
    }
    func setProfile(_ value: String) {
        guard let url = URL(string: value), url.scheme == "https", ["goodreads.com","www.goodreads.com"].contains(url.host ?? "") else { status = "Use your Goodreads profile or My Books HTTPS link."; return }
        let parts = url.pathComponents
        guard let key = parts.firstIndex(where: { $0 == "show" || $0 == "list" }), parts.indices.contains(key+1), let id = parts[key+1].split(separator: "-").first, !id.isEmpty, id.allSatisfy(\.isNumber) else { status = "The Goodreads profile number could not be read."; return }
        profileID = String(id); UserDefaults.standard.set(profileID, forKey: "goodreadsProfileID"); refresh()
    }
    func refresh() {
        guard !refreshing else { return }
        guard let profileID else { status = "Connect Goodreads, paste your profile link, or import its library CSV."; return }
        collecting = [:]; page = 1; refreshing = true; status = "Refreshing Goodreads shelves…"
        loadPage(profileID)
    }
    private func loadPage(_ id: String) { webView.load(URLRequest(url: URL(string: "https://www.goodreads.com/review/list/\(id)?shelf=all&per_page=100&page=\(page)")!)) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, ["goodreads.com","www.goodreads.com"].contains(url.host ?? "") else { return }
        if url.path.contains("sign_in") || url.path.contains("sign_up") {
            if refreshing { refreshing = false; status = "Goodreads needs you to sign in again. Saved shelves are retained." }
            return
        }
        if !url.path.hasPrefix("/review/list/") {
            webView.evaluateJavaScript("Array.from(document.querySelectorAll('a[href*=\"/review/list/\"]')).find(a => /my books/i.test(a.textContent))?.href || null") { [weak self] result, _ in
                guard let link = result as? String else { return }
                self?.setProfile(link)
            }; return
        }
        let script = #"""
        (() => {
          const rows = Array.from(document.querySelectorAll('tr.bookalike'));
          return {books: rows.map(row => {
            const title = row.querySelector('td.title a.bookTitle,td.title a');
            const author = row.querySelector('td.author a');
            const shelf = row.querySelector('td.shelves .shelf,td.shelves a');
            const image = row.querySelector('td.cover img');
            const id = title?.href.match(/\/book\/show\/(\d+)/)?.[1];
            return {id:id || row.id,title:(title?.textContent || '').trim(),author:(author?.textContent || '').trim(),shelf:(shelf?.textContent || 'to-read').trim(),cover:image?.src || null,url:title?.href || ''};
          }).filter(b => b.id && b.title),next:!!document.querySelector('a.next_page:not(.disabled)'),valid:!!document.querySelector('#books, #booksBody, table.tableList')};
        })()
        """#
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else { return }
            guard error == nil, let object = result as? [String:Any], object["valid"] as? Bool == true, let rows = object["books"] as? [[String:Any]], let data = try? JSONSerialization.data(withJSONObject: rows), let decoded = try? JSONDecoder().decode([GoodreadsBook].self, from: data) else {
                self.refreshing = false; self.status = "Goodreads page could not be read. Open the connection or import your Goodreads CSV. Saved shelves are retained."; return
            }
            for book in decoded { self.collecting[book.id] = book }
            if self.refreshing, object["next"] as? Bool == true, self.page < 20, let id = self.profileID { self.page += 1; self.loadPage(id); return }
            self.books = Array(self.collecting.values).sorted { $0.title < $1.title }; self.refreshing = false
            self.persist(); self.status = "Goodreads shelves refreshed · \(self.books.count) books"; self.showSignIn = false
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { refreshing = false; status = "Goodreads is unavailable. Your saved shelves are still here." }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        let host = url.host ?? ""
        decisionHandler(url.scheme == "https" && (host == "goodreads.com" || host.hasSuffix(".goodreads.com") || host == "amazon.com" || host.hasSuffix(".amazon.com")) ? .allow : .cancel)
    }
    func disconnect() {
        profileID = nil; books = []; collecting = [:]; refreshing = false; webView.stopLoading()
        UserDefaults.standard.removeObject(forKey: "goodreadsProfileID"); try? FileManager.default.removeItem(at: file)
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { }
        status = "Goodreads disconnected on this device."
    }
    private func persist() { if let data = try? JSONEncoder().encode(books) { try? data.write(to: file, options: .atomic) } }
    func importCSV(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do { books = try Self.parseCSV(String(contentsOf: url, encoding: .utf8)); persist(); status = "Imported \(books.count) Goodreads books from CSV. This is a snapshot; connect for refresh." }
        catch { status = "Could not import Goodreads CSV: \(error.localizedDescription)" }
    }
    nonisolated static func parseCSV(_ text: String) throws -> [GoodreadsBook] {
        var rows: [[String]] = [], row: [String] = [], cell = "", quoted = false
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\u{feff}", with: "")); var index = 0
        while index < chars.count {
            let c = chars[index]
            if c == "\"" { if quoted && index+1 < chars.count && chars[index+1] == "\"" { cell.append("\""); index += 1 } else { quoted.toggle() } }
            else if c == "," && !quoted { row.append(cell); cell = "" }
            else if c == "\n" && !quoted { row.append(cell); rows.append(row); row = []; cell = "" }
            else { cell.append(c) }; index += 1
        }
        guard !quoted else { throw ListenError.message("An unclosed quote was found.") }
        if !cell.isEmpty || !row.isEmpty { row.append(cell); rows.append(row) }
        guard let header = rows.first, let title = header.firstIndex(of: "Title"), let author = header.firstIndex(of: "Author"), let id = header.firstIndex(of: "Book Id") else { throw ListenError.message("Use a Goodreads library export with Book Id, Title, and Author columns.") }
        let shelf = header.firstIndex(of: "Exclusive Shelf")
        return rows.dropFirst().compactMap { row in
            guard row.count > max(title,author,id), !row[id].isEmpty else { return nil }
            return GoodreadsBook(id: row[id], title: row[title], author: row[author], shelf: shelf.flatMap { row.indices.contains($0) ? row[$0] : nil } ?? "to-read", cover: nil, url: "https://www.goodreads.com/book/show/" + row[id])
        }
    }
}
