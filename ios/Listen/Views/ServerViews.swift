import SwiftUI

struct MediaServersView: View {
  @EnvironmentObject var servers: ServerLibrary
  @State private var connect = false
  var body: some View {
    NavigationStack {
      List {
        Section {
          Text(
            "Download DRM-free audiobooks from your own Audiobookshelf or Jellyfin server. Server credentials stay in this device’s Keychain."
          ).font(.subheadline).foregroundStyle(.secondary)
        }
        ForEach(servers.servers) { server in
          NavigationLink {
            ServerBrowser(server: server, parent: nil)
          } label: {
            Label {
              VStack(alignment: .leading) {
                Text(server.name)
                Text(server.kind.title).font(.caption).foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "externaldrive.connected.to.line.below")
            }
          }
        }.onDelete { indexes in for index in indexes { servers.remove(servers.servers[index]) } }
        if servers.servers.isEmpty {
          ContentUnavailableView(
            "Your own library, anywhere.", systemImage: "externaldrive",
            description: Text(
              "Connect a media server to browse and download books for offline listening."))
        }
        if !servers.status.isEmpty {
          Section("Transfer status") { Text(servers.status).font(.subheadline) }
        }
      }.navigationTitle("Servers").toolbar {
        Button("Add server", systemImage: "plus") { connect = true }.accessibilityIdentifier(
          "addServer")
      }.sheet(isPresented: $connect) { ServerConnectView() }
    }
  }
}
struct ServerConnectView: View {
  @EnvironmentObject var servers: ServerLibrary
  @Environment(\.dismiss) var dismiss
  @State private var kind: MediaServerKind = .audiobookshelf
  @State private var name = ""
  @State private var url = "https://"
  @State private var token = ""
  @State private var username = ""
  @State private var password = ""
  @State private var useToken = false
  @State private var userID = ""
  @State private var busy = false
  @State private var error: String?
  var body: some View {
    NavigationStack {
      Form {
        Section("Server") {
          Picker("Service", selection: $kind) {
            ForEach(MediaServerKind.allCases) { Text($0.title).tag($0) }
          }
          TextField("Name (optional)", text: $name)
          TextField("HTTPS server URL", text: $url).textInputAutocapitalization(.never)
            .autocorrectionDisabled().keyboardType(.URL).accessibilityIdentifier("serverURL")
        }
        Section("Sign in") {
          Toggle("Use an API token", isOn: $useToken)
          if useToken {
            SecureField("Access token", text: $token)
            if kind == .jellyfin {
              TextField("Jellyfin user ID (optional)", text: $userID).textInputAutocapitalization(
                .never
              ).autocorrectionDisabled()
            }
          } else {
            TextField("Username", text: $username).textInputAutocapitalization(.never)
              .autocorrectionDisabled().textContentType(.username)
            SecureField("Password", text: $password).textContentType(.password)
          }
          Text(
            "HTTPS and certificate checks are required. Passwords are used for sign-in only. Access tokens are stored locally in Keychain and are not synced to iCloud."
          ).font(.footnote).foregroundStyle(.secondary)
        }
        if let error {
          Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("serverError") }
        }
        if busy { ProgressView("Connecting…") }
      }.navigationTitle("Connect server").toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }.disabled(busy)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Connect") { Task { await connect() } }.disabled(
            busy || (useToken ? token.isEmpty : username.isEmpty || password.isEmpty)
          ).accessibilityIdentifier("connectServer")
        }
      }
    }
  }
  func connect() async {
    busy = true
    defer { busy = false }
    error = nil
    do {
      var server = MediaServer(
        name: name.isEmpty ? kind.title : name, kind: kind, baseURL: url, userID: userID)
      var access = token
      if !useToken {
        let authenticated = try await MediaServerAPI(server: server, token: "").authenticate(
          username: username, password: password)
        access = authenticated.0
        server.userID = authenticated.1
      } else if kind == .jellyfin, server.userID.isEmpty {
        let profile = try await MediaServerAPI(server: server, token: access).json(["Users", "Me"])
        server.userID = profile["Id"] as? String ?? ""
      }
      _ = try await MediaServerAPI(server: server, token: access).items()
      try servers.save(server, token: access)
      token = ""
      password = ""
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}
struct ServerBrowser: View {
  let server: MediaServer
  let parent: ServerItem?
  @EnvironmentObject var servers: ServerLibrary
  @EnvironmentObject var store: LibraryStore
  @State private var items: [ServerItem] = []
  @State private var busy = false
  @State private var error: String?
  @State private var page = 0
  @State private var more = true
  var body: some View {
    List {
      if let error {
        Text(error).foregroundStyle(.red)
        Button("Try again") { Task { await load(reset: true) } }
      }
      ForEach(items) { item in
        if item.folder {
          NavigationLink {
            ServerBrowser(server: server, parent: item)
          } label: {
            Label(item.title, systemImage: "folder")
          }
        } else {
          HStack {
            VStack(alignment: .leading) {
              Text(item.title).font(.headline)
              if !item.author.isEmpty {
                Text(item.author).font(.subheadline).foregroundStyle(.secondary)
              }
            }
            Spacer()
            Button {
              Task { await servers.download(item, from: server, store: store) }
            } label: {
              Image(systemName: "arrow.down.circle").frame(minWidth: 44, minHeight: 44)
            }.disabled(servers.downloading.contains(server.id.uuidString + item.id))
              .accessibilityLabel("Download \(item.title)")
          }
        }
      }
      if busy {
        ProgressView("Loading library…")
      } else if more && !items.isEmpty {
        Button("Load more") { Task { await load(reset: false) } }
      }
      if items.isEmpty && !busy && error == nil {
        Text("No items are available in this library.").foregroundStyle(.secondary)
      }
      if !servers.status.isEmpty {
        Text(servers.status).font(.footnote).foregroundStyle(.secondary)
      }
    }.navigationTitle(parent?.title ?? server.name).task {
      if items.isEmpty { await load(reset: true) }
    }.refreshable { await load(reset: true) }
  }
  func load(reset: Bool) async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    error = nil
    do {
      if reset { page = 0 }
      let rows = try await servers.api(server).items(parent: parent?.id, page: page)
      if reset { items = [] }
      let old = Set(items.map(\.id))
      items += rows.filter { !old.contains($0.id) }
      page += 1
      more = rows.count == 100
    } catch { self.error = error.localizedDescription }
  }
}
