//
//  StickerCommandViewModel.swift
//  Sticker
//
//  Created by 周屹峰 on 2025/12/20.
//


import Foundation
import AppKit

final class StickerCommandViewModel: ObservableObject {

    @Published var text: String = ""
    @Published var pastedImage: NSImage?
    @Published var selectedIndex: Int = 0

    func clearImage() {
        pastedImage = nil
    }
    
    func reset(with initialText: String?) {
        text = initialText ?? ""
        pastedImage = nil
        selectedIndex = 0
    }
}

