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
    var refreshTimer: Timer?
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
        var env = ProcessInfo.processInfo.environment; env["LISTEN_DATA_DIR"] = root.path; env["PYTHONUNBUFFERED"] = "1"; process.environment = env
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/listen.log")
        if !FileManager.default.fileExists(atPath: logs.path) { FileManager.default.createFile(atPath: logs.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
        if let handle = try? FileHandle(forWritingTo: logs) { handle.seekToEndOfFile(); process.standardOutput = handle; process.standardError = handle }
        do { try process.run(); server = process; waitForService(100) } catch { showStartupError("The bundled local service could not start. Reinstall listen. or inspect Library/Logs/listen.log.") }
    }
    func waitForService(_ remaining: Int) {
        if let data = try? Data(contentsOf: root.appendingPathComponent("connection.json")), let connection = try? JSONSerialization.jsonObject(with: data) as? [String: Any], connection["pid"] as? Int32 == server?.processIdentifier, let port = connection["port"] as? Int, let secret = connection["token"] as? String, let url = URL(string: "http://127.0.0.1:\(port)") {
            serviceURL = url; token = secret; loadPage("/discover")
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in if self.preferences()["auto_refresh_safari"] as? Bool == true { self.captureSafari(mode: "shelf", background: true) } }
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
        if let url = navigationAction.request.url, ["http", "https"].contains(url.scheme ?? "") { openBrowser(url) }; return nil
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
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
        var r = request("/")!; r.httpMethod = "POST"; r.httpBody = encoded.data(using: .utf8); r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); r.setValue(base.absoluteString + "/discover", forHTTPHeaderField: "Referer")
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
    func applicationWillTerminate(_ notification: Notification) { refreshTimer?.invalidate(); server?.terminate() }
}
let delegate = ListenDelegate(); NSApplication.shared.delegate = delegate; NSApplication.shared.setActivationPolicy(.regular); NSApplication.shared.run()
