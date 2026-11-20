import SwiftUI

final class StickerCommandViewModel: ObservableObject {
    @Published var pluginID = ""
    @Published var pluginValues: [String: String] = [:]
    @Published var groupID: UUID?
    @Published var text = ""
    @Published var color: StickerPaperColor = .honey
}
