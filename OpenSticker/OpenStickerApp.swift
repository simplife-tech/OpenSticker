//
//  OpenStickerApp.swift
//  OpenSticker
//
//  Created by zhouyifeng on 2025/12/19.
//

import SwiftUI

@main
struct OpenStickerApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

