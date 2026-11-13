import Combine
import Foundation
import Security

enum MediaServerKind: String, Codable, CaseIterable, Identifiable {
  case audiobookshelf, jellyfin
  var id: String { rawValue }
  var title: String { self == .audiobookshelf ? "Audiobookshelf" : "Jellyfin" }
}
struct MediaServer: Codable, Identifiable, Equatable {
  var id = UUID()
  var name: String
  var kind: MediaServerKind
  var baseURL: String
  var userID: String = ""
}
struct ServerItem: Identifiable, Equatable {
  var id: String
  var title: String
  var author: String
  var folder: Bool
}
struct ServerAudioFile: Equatable {
  var url: URL
  var name: String
}
struct ServerCredentialError: LocalizedError {
  let status: OSStatus
  var errorDescription: String? { "The server token could not be saved in Keychain (\(status)). Use a signed build with Keychain access. No token was saved to configuration files." }
}
enum ServerCredential {
  static let service = "listen.mobile.media-servers"
  static func save(_ token: String, id: UUID) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: id.uuidString,
    ]
    let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8)]
    var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      status = SecItemAdd(
        query.merging(attributes) { $1 }.merging([
          kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]) { $1 } as CFDictionary, nil)
    }
    guard status == errSecSuccess else {
      throw ServerCredentialError(status: status)
    }
  }
  static func read(_ id: UUID) -> String {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: id.uuidString, kSecReturnData as String: true,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return "" }
    return String(decoding: data, as: UTF8.self)
  }
  static func remove(_ id: UUID) {
    SecItemDelete(
      [
        kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
        kSecAttrAccount as String: id.uuidString,
      ] as CFDictionary)
  }
}
final class OriginRedirectPolicy: NSObject, URLSessionTaskDelegate {
  let base: URL
  init(_ base: URL) { self.base = base }
  static func sameOrigin(_ first: URL, _ second: URL) -> Bool {
    first.scheme?.lowercased() == second.scheme?.lowercased()
      && first.host?.lowercased() == second.host?.lowercased()
      && (first.port ?? 443) == (second.port ?? 443) && second.user == nil && second.password == nil
  }
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) { completionHandler(request.url.map { Self.sameOrigin(base, $0) } == true ? request : nil) }
}
struct MediaServerAPI {
  let server: MediaServer
  let token: String
  let base: URL
  let session: URLSession
  init(server: MediaServer, token: String, configuration: URLSessionConfiguration = .ephemeral)
    throws
  {
    self.server = server
    self.token = token
    self.base = try Self.validated(server.baseURL)
    self.session = URLSession(
      configuration: configuration, delegate: OriginRedirectPolicy(base), delegateQueue: nil)
  }
  static func validated(_ value: String) throws -> URL {
    guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
      url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
      url.query == nil, url.fragment == nil
    else {
      throw ListenError.message(
        "Use an HTTPS server URL without embedded credentials. Certificate checks stay enabled.")
    }
    return url
  }
  func url(_ path: [String], query: [URLQueryItem] = []) -> URL {
    var url = base
    for component in path { url.appendPathComponent(component) }
    var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    parts.queryItems = query.isEmpty ? nil : query
    return parts.url!
  }
  func request(_ url: URL, method: String = "GET", body: [String: Any]? = nil) throws -> URLRequest
  {
    guard OriginRedirectPolicy.sameOrigin(base, url) else {
      throw ListenError.message(
        "The server returned a link on another origin. Credentials were not sent.")
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    request.httpMethod = method
    if server.kind == .audiobookshelf {
      if !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
    } else {
      let defaults = UserDefaults.standard
      let deviceID = defaults.string(forKey: "mediaServerDeviceID") ?? UUID().uuidString
      defaults.set(deviceID, forKey: "mediaServerDeviceID")
      var authorization = "MediaBrowser Client=\"listen.\", Device=\"iOS\", DeviceId=\"\(deviceID)\", Version=\"\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")\""
      if !token.isEmpty {
        guard !token.contains("\"") && !token.contains("\r") && !token.contains("\n") else { throw ListenError.message("The server token contains invalid characters.") }
        authorization += ", Token=\"\(token)\""
        request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
      }
      request.setValue(authorization, forHTTPHeaderField: "Authorization")
      request.setValue(authorization, forHTTPHeaderField: "X-Emby-Authorization")
    }
    if let body {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    return request
  }
  func json(
    _ path: [String], query: [URLQueryItem] = [], method: String = "GET", body: [String: Any]? = nil
  ) async throws -> [String: Any] {
    let (data, response) = try await session.data(
      for: request(url(path, query: query), method: method, body: body))
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
      data.count <= 16_000_000
    else {
      throw ListenError.message(
        "The server refused the request. Check its address, account permissions, and saved login.")
    }
    return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
  }
  func authenticate(username: String, password: String) async throws -> (String, String) {
    let object = try await json(
      server.kind == .audiobookshelf ? ["login"] : ["Users", "AuthenticateByName"], method: "POST",
      body: server.kind == .audiobookshelf
        ? ["username": username, "password": password] : ["Username": username, "Pw": password])
    let user = object["user"] as? [String: Any] ?? object["User"] as? [String: Any] ?? [:]
    guard let key = object["AccessToken"] as? String ?? user["token"] as? String, !key.isEmpty
    else { throw ListenError.message("The server did not return an access token.") }
    return (key, user["Id"] as? String ?? user["id"] as? String ?? "")
  }
  func items(parent: String? = nil, page: Int = 0) async throws -> [ServerItem] {
    let data: [String: Any]
    if server.kind == .audiobookshelf {
      data = try await json(
        parent.map { ["api", "libraries", $0, "items"] } ?? ["api", "libraries"],
        query: parent == nil
          ? []
          : [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "minified", value: "0"),
          ])
      let rows = data[parent == nil ? "libraries" : "results"] as? [[String: Any]] ?? []
      return rows.compactMap { row in
        guard let id = row["id"] as? String else { return nil }
        let media = row["media"] as? [String: Any] ?? [:]
        let meta = media["metadata"] as? [String: Any] ?? [:]
        let authors = meta["authors"] as? [[String: Any]] ?? []
        return ServerItem(
          id: id, title: meta["title"] as? String ?? row["name"] as? String ?? "Untitled",
          author: meta["authorName"] as? String
            ?? authors.compactMap { $0["name"] as? String }.joined(separator: ", "),
          folder: parent == nil)
      }
    }
    guard !server.userID.isEmpty else {
      throw ListenError.message("Connect your Jellyfin account first so its user ID can be saved.")
    }
    var query = [
      URLQueryItem(name: "Limit", value: "100"),
      URLQueryItem(name: "StartIndex", value: String(page * 100)),
      URLQueryItem(name: "SortBy", value: "SortName"),
      URLQueryItem(name: "SortOrder", value: "Ascending"),
    ]
    if let parent { query.append(URLQueryItem(name: "ParentId", value: parent)) }
    data = try await json(
      parent == nil ? ["Users", server.userID, "Views"] : ["Users", server.userID, "Items"],
      query: query)
    return (data["Items"] as? [[String: Any]] ?? []).compactMap { row in
      guard let id = row["Id"] as? String else { return nil }
      return ServerItem(
        id: id, title: row["Name"] as? String ?? "Untitled",
        author: (row["Artists"] as? [String] ?? []).joined(separator: ", "),
        folder: row["IsFolder"] as? Bool ?? (parent == nil))
    }
  }
  func files(for item: ServerItem) async throws -> [ServerAudioFile] {
    if server.kind == .jellyfin {
      let data = try await json(["Users", server.userID, "Items", item.id])
      let path = data["Path"] as? String ?? "book.m4b"
      let name = URL(fileURLWithPath: path).lastPathComponent
      return [
        ServerAudioFile(
          url: url(["Items", item.id, "Download"]),
          name: Importer.supported(URL(fileURLWithPath: name)) ? name : "audio.m4b")
      ]
    }
    let data = try await json(
      ["api", "items", item.id], query: [URLQueryItem(name: "expanded", value: "1")])
    let media = data["media"] as? [String: Any] ?? [:]
    let rows = media["audioFiles"] as? [[String: Any]] ?? []
    let files = try rows.map { row -> ServerAudioFile in
      let meta = row["metadata"] as? [String: Any] ?? [:]
      guard let ino = (row["ino"] as? String) ?? (row["ino"] as? NSNumber)?.stringValue else {
        throw ListenError.message("The server did not provide an audio file identifier.")
      }
      let name = meta["filename"] as? String ?? "audio.m4b"
      return ServerAudioFile(
        url: url(["api", "items", item.id, "file", ino, "download"]), name: name)
    }
    guard !files.isEmpty else {
      throw ListenError.message("The server item has no downloadable audio files.")
    }
    return files
  }
  func download(_ file: ServerAudioFile, to target: URL) async throws {
    let (temporary, response) = try await session.download(for: request(file.url))
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw ListenError.message(
        "The server could not download this audio. Your local books are unchanged.")
    }
    try FileManager.default.moveItem(at: temporary, to: target)
  }
}
@MainActor final class ServerLibrary: ObservableObject {
  @Published var servers: [MediaServer] = []
  @Published var downloading: Set<String> = []
  @Published var status = ""
  private let file: URL
  init(root: URL) {
    file = root.appendingPathComponent("media-servers.json")
    servers = (try? JSONDecoder().decode([MediaServer].self, from: Data(contentsOf: file))) ?? []
  }
  func save(_ value: MediaServer, token: String) throws {
    try ServerCredential.save(token, id: value.id)
    if let i = servers.firstIndex(where: { $0.id == value.id }) {
      servers[i] = value
    } else {
      servers.append(value)
    }
    try JSONEncoder().encode(servers).write(to: file, options: .atomic)
  }
  func remove(_ value: MediaServer) {
    ServerCredential.remove(value.id)
    servers.removeAll { $0.id == value.id }
    try? JSONEncoder().encode(servers).write(to: file, options: .atomic)
  }
  func api(_ value: MediaServer) throws -> MediaServerAPI {
    let token = ServerCredential.read(value.id)
    guard !token.isEmpty else {
      throw ListenError.message("Reconnect this server. Its saved Keychain token is unavailable.")
    }
    return try MediaServerAPI(server: value, token: token)
  }
  func download(_ item: ServerItem, from server: MediaServer, store: LibraryStore) async {
    let key = server.id.uuidString + item.id
    guard !downloading.contains(key) else { return }
    downloading.insert(key)
    defer { downloading.remove(key) }
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: staging) }
    do {
      let client = try api(server)
      let files = try await client.files(for: item)
      try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
      var urls: [URL] = []
      for (index, file) in files.enumerated() {
        try Task.checkCancellation()
        status = "Downloading \(index+1) of \(files.count): \(item.title)"
        let name =
          String(format: "%04d-", index) + URL(fileURLWithPath: file.name).lastPathComponent
        let target = staging.appendingPathComponent(name)
        try await client.download(file, to: target)
        urls.append(target)
      }
      let ids = await store.importFiles(
        urls, combine: true, enrich: false,
        convert: UserDefaults.standard.bool(forKey: "automaticConversion"))
      for id in ids {
        if var book = store.books.first(where: { $0.id == id }) {
          book.title = item.title
          if !item.author.isEmpty { book.author = item.author }
          book.metadataUpdatedAt = Date()
          store.update(book)
        }
      }
      status =
        ids.isEmpty
        ? "Download finished, but import needs attention. Check the library message."
        : "Available offline: \(item.title)"
    } catch { status = error.localizedDescription }
  }
}

/// Public file downloads may redirect to a CDN, but never downgrade TLS or embed credentials.
final class SecureDownloadRedirectPolicy: NSObject, URLSessionTaskDelegate {
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    let url = request.url
    completionHandler(url?.scheme == "https" && url?.user == nil && url?.password == nil ? request : nil)
  }
}
