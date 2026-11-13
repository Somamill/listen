import SwiftUI

struct BrowserTransferView: View {
  @EnvironmentObject var transfer: LocalTransfer
  @EnvironmentObject var store: LibraryStore
  @Environment(\.dismiss) var dismiss
  @State private var importing = false
  var body: some View {
    NavigationStack {
      List {
        Section {
          Text(
            "Use a browser on the same trusted Wi-Fi network. Transfers use local HTTP with a temporary secret link, not Internet-hosted storage. Anyone who has the link on that network can upload until you close this screen."
          ).font(.subheadline)
          if !transfer.running {
            Button("Start local transfer", systemImage: "wifi") { transfer.start() }
              .accessibilityIdentifier("startLocalTransfer")
          } else {
            Text(transfer.address).textSelection(.enabled).font(.footnote.monospaced())
            ShareLink("Share transfer link", item: transfer.address)
          }
          Text(transfer.status).foregroundStyle(.secondary)
        }
        Section("Received files (\(transfer.files.count))") {
          ForEach(transfer.files, id: \.self) { Text($0.lastPathComponent) }
        }
        if importing { ProgressView("Importing…") }
      }.navigationTitle("Browser transfer").toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }.disabled(importing)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Import") { Task { await finish() } }.disabled(transfer.files.isEmpty || importing)
        }
      }.onDisappear { transfer.stop() }
    }
  }
  func finish() async {
    importing = true
    defer { importing = false }
    transfer.stop()
    let files = transfer.files
    let ids = await store.importFiles(
      files, combine: true,
      enrich: UserDefaults.standard.object(forKey: "automaticMetadata") as? Bool ?? true,
      convert: UserDefaults.standard.bool(forKey: "automaticConversion"))
    if !ids.isEmpty {
      transfer.clear()
      dismiss()
    }
  }
}
struct DownloadImportView: View {
  @EnvironmentObject var store: LibraryStore
  @Environment(\.dismiss) var dismiss
  @State private var text = ""
  @State private var busy = false
  @State private var error: String?
  var body: some View {
    NavigationStack {
      Form {
        TextField("HTTPS audio or ZIP URL", text: $text).textInputAutocapitalization(.never)
          .autocorrectionDisabled().keyboardType(.URL)
        Text(
          "Use a direct file URL you have permission to download. For authenticated media libraries, use the Servers tab instead."
        ).font(.footnote).foregroundStyle(.secondary)
        if let error { Text(error).foregroundStyle(.red) }
        if busy { ProgressView("Downloading…") }
      }.navigationTitle("Download a file").toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }.disabled(busy)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Download") { Task { await download() } }.disabled(busy || text.isEmpty)
        }
      }
    }
  }
  func download() async {
    busy = true
    defer { busy = false }
    error = nil
    do {
      guard let url = URL(string: text), url.scheme == "https", url.host != nil, url.user == nil,
        url.password == nil
      else { throw ListenError.message("Use an HTTPS URL without embedded credentials.") }
      var request = URLRequest(url: url)
      request.timeoutInterval = 60
      let (temporary, response) = try await URLSession(configuration: .ephemeral, delegate: SecureDownloadRedirectPolicy(), delegateQueue: nil).download(for: request)
      guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
        response.url?.scheme == "https"
      else { throw ListenError.message("The file could not be downloaded securely.") }
      let name = URL(fileURLWithPath: response.suggestedFilename ?? url.lastPathComponent)
        .lastPathComponent
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: folder) }
      let target = folder.appendingPathComponent(name)
      try FileManager.default.moveItem(at: temporary, to: target)
      let ids = await store.importFiles(
        [target],
        enrich: UserDefaults.standard.object(forKey: "automaticMetadata") as? Bool ?? true,
        convert: UserDefaults.standard.bool(forKey: "automaticConversion"))
      if !ids.isEmpty {
        dismiss()
      } else {
        throw ListenError.message(store.error ?? "The downloaded file contains no supported audio.")
      }
    } catch { self.error = error.localizedDescription }
  }
}
