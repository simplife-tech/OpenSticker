//
//  StickerIndex.swift
//  Sticker
//
//  Created by 周屹峰 on 2025/12/20.
//

import AppKit

final class StickerIndex {

    private(set) var global: Set<UUID> = []
    private(set) var byApp: [String: Set<UUID>] = [:]
    private(set) var browser: Set<UUID> = []
    private(set) var byDomain: [String: Set<UUID>] = [:]

    func index(_ sticker: Sticker) {
        for scope in sticker.scopes {
            switch scope {
            case .global:
                global.insert(sticker.id)

            case .app(let bundleId):
                byApp[bundleId, default: []].insert(sticker.id)

            case .browser:
                browser.insert(sticker.id)

            case .browserSite(let domain):
                byDomain[domain, default: []].insert(sticker.id)
            }
        }
    }

    func remove(_ sticker: Sticker) {
        for scope in sticker.scopes {
            switch scope {
            case .global:
                global.remove(sticker.id)

            case .app(let bundleId):
                byApp[bundleId]?.remove(sticker.id)

            case .browser:
                browser.remove(sticker.id)

            case .browserSite(let domain):
                byDomain[domain]?.remove(sticker.id)
            }
        }
    }

    func clear() {
        global.removeAll()
        browser.removeAll()
        byApp.removeAll()
        byDomain.removeAll()
    }
}
