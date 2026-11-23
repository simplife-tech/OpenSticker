//
//  Scope.swift
//  Sticker
//
//  Created by 周屹峰 on 2025/12/20.
//


enum Scope {
    case global
    case browser
    case app
    case domain
    case url
}

struct ActionItem {
    let title: String
    let subtitle: String?
    let scope: Scope
}
