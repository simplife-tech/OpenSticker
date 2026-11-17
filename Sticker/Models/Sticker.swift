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
    var scopes: Set<StickerScope>
    var isCollapsed: Bool?
    var paperColor: StickerPaperColor?
    var paperOpacity: Double?
    var textSize: CGSize? = nil
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


enum StickerPaperColor: String, Codable, CaseIterable {
    case honey, lemon, apricot, tangerine, blush, rose
    case lime, mint, sage, jade, aqua, sky
    case periwinkle, lavender, orchid, sand, slate, neutral

    var title: String {
        switch self {
        case .lemon: return "柠檬黄"
        case .apricot: return "杏桃色"
        case .tangerine: return "橘红"
        case .rose: return "玫瑰粉"
        case .lime: return "青柠绿"
        case .sage: return "鼠尾草绿"
        case .jade: return "翡翠绿"
        case .aqua: return "湖水青"
        case .periwinkle: return "长春花蓝"
        case .orchid: return "兰花紫"
        case .sand: return "暖沙色"
        case .slate: return "石板灰"
        case .neutral: return "中性"
        case .honey: return "蜂蜜黄"
        case .blush: return "珊瑚粉"
        case .mint: return "薄荷绿"
        case .sky: return "天空蓝"
        case .lavender: return "薰衣草紫"
        }
    }

    var tint: Color {
        switch self {
        case .lemon: return Color(red: 0.9, green: 0.78, blue: 0.2)
        case .apricot: return Color(red: 0.98, green: 0.58, blue: 0.37)
        case .tangerine: return Color(red: 0.97, green: 0.41, blue: 0.15)
        case .rose: return Color(red: 0.88, green: 0.28, blue: 0.58)
        case .lime: return Color(red: 0.65, green: 0.76, blue: 0.23)
        case .sage: return Color(red: 0.46, green: 0.57, blue: 0.37)
        case .jade: return Color(red: 0.12, green: 0.6, blue: 0.43)
        case .aqua: return Color(red: 0.16, green: 0.7, blue: 0.74)
        case .periwinkle: return Color(red: 0.4, green: 0.46, blue: 0.92)
        case .orchid: return Color(red: 0.8, green: 0.35, blue: 0.79)
        case .sand: return Color(red: 0.65, green: 0.48, blue: 0.32)
        case .slate: return Color(red: 0.36, green: 0.48, blue: 0.61)
        case .neutral: return .primary
        case .honey: return Color(red: 1, green: 0.72, blue: 0.19)
        case .blush: return Color(red: 0.97, green: 0.38, blue: 0.44)
        case .mint: return Color(red: 0.22, green: 0.74, blue: 0.50)
        case .sky: return Color(red: 0.25, green: 0.60, blue: 0.95)
        case .lavender: return Color(red: 0.67, green: 0.46, blue: 0.94)
        }
    }
}
