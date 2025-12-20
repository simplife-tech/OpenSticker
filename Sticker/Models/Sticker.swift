//
//  Sticker.swift
//  Sticker
//
//  Created by zhouyifeng on 2025/12/19.
//


import SwiftUI

enum StickerContent: Codable, Hashable {
    case text(String)
    case image(path: String)
}

struct Sticker: Identifiable, Equatable, Codable {
    let id: UUID
    var content: StickerContent
    let scopes: Set<StickerScope>

    /// 归一化坐标（0~1）
    var normalizedPosition: CGPoint
}

extension Sticker {

    func isVisible(in context: StickerContext) -> Bool {
        // 没有任何 scope，默认不显示（防脏数据）
        guard !scopes.isEmpty else {
            return false
        }

        for scope in scopes {
            switch scope {

            case .global:
                // 全局贴纸永远可见
                return true

            case .app(let bundleId):
                // 当前 App 匹配
                if let current = context.bundleId,
                   current == bundleId {
                    return true
                }

            case .browser:
                // 当前 App 是浏览器
                if context.isBrowser {
                    return true
                }

            case .browserDomain(let domain):
                // 浏览器 + 域名匹配
                if context.isBrowser,
                   let currentDomain = context.domain,
                   currentDomain == domain {
                    return true
                }
            
            case .browserUrl(let url):
                // 浏览器 + url匹配
                if context.isBrowser,
                   let currentUrl = context.url,
                   currentUrl == url {
                    return true
                }
            }
        }

        // 没有任何 scope 命中
        return false
    }
}
