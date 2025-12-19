//
//  DeleteBarView.swift
//  Sticker
//
//  Created by zhouyifeng on 2025/12/19.
//


import SwiftUI

struct DeleteBarView: View {
    let active: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(active ? Color.red.opacity(0.6) : Color.black.opacity(0.3))
                .background(.ultraThinMaterial)

            Text("拖到此处删除")
                .foregroundColor(.white)
                .font(.headline)
        }
    }
}
