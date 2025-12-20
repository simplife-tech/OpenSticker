//
//  StickerScope.swift
//  Sticker
//
//  Created by 周屹峰 on 2025/12/20.
//


import Foundation

enum StickerScope: Hashable, Codable {
    case global
    case app(bundleId: String)
    case browser
    case browserDomain(domain: String)
    case browserUrl(url: String)
}
