import AppKit
import WebKit
import LocalAuthentication

final class ListenDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var web: WKWebView!
    var server: Process?
    var serviceURL: URL?
    var token = ""
    var pendingBook: URL?
    var lockOverlay: NSView?
    var safariBusy = false
    var grWindow: NSWindow?
    var grWeb: WKWebView?
    var grEnabled = false
    var grBusy = false
    var grUser = ""
    var grPage = 1
    var grTimer: Timer?
    var refreshTimer: Timer?
    var goodreadsEnabled = false
    var goodreadsWindow: Int?
    var goodreadsUser = ""
    var goodreadsPage = 1
    var goodreadsNext = Date.distantPast
    var goodreadsRefreshStart = false
    var root: URL {
        if let custom = ProcessInfo.processInfo.environment["LISTEN_DATA_DIR"] { return URL(fileURLWithPath: custom) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("listen", isDirectory: true)
    }
    func preferences() -> [String: Any] {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("settings.json")), let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return result
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        createMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "listen."; window.titlebarAppearsTransparent = true; window.delegate = self; window.minSize = NSSize(width: 850, height: 640)
        let material = NSVisualEffectView(frame: window.contentView!.bounds)
        material.material = .underWindowBackground; material.blendingMode = .behindWindow; material.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(material)
        let configuration = WKWebViewConfiguration(); configuration.userContentController.add(self, name: "listen")
        web = WKWebView(frame: window.contentView!.bounds, configuration: configuration)
        web.setValue(false, forKey: "drawsBackground"); web.autoresizingMask = [.width, .height]; web.uiDelegate = self; web.navigationDelegate = self
        window.contentView!.addSubview(web); applyAppearance(); window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        startServer()
    }
    func createMenu() {
        let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About listen.", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let lock = NSMenuItem(title: "Lock Window", action: #selector(lockWindow), keyEquivalent: "l"); lock.keyEquivalentModifierMask = [.control, .command]; lock.target = self; appMenu.addItem(lock)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","); settings.target = self; appMenu.addItem(settings)
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "Quit listen.", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; let editItem = NSMenuItem(); let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }
        editItem.submenu = editMenu; menu.addItem(editItem); NSApp.mainMenu = menu
    }
    func startServer() {
        let executable = Bundle.main.resourceURL!.appendingPathComponent("server/listen-server")
        let process = Process(); process.executableURL = executable; process.currentDirectoryURL = root
        var env = ProcessInfo.processInfo.environment; env["LISTEN_DATA_DIR"] = root.path; env["PYTHONUNBUFFERED"] = "1"; env["LISTEN_OWNER_PID"] = String(ProcessInfo.processInfo.processIdentifier); process.environment = env
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/listen.log")
        if !FileManager.default.fileExists(atPath: logs.path) { FileManager.default.createFile(atPath: logs.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        if let handle = try? FileHandle(forWritingTo: logs) { handle.seekToEndOfFile(); process.standardOutput = handle; process.standardError = handle }
        do { try process.run(); server = process; waitForService(100) } catch { showStartupError("The bundled local service could not start. Reinstall listen. or inspect Library/Logs/listen.log.") }
    }
    func waitForService(_ remaining: Int) {
        if let data = try? Data(contentsOf: root.appendingPathComponent("connection.json")), let connection = try? JSONSerialization.jsonObject(with: data) as? [String: Any], connection["owner_pid"] as? Int == Int(ProcessInfo.processInfo.processIdentifier), let port = (connection["port"] as? Int) ?? Int(connection["port"] as? String ?? ""), let secret = connection["token"] as? String, let url = URL(string: "http://127.0.0.1:\(port)") {
            serviceURL = url; token = secret; loadPage("/discover")
            let resume = (try? Data(contentsOf: root.appendingPathComponent("goodreads-browser.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            goodreadsEnabled = resume?["enabled"] as? Bool ?? false
            if let feedData = try? Data(contentsOf: root.appendingPathComponent("goodreads-connection.json")), let feed = try? JSONSerialization.jsonObject(with: feedData) as? [String: Any], feed["enabled"] as? Bool == true { goodreadsEnabled = false }
            goodreadsWindow = resume?["window"] as? Int
            goodreadsUser = resume?["user"] as? String ?? ""
            goodreadsRefreshStart = !goodreadsUser.isEmpty
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in if self.goodreadsEnabled && Date() >= self.goodreadsNext { self.pollGoodreads() } }
            let nativeConnection = (try? Data(contentsOf: root.appendingPathComponent("goodreads-native.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            if nativeConnection?["enabled"] as? Bool == true { grUser = nativeConnection?["user"] as? String ?? ""; connectNativeGoodreads(show: false) }
            if let pending = pendingBook { pendingBook = nil; handleBookURL(pending) }
            return
        }
        if remaining > 0 && server?.isRunning == true { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.waitForService(remaining - 1) } }
        else { showStartupError("The local service did not become ready. See Library/Logs/listen.log for details.") }
    }
    func showStartupError(_ text: String) { let alert = NSAlert(); alert.messageText = "listen. could not start"; alert.informativeText = text; alert.runModal() }
    func request(_ path: String) -> URLRequest? {
        guard let base = serviceURL, let url = URL(string: path, relativeTo: base) else { return nil }
        var r = URLRequest(url: url); r.setValue(token, forHTTPHeaderField: "X-Listen-Token"); return r
    }
    func loadPage(_ path: String) { if let r = request(path) { web.load(r) } }
    @objc func openSettings() { loadPage("/settings") }
    func post(_ path: String, payload: [String: Any], completion: @escaping ([String: Any]?, String?) -> Void) {
        guard var r = request(path), let data = try? JSONSerialization.data(withJSONObject: payload), let base = serviceURL else { completion(nil, "The local service is unavailable."); return }
        r.httpMethod = "POST"; r.httpBody = data; r.timeoutInterval = 35; r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.setValue(base.absoluteString, forHTTPHeaderField: "Origin")
        URLSession.shared.dataTask(with: r) { data, response, _ in
            DispatchQueue.main.async {
                guard let data = data, let response = response as? HTTPURLResponse, let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { completion(nil, "The local service did not respond."); return }
                if response.statusCode >= 400 { completion(nil, body["error"] as? String ?? "This action could not be completed.") } else { completion(body, nil) }
            }
        }.resume()
    }
    func notify(_ message: String) { web.callAsyncJavaScript("if(typeof notify==='function')notify(message);", arguments: ["message": message], in: nil, in: .page, completionHandler: nil) }
    func applyAppearance() {
        let theme = preferences()["theme"] as? String ?? "system"
        NSApp.appearance = theme == "dark" ? NSAppearance(named: .darkAqua) : theme == "light" ? NSAppearance(named: .aqua) : nil
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView === web, let source = message.frameInfo.request.url, source.host == "127.0.0.1", source.port == serviceURL?.port, let body = message.body as? [String: Any], let command = body["command"] as? String else { return }
        switch command {
        case "goodreads-native-connect": connectNativeGoodreads(show: true)
        case "goodreads-native-refresh": refreshNativeGoodreads()
        case "goodreads-connect": connectGoodreads()
        case "goodreads-disconnect":
            grEnabled = false; grTimer?.invalidate(); grWeb?.stopLoading(); grWindow?.orderOut(nil); persistNativeGoodreads(); goodreadsEnabled = false; persistGoodreads(); post("/goodreads/connection", payload: ["action": "disconnect"]) { _, _ in self.loadPage("/discover") }
        case "goodreads-refresh": goodreadsNext = .distantPast
        case "appearance": applyAppearance()
        case "lock": lockWindow()
        case "folder": chooseFolder(body["kind"] as? String ?? "")
        case "clipboard": useClipboard()
        case "browser-book": web.evaluateJavaScript("window.dispatchEvent(new Event('listen-browser-dialog'));", completionHandler: nil)
        case "safari-book", "goodreads-safari-book": captureSafari(mode: "book")
        case "safari-shelf", "goodreads-safari-shelf", "goodreads-sync": captureSafari(mode: "shelf")
        case "magnet":
            if let raw = body["url"] as? String, raw.hasPrefix("magnet:?"), raw.contains("xt=urn%3Abtih%3A") || raw.contains("xt=urn:btih:"), let url = URL(string: raw) { NSWorkspace.shared.open(url) }
        case "goodreads-signin": openBrowser(URL(string: "https://www.goodreads.com/user/sign_in")!)
        case "goodreads-shelves": openBrowser(URL(string: "https://www.goodreads.com/")!)
        case "goodreads-audiobooks": openBrowser(URL(string: "https://www.goodreads.com/list/show/426.Best_Audiobooks")!)
        default: break
        }
    }
    func openBrowser(_ url: URL) {
        let ids = ["safari": "com.apple.Safari", "chrome": "com.google.Chrome", "firefox": "org.mozilla.firefox", "edge": "com.microsoft.edgemac", "brave": "com.brave.Browser"]
        let selected = preferences()["browser"] as? String ?? "default"
        if let id = ids[selected], let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { let config = NSWorkspace.OpenConfiguration(); config.activates = true; NSWorkspace.shared.open([url], withApplicationAt: app, configuration: config, completionHandler: nil) }
        else { NSWorkspace.shared.open(url) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if webView === grWeb, let url = navigationAction.request.url, url.scheme == "https" { grWeb?.load(URLRequest(url: url)); return nil }
        if let url = navigationAction.request.url, ["http", "https"].contains(url.scheme ?? "") { openBrowser(url) }; return nil
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if webView === grWeb { decisionHandler(action.request.url?.scheme == "https" ? .allow : .cancel); return }
        if action.navigationType == .linkActivated, let url = action.request.url, url.host != "127.0.0.1", ["http", "https"].contains(url.scheme ?? "") { openBrowser(url); decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    func chooseFolder(_ kind: String) {
        guard ["downloads_folder", "completed_folder"].contains(kind) else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false; panel.prompt = "Choose folder"
        panel.beginSheetModal(for: window) { response in if response == .OK, let url = panel.url { self.post("/api/folder", payload: ["kind": kind, "path": url.path]) { _, error in if let error = error { self.notify(error) } else { self.loadPage("/settings"); self.notify("Destination folder saved.") } } } }
    }
    func useClipboard() {
        guard let value = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), let url = URL(string: value), url.scheme == "https", ["goodreads.com", "www.goodreads.com"].contains(url.host ?? ""), url.path.hasPrefix("/book/show/") else { notify("Copy a Goodreads book URL, then try again."); return }
        post("/goodreads/link", payload: ["url": url.absoluteString]) { body, error in if let error = error { self.notify(error) } else if let body = body { self.searchBook(body) } }
    }
    func application(_ application: NSApplication, open urls: [URL]) { for url in urls where url.scheme == "listen" { if serviceURL == nil { pendingBook = url } else { handleBookURL(url) } } }
    func handleBookURL(_ url: URL) {
        guard url.host == "book", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        var payload = [String: Any](); for key in ["url", "title", "author"] { payload[key] = components.queryItems?.first(where: { $0.name == key })?.value ?? "" }
        post("/goodreads/link", payload: payload) { body, error in if let error = error { self.notify(error) } else if let body = body { self.searchBook(body) } }
    }
    func searchBook(_ book: [String: Any]) {
        guard let base = serviceURL else { return }
        let values = ["query": book["query"] as? String ?? "", "goodreads_title": book["title"] as? String ?? "", "goodreads_author": book["author"] as? String ?? ""]
        let encoded = values.map { key, value in key + "=" + (value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") }.joined(separator: "&")
        var r = request("/")!; r.httpMethod = "POST"; r.httpBody = encoded.data(using: .utf8); r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); r.setValue(base.absoluteString + "/discover", forHTTPHeaderField: "Referer"); r.setValue(base.absoluteString, forHTTPHeaderField: "Origin")
        web.load(r); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func captureSafari(mode: String, background: Bool = false) {
        guard !safariBusy else { return }
        if background && !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.apple.Safari" }) { return }
        safariBusy = true; if !background { notify("Reading the Goodreads page open in Safari…") }
        let script = "const requestedMode = \"\(mode)\";\n" + #"""
const safari = Application('Safari');
if (!safari.running() || !safari.windows().length) throw new Error('Open Goodreads in Safari first.');
const tab = safari.windows[0].currentTab();
const url = String(tab.url());
if (!/^https:\/\/(?:www\.)?goodreads\.com\/(?:book\/show\/\d+|review\/list\/\d+)/i.test(url)) throw new Error('Open a Goodreads book or shelf first.');
if (requestedMode === 'book' && !/\/book\/show\/\d+/.test(url)) throw new Error('Open a book first.');
if (requestedMode === 'shelf' && !/\/review\/list\/\d+/.test(url)) throw new Error('Open My Books first.');
const page_title = String(tab.name());
const html = String(tab.source());
if (String(tab.url()) !== url || html.length > 5000000) throw new Error('The page changed or is too large.');
JSON.stringify({url, page_title, html});
"""#
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); process.arguments = ["-l", "JavaScript", "-e", script]
            let output = Pipe(); let errors = Pipe(); process.standardOutput = output; process.standardError = errors
            do { try process.run() } catch { DispatchQueue.main.async { self.safariBusy = false; if !background { self.notify("Could not start the Safari connection.") } }; return }
            let response = output.fileHandleForReading.readDataToEndOfFile(); let errorData = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            DispatchQueue.main.async {
                guard process.terminationStatus == 0, var body = (try? JSONSerialization.jsonObject(with: response)) as? [String: Any] else {
                    self.safariBusy = false
                    if !background { let detail = String(data: errorData, encoding: .utf8) ?? ""; self.notify(detail.contains("-1743") || detail.localizedCaseInsensitiveContains("not authorized") ? "Allow listen. to access Safari in System Settings → Privacy & Security → Automation, then try again." : "Open a Goodreads book or My Books shelf in Safari, then try again.") }; return
                }
                body["mode"] = mode
                self.post("/goodreads/safari", payload: body) { result, error in
                    self.safariBusy = false
                    if let error = error { if !background { self.notify(error) }; return }
                    guard let result = result else { return }
                    if result["action"] as? String == "search", !background { self.searchBook(result) }
                    else if result["action"] as? String == "import" {
                        if !background { self.loadPage("/discover"); self.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
                        else { self.web.evaluateJavaScript("if(typeof refreshGoodreads==='function')refreshGoodreads();", completionHandler: nil); if result["changed"] as? Bool == true { self.web.evaluateJavaScript("window.dispatchEvent(new Event('goodreadsSynced'));", completionHandler: nil) } }
                    }
                }
            }
        }
    }
    func persistNativeGoodreads() {
        let data = try? JSONSerialization.data(withJSONObject: ["enabled": grEnabled, "user": grUser])
        if let data = data { let url = root.appendingPathComponent("goodreads-native.json"); try? data.write(to: url, options: .atomic); try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
    }
    func connectNativeGoodreads(show: Bool) {
        if show { grUser = "" }
        grEnabled = true; persistNativeGoodreads()
        post("/goodreads/feed/disconnect", payload: [:]) { _, _ in
            self.post("/goodreads/window", payload: ["action": "connecting"]) { _, _ in }
        }
        if grWeb == nil {
            let config = WKWebViewConfiguration(); config.websiteDataStore = .default()
            let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 780), configuration: config)
            view.navigationDelegate = self; view.uiDelegate = self; grWeb = view
            grWindow = NSWindow(contentRect: view.frame, styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
            grWindow?.title = "Goodreads · listen."; grWindow?.contentView = view; grWindow?.isReleasedWhenClosed = false; grWindow?.center()
        }
        if show { grWindow?.makeKeyAndOrderFront(nil) }
        grTimer?.invalidate(); grTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in self.refreshNativeGoodreads() }
        refreshNativeGoodreads()
    }
    func refreshNativeGoodreads() {
        guard grEnabled, !grBusy else { return }; grPage = 1
        let path = grUser.isEmpty ? "/user/sign_in" : "/review/list/" + grUser + "?shelf=all&per_page=100&page=1"
        grWeb?.load(URLRequest(url: URL(string: "https://www.goodreads.com" + path)!))
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === grWeb, grEnabled, !grBusy, let url = webView.url else { return }
        guard url.scheme == "https", ["www.goodreads.com","goodreads.com"].contains(url.host ?? "") else { return }
        let path = url.path
        if path.contains("sign_in") || path.contains("sign_up") || path.contains("/ap/") {
            grWindow?.makeKeyAndOrderFront(nil)
            post("/goodreads/window", payload: ["action": "needs-signin"]) { _, _ in }; return
        }
        guard path == "/" || path.hasPrefix("/user/show/") || path.hasPrefix("/review/list/") else { return }
        grBusy = true
        webView.evaluateJavaScript("document.documentElement.outerHTML") { value, _ in
            guard self.grEnabled, webView.url == url, let html = value as? String, html.utf8.count < 5000000 else { self.grBusy = false; return }
            self.post("/goodreads/window", payload: ["url":url.absoluteString,"html":html,"user_id":self.grUser,"page":self.grPage]) { body, error in
                self.grBusy = false; guard self.grEnabled else { return }
                if let error = error { self.notify(error); return }
                guard let body = body else { return }
                if let user = body["user_id"] as? String { self.grUser = user; self.persistNativeGoodreads() }
                let action = body["action"] as? String ?? "wait"
                if action == "navigate", let value = body["url"] as? String, let target = URL(string:value), target.scheme == "https", target.host == "www.goodreads.com", target.path == "/review/list/" + self.grUser {
                    self.grPage = body["page"] as? Int ?? 1
                    DispatchQueue.main.asyncAfter(deadline:.now()+1) { if self.grEnabled { self.grWeb?.load(URLRequest(url:target)) } }
                } else if action == "complete" {
                    self.grWindow?.orderOut(nil)
                    self.web.evaluateJavaScript("window.dispatchEvent(new Event('goodreadsSynced'));", completionHandler:nil)
                }
            }
        }
    }
    func persistGoodreads() {
        let value: [String: Any] = ["enabled": goodreadsEnabled, "window": goodreadsWindow ?? 0, "user": goodreadsUser]
        if let data = try? JSONSerialization.data(withJSONObject: value) { let path = root.appendingPathComponent("goodreads-browser.json"); try? data.write(to: path, options: .atomic); try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path) }
    }
    func safariScript(_ script: String, completion: @escaping ([String: Any]?, String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-l", "JavaScript", "-e", script]
            let out = Pipe(); let err = Pipe(); p.standardOutput = out; p.standardError = err
            do { try p.run() } catch { DispatchQueue.main.async { completion(nil, "Safari could not start.") }; return }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) { if p.isRunning { p.terminate() } }
            let bytes = out.fileHandleForReading.readDataToEndOfFile(); let errors = err.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            let value = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
            DispatchQueue.main.async { completion(p.terminationStatus == 0 ? value : nil, String(data: errors, encoding: .utf8) ?? "") }
        }
    }
    func connectGoodreads() {
        guard !safariBusy else { return }
        if goodreadsEnabled, let id = goodreadsWindow { safariScript("const s=Application('Safari');s.activate();const w=s.windows().filter(w=>w.id()===\(id));if(w.length!==1)throw Error('Closed');w[0].index=1;JSON.stringify({ok:true});") { value, _ in if value == nil { self.goodreadsEnabled = false; self.connectGoodreads() } }; return }
        safariBusy = true
        post("/goodreads/connection", payload: ["action": "connecting"]) { _, _ in }
        // A separate window avoids reading or changing the user's other Safari tabs.
        safariScript(#"""
const s=Application('Safari'); s.activate();
s.documents.push(s.Document({url:'https://www.goodreads.com/user/sign_in'}));
JSON.stringify({window:s.windows[0].id()});
"""#) { result, _ in
            self.safariBusy = false
            guard let id = result?["window"] as? Int else { self.goodreadsFailure(); return }
            self.goodreadsWindow = id; self.goodreadsUser = ""; self.goodreadsPage = 1; self.goodreadsEnabled = true; self.goodreadsNext = .distantPast; self.persistGoodreads()
            self.notify("Sign in to Goodreads in Safari. Your books will appear automatically.")
        }
    }
    func goodreadsFailure() {
        goodreadsEnabled = false; persistGoodreads()
        post("/goodreads/connection", payload: ["action": "unavailable"]) { _, _ in self.web.evaluateJavaScript("if(typeof refreshGoodreads==='function')refreshGoodreads();", completionHandler: nil) }
        notify("Reconnect Goodreads. If asked, allow listen. to access Safari in System Settings → Privacy & Security → Automation.")
    }
    func pollGoodreads() {
        guard !safariBusy, let id = goodreadsWindow, id > 0 else { return }
        if goodreadsRefreshStart && !goodreadsUser.isEmpty { goodreadsRefreshStart = false; safariBusy = true; navigateGoodreads("https://www.goodreads.com/review/list/" + goodreadsUser + "?shelf=all&per_page=100&page=1"); return }
        safariBusy = true
        // Only read source after checking a dedicated single-tab window and safe page path.
        let script = "const windowId = \(id);\n" + #"""
const s=Application('Safari');
if(!s.running())throw Error('Safari is closed');
const wins=s.windows().filter(w=>w.id()===windowId);
if(wins.length!==1 || wins[0].tabs().length!==1)throw Error('Reconnect Goodreads');
const t=wins[0].tabs[0];const url=String(t.url());
if(!/^https:\/\/(?:www\.)?goodreads\.com\/(?:$|[?#]|review\/list\/\d+|user\/show\/\d+)/i.test(url)){
 JSON.stringify({action:'signin'});
}else{
 const html=String(t.source());
 if(String(t.url())!==url || html.length>5000000)throw Error('Page changed');
 JSON.stringify({url,html});
}
"""#
        safariScript(script) { result, _ in
            guard self.goodreadsEnabled else { self.safariBusy = false; return }
            guard var body = result else { self.safariBusy = false; self.goodreadsFailure(); return }
            if body["action"] as? String == "signin" {
                self.safariBusy = false
                self.post("/goodreads/connection", payload: ["action": "needs-signin"]) { _, _ in }; return
            }
            body["user_id"] = self.goodreadsUser; body["page"] = self.goodreadsPage
            self.post("/goodreads/connection", payload: body) { response, error in
                guard self.goodreadsEnabled else { self.safariBusy = false; return }
                guard let response = response, error == nil else { self.safariBusy = false; self.goodreadsFailure(); return }
                if let user = response["user_id"] as? String { self.goodreadsUser = user; self.persistGoodreads() }
                let action = response["action"] as? String ?? "wait"
                if action == "background" { self.goodreadsEnabled = false; self.persistGoodreads(); self.safariBusy = false; self.loadPage("/discover"); self.notify("Goodreads connected directly. You can close Safari."); return }
                if action == "navigate", let url = response["url"] as? String { self.goodreadsPage = response["page"] as? Int ?? 1; self.navigateGoodreads(url) }
                else if action == "complete" {
                    self.goodreadsNext = Date().addingTimeInterval(300); self.goodreadsPage = 1; self.goodreadsRefreshStart = true
                    self.safariBusy = false
                    self.web.evaluateJavaScript("window.dispatchEvent(new Event('goodreadsSynced'));", completionHandler: nil)
                    // Refresh navigation occurs only in the dedicated Goodreads window.
                } else { self.safariBusy = false }
            }
        }
    }
    func navigateGoodreads(_ url: String) {
        guard let id = goodreadsWindow, let u = URL(string: url), u.scheme == "https", u.host == "www.goodreads.com", u.path == "/review/list/" + goodreadsUser, let bytes = try? JSONSerialization.data(withJSONObject: url, options: .fragmentsAllowed), let quoted = String(data: bytes, encoding: .utf8) else { safariBusy = false; goodreadsFailure(); return }
        let script = "const s=Application('Safari');const w=s.windows().filter(w=>w.id()===\(id));if(w.length!==1||w[0].tabs().length!==1)throw Error('Reconnect');w[0].tabs[0].url=\(quoted);JSON.stringify({ok:true});"
        safariScript(script) { result, _ in self.safariBusy = false; self.goodreadsNext = Date().addingTimeInterval(4); if result == nil { self.goodreadsFailure() } }
    }
    @objc func lockWindow() {
        guard lockOverlay == nil else { return }; web.isHidden = true
        let overlay = NSVisualEffectView(frame: window.contentView!.bounds); overlay.material = .underWindowBackground; overlay.autoresizingMask = [.width, .height]
        let group = NSView(frame: NSRect(x: (overlay.bounds.width - 400) / 2, y: (overlay.bounds.height - 260) / 2, width: 400, height: 260)); group.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        let icon = NSImageView(frame: NSRect(x: 160, y: 175, width: 80, height: 80)); icon.image = NSImage(named: NSImage.applicationIconName); group.addSubview(icon)
        let title = NSTextField(labelWithString: "A little privacy for your shelf."); title.font = .systemFont(ofSize: 23, weight: .medium); title.alignment = .center; title.frame = NSRect(x: 0, y: 119, width: 400, height: 40); group.addSubview(title)
        let subtitle = NSTextField(labelWithString: "Use Touch ID or your Mac password to return."); subtitle.textColor = .secondaryLabelColor; subtitle.alignment = .center; subtitle.frame = NSRect(x: 0, y: 88, width: 400, height: 24); group.addSubview(subtitle)
        let button = NSButton(title: "Unlock listen.", target: self, action: #selector(unlockWindow)); button.bezelStyle = .rounded; button.frame = NSRect(x: 115, y: 25, width: 170, height: 38); group.addSubview(button)
        overlay.addSubview(group); window.contentView!.addSubview(overlay); lockOverlay = overlay
    }
    @objc func unlockWindow() {
        let context = LAContext(); var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) { context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your listen. window") { success, _ in DispatchQueue.main.async { if success { self.lockOverlay?.removeFromSuperview(); self.lockOverlay = nil; self.web.isHidden = false } } } }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { refreshTimer?.invalidate(); grTimer?.invalidate(); server?.terminate() }
}
let delegate = ListenDelegate(); NSApplication.shared.delegate = delegate; NSApplication.shared.setActivationPolicy(.regular); NSApplication.shared.run()
