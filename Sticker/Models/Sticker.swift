//
//  Sticker.swift
//  Sticker
//
//  Created by zhouyifeng on 2025/12/19.
//


import SwiftUI

struct Sticker: Identifiable, Equatable, Codable {
    let id: UUID
    var text: String

    /// 归一化坐标（0~1）
    var normalizedPosition: CGPoint
}

