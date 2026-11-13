import Combine
import Darwin
import Foundation
import Network

@MainActor final class LocalTransfer: ObservableObject {
  @Published var address = ""
  @Published var status = "Start a temporary transfer session on trusted Wi-Fi."
  @Published var files: [URL] = []
  @Published var running = false
  private var listener: NWListener?
  private let queue = DispatchQueue(label: "listen.local-transfer")
  private var connections: [UUID: UploadConnection] = [:]
  private(set) var root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "listen-transfer-\(UUID().uuidString)")
  func start() {
    guard listener == nil else { return }
    do {
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      let token =
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
        + UUID().uuidString.replacingOccurrences(of: "-", with: "")
      let service = try NWListener(using: .tcp, on: .any)
      listener = service
      service.stateUpdateHandler = { [weak self, weak service] state in
        Task { @MainActor in
          guard let self else { return }
          if case .ready = state, let port = service?.port {
            self.running = true
            self.address = "http://\(Self.localAddress()):\(port.rawValue)/#\(token)"
            self.status = "Ready. Keep this screen open while transferring."
          } else if case .failed(let error) = state {
            self.status = error.localizedDescription
            self.stop()
          }
        }
      }
      let root = self.root
      service.newConnectionHandler = { [weak self, weak service] connection in
        Task { @MainActor in
          guard let self, self.listener === service, self.connections.count < 8 else {
            connection.cancel()
            return
          }
          let id = UUID()
          let receiver = UploadConnection(
            connection: connection, root: root, token: token,
            received: { [weak self] url in
              Task { @MainActor in
                self?.files.append(url)
                self?.status = "Received \(url.lastPathComponent)"
              }
            },
            closed: { [weak self] in
              Task { @MainActor in self?.connections.removeValue(forKey: id) }
            })
          self.connections[id] = receiver
          receiver.start()
        }
      }
      service.start(queue: queue)
    } catch { status = error.localizedDescription }
  }
  func stop() {
    listener?.cancel()
    listener = nil
    for receiver in connections.values { receiver.cancel() }
    connections.removeAll()
    running = false
    address = ""
  }
  func clear() {
    files = []
    try? FileManager.default.removeItem(at: root)
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "listen-transfer-\(UUID().uuidString)")
  }
  nonisolated static func safeRelativePath(_ name: String) -> Bool {
    guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0") else {
      return false
    }
    let parts = name.split(separator: "/", omittingEmptySubsequences: false)
    return parts.count <= 20
      && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count < 240 }
  }
  nonisolated static func localAddress() -> String {
    #if targetEnvironment(simulator)
      return "127.0.0.1"
    #else
      var result = "Wi-Fi-address-unavailable"
      var pointer: UnsafeMutablePointer<ifaddrs>?
      guard getifaddrs(&pointer) == 0 else { return result }
      defer { freeifaddrs(pointer) }
      var current = pointer
      while let entry = current {
        if String(cString: entry.pointee.ifa_name) == "en0", let address = entry.pointee.ifa_addr,
          address.pointee.sa_family == UInt8(AF_INET)
        {
          var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
          if getnameinfo(
            address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0,
            NI_NUMERICHOST) == 0
          {
            result = String(cString: host)
          }
        }
        current = entry.pointee.ifa_next
      }
      return result
    #endif
  }
}
private final class UploadConnection {
  let connection: NWConnection
  let root: URL
  let token: String
  let received: (URL) -> Void
  let closed: () -> Void
  private let queue = DispatchQueue(label: "listen.upload")
  private var timeout: DispatchWorkItem?
  var buffer = Data()
  var bodyLength: Int64?
  var written: Int64 = 0
  var file: FileHandle?
  var destination: URL?
  var partial: URL?
  var finished = false
  init(
    connection: NWConnection, root: URL, token: String, received: @escaping (URL) -> Void,
    closed: @escaping () -> Void
  ) {
    self.connection = connection
    self.root = root
    self.token = token
    self.received = received
    self.closed = closed
  }
  func start() {
    connection.stateUpdateHandler = { [weak self] state in if case .failed = state { self?.abort() }
    }
    connection.start(queue: queue)
    receive()
  }
  func cancel() { queue.async { [self] in abort() } }
  private func armTimeout() {
    timeout?.cancel()
    let task = DispatchWorkItem { [weak self] in self?.abort() }
    timeout = task
    queue.asyncAfter(deadline: .now() + 30, execute: task)
  }
  func receive() {
    armTimeout()
    connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) {
      [self] data, _, complete, error in
      guard !finished else { return }
      do {
        if let data, !data.isEmpty {
          if bodyLength == nil {
            buffer.append(data)
            if let separator = buffer.range(of: Data("\r\n\r\n".utf8)) {
              guard separator.lowerBound < 32_768 else {
                reply(431, "Headers too large")
                return
              }
              let header = String(decoding: buffer[..<separator.lowerBound], as: UTF8.self)
              let body = Data(buffer[separator.upperBound...])
              buffer = Data()
              guard try begin(header) else { return }
              try append(body)
            } else if buffer.count > 32_768 {
              reply(431, "Headers too large")
              return
            }
          } else {
            try append(data)
          }
        }
        if finished { return }
        if complete || error != nil {
          abort()
          return
        }
        receive()
      } catch { reply(400, "Transfer failed; keep the original file and retry.") }
    }
  }
  func begin(_ header: String) throws -> Bool {
    let lines = header.components(separatedBy: "\r\n")
    let first = (lines.first ?? "").split(separator: " ")
    guard first.count >= 2 else {
      reply(400, "Invalid request")
      return false
    }
    let method = String(first[0])
    let path = String(first[1])
    if method == "GET", path == "/" {
      reply(200, Self.html, contentType: "text/html; charset=utf-8")
      return false
    }
    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      if let split = line.firstIndex(of: ":") {
        headers[String(line[..<split]).lowercased()] = String(line[line.index(after: split)...])
          .trimmingCharacters(in: .whitespaces)
      }
    }
    guard headers["authorization"] == "Bearer " + token else {
      reply(401, "Open the complete transfer link from listen.")
      return false
    }
    guard method == "PUT", path.hasPrefix("/upload/"),
      let name = String(path.dropFirst(8)).removingPercentEncoding,
      LocalTransfer.safeRelativePath(name)
    else {
      reply(400, "Invalid upload path")
      return false
    }
    guard let length = headers["content-length"].flatMap(Int64.init), length > 0,
      length <= 5 * 1024 * 1024 * 1024
    else {
      reply(413, "File must be between 1 byte and 5 GB.")
      return false
    }
    let target = root.appendingPathComponent(name)
    guard Importer.supported(target) || target.pathExtension.lowercased() == "zip" else {
      reply(415, "Choose supported audio or ZIP files.")
      return false
    }
    guard !FileManager.default.fileExists(atPath: target.path) else {
      reply(409, "A file with this name was already received.")
      return false
    }
    try FileManager.default.createDirectory(
      at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    let staging = root.appendingPathComponent(".partial-\(UUID().uuidString)")
    FileManager.default.createFile(atPath: staging.path, contents: nil)
    file = try FileHandle(forWritingTo: staging)
    partial = staging
    destination = target
    bodyLength = length
    return true
  }
  func append(_ data: Data) throws {
    guard let length = bodyLength else { return }
    guard Int64(data.count) <= length - written else {
      reply(400, "Unexpected body length")
      return
    }
    try file?.write(contentsOf: data)
    written += Int64(data.count)
    if written == length, let partial, let destination {
      try file?.close()
      file = nil
      try FileManager.default.moveItem(at: partial, to: destination)
      self.partial = nil
      received(destination)
      reply(200, "Received")
    }
  }
  func abort() {
    guard !finished else { return }
    finished = true
    timeout?.cancel()
    closed()
    try? file?.close()
    file = nil
    if let partial { try? FileManager.default.removeItem(at: partial) }
    connection.cancel()
  }
  func reply(_ code: Int, _ text: String, contentType: String = "text/plain; charset=utf-8") {
    guard !finished else { return }
    finished = true
    timeout?.cancel()
    closed()
    try? file?.close()
    file = nil
    if let partial { try? FileManager.default.removeItem(at: partial) }
    let body = Data(text.utf8)
    let header =
      "HTTP/1.1 \(code) \(code==200 ? "OK":"Error")\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n"
    connection.send(
      content: Data(header.utf8) + body,
      completion: .contentProcessed { [connection] _ in connection.cancel() })
  }
  static let html = #"""
    <!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Transfer to listen.</title><meta name="description" content="Transfer your audio and ZIP files directly to listen. over trusted local Wi-Fi.">
    <style>/* Hallmark: listen. local-transfer utility; native system typography and sage/forest palette. */
    /* Critique: one task, no marketing sections; flexible file inputs preserve 320px layout. */
    html,body{overflow-x:clip}
    :root{color-scheme:light dark;font-family:system-ui;--accent:#42684b;--paper:#faf8f4;--ink:#151815}*{box-sizing:border-box}body{color:var(--ink);background:var(--paper);max-width:65ch;margin:clamp(1rem,8vh,4rem) auto;padding:1.5rem;line-height:1.6;scrollbar-color:var(--accent) var(--paper)}h1{text-wrap:balance;font-size:2rem;line-height:1.2;margin-bottom:1.5rem}input{font:inherit;min-height:44px;width:100%;min-width:0;display:block;accent-color:var(--accent);caret-color:var(--accent)}input:focus-visible{outline:3px solid var(--accent);outline-offset:3px}input:disabled{background:color-mix(in srgb,var(--ink) 12%,var(--paper));color:var(--ink);cursor:wait}input::file-selector-button{min-height:44px;padding:.5rem .75rem;border:1px solid var(--accent);border-radius:8px;color:var(--ink);background:var(--paper)}input::file-selector-button:active{background:var(--accent);color:var(--paper)}li{margin:1rem 0;font-variant-numeric:tabular-nums}::selection{background:var(--accent);color:var(--paper)}@media(prefers-color-scheme:dark){:root{--accent:#a9c7ae;--paper:#151815;--ink:#faf8f4}}</style>
    <h1>Transfer to listen.</h1><p>Choose audio files or a folder. Keep the transfer screen open on your device, then confirm the import there.</p>
    <label>Audio or ZIP files <input id="files" type="file" multiple></label><p><label>A folder <input id="folder" type="file" webkitdirectory multiple></label></p><ul id="results" aria-live="polite" aria-label="Transfer results"></ul>
    <script>const token=location.hash.slice(1);for(const input of document.querySelectorAll('input'))input.onchange=async()=>{input.disabled=true;for(const file of input.files){const row=document.createElement('li');row.textContent=file.name+' — uploading';document.querySelector('#results').append(row);try{const name=file.webkitRelativePath||file.name;const r=await fetch('/upload/'+name.split('/').map(encodeURIComponent).join('/'),{method:'PUT',headers:{Authorization:'Bearer '+token},body:file});row.textContent=file.name+' — '+(r.ok?'received':await r.text())}catch{row.textContent=file.name+' — connection interrupted; keep the original and retry'}}input.disabled=false};</script></html>
    """#
}
