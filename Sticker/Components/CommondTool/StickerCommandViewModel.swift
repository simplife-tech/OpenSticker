//
//  StickerCommandViewModel.swift
//  Sticker
//
//  Created by 周屹峰 on 2025/12/20.
//


import Foundation

final class StickerCommandViewModel: ObservableObject {

    @Published var text: String = ""
    @Published var selectedIndex: Int = 0

    func reset(with initialText: String?) {
        text = initialText ?? ""
        selectedIndex = 0
    }
}

