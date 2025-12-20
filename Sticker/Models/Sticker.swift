//
//  Sticker.swift
//  Sticker
//
//  Created by zhouyifeng on 2025/12/19.
//


import SwiftUI

enum StickerContent: Codable, Equatable, Hashable {
    case text(String)
    case image(ImagePayload)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case image
    }

    enum ContentType: String, Codable {
        case text
        case image
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(ContentType.self, forKey: .type)

        switch type {
        case .text:
            self = .text(try c.decode(String.self, forKey: .text))
        case .image:
            self = .image(try c.decode(ImagePayload.self, forKey: .image))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let text):
            try c.encode(ContentType.text, forKey: .type)
            try c.encode(text, forKey: .text)

        case .image(let payload):
            try c.encode(ContentType.image, forKey: .type)
            try c.encode(payload, forKey: .image)
        }
    }
}

struct Sticker: Identifiable, Equatable, Codable {
    let id: UUID
    var content: StickerContent
    let scopes: Set<StickerScope>
    var imageSize: CGSize = CGSize(width: 200, height: 200)
    
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
