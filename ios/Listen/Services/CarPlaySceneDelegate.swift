import CarPlay

/// Optional Apple-approved CarPlay capability. No entitlement bypass is attempted.
@MainActor final class CarPlaySceneDelegate: NSObject, CPTemplateApplicationSceneDelegate {
  private var controller: CPInterfaceController?
  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    controller = interfaceController
    showLibrary()
  }
  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) { controller = nil }
  private func showLibrary() {
    let books = MobileCompanionBridge.store?.books.filter { !$0.state.finished } ?? []
    let items = books.prefix(100).map { book -> CPListItem in
      let item = CPListItem(text: book.title, detailText: book.author)
      item.handler = { [weak self] _, complete in
        Task { @MainActor in
          await MobileCompanionBridge.player?.open(book)
          self?.controller?.pushTemplate(
            CPNowPlayingTemplate.shared, animated: true, completion: nil)
          complete()
        }
      }
      return item
    }
    let list = CPListTemplate(title: "listen.", sections: [CPListSection(items: items)])
    controller?.setRootTemplate(list, animated: false, completion: nil)
  }
}
