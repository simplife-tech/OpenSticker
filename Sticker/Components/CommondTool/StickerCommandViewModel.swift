import SwiftUI

final class StickerCommandViewModel: ObservableObject {
    @Published var text = ""
    @Published var color: StickerPaperColor = .honey
}
