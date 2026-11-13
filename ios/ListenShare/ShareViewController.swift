import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private let message = UILabel()
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    message.text = "Preparing audio for listen.…"
    message.numberOfLines = 0
    message.textAlignment = .center
    message.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(message)
    NSLayoutConstraint.activate([
      message.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
      message.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
      message.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
    Task { await receive() }
  }
  @MainActor private func receive() async {
    guard let root = CompanionStorage.directory else {
      message.text =
        "Shared import needs the app’s signed App Group capability. Open the file directly in listen. or import it from Files."
      return
    }
    let folder = root.appendingPathComponent("Inbox/\(UUID().uuidString)", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
      let providers = items.flatMap { $0.attachments ?? [] }
      var count = 0
      for provider in providers.prefix(20) {
        let type =
          provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier)
          ? UTType.audio.identifier
          : provider.hasItemConformingToTypeIdentifier(UTType.zip.identifier)
            ? UTType.zip.identifier : nil
        guard let type else { continue }
        let index = count
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, Error>) in
          provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
            do {
              if let error { throw error }
              guard let url else {
                throw NSError(
                  domain: "listen.share", code: 1,
                  userInfo: [NSLocalizedDescriptionKey: "This attachment has no audio file."])
              }
              let name = String(format: "%04d-", index) + url.lastPathComponent
              try FileManager.default.copyItem(at: url, to: folder.appendingPathComponent(name))
              continuation.resume()
            } catch { continuation.resume(throwing: error) }
          }
        }
        count += 1
      }
      guard count > 0 else {
        throw NSError(
          domain: "listen.share", code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Choose audio or a ZIP archive."])
      }
      try Data("{}".utf8).write(to: folder.appendingPathComponent("ready.json"), options: .atomic)
      message.text = "Saved for listen. Open the app to finish importing."
      extensionContext?.completeRequest(returningItems: nil)
    } catch {
      try? FileManager.default.removeItem(at: folder)
      message.text = "Could not import: \(error.localizedDescription)"
    }
  }
}
