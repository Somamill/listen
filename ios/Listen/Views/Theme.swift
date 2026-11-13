import SwiftUI
import UIKit

enum ListenTheme {
    static let accent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 169/255, green: 199/255, blue: 174/255, alpha: 1) : UIColor(red: 66/255, green: 104/255, blue: 75/255, alpha: 1)
    })
    static let background = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 21/255, green: 24/255, blue: 21/255, alpha: 1) : UIColor(red: 250/255, green: 248/255, blue: 244/255, alpha: 1)
    })
}
struct BookArtwork: View {
    let book: AudioBook
    let root: URL
    var body: some View {
        Group {
            if let filename = book.coverFilename, let image = UIImage(contentsOfFile: root.appendingPathComponent(book.id.uuidString).appendingPathComponent(filename).path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(ListenTheme.accent.opacity(0.12)).overlay {
                    Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(ListenTheme.accent)
                }
            }
        }.clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
    }
}
