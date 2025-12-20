//
//  ImagePayload.swift
//  Sticker
//
//  Created by 周屹峰 on 2025/12/20.
//


import AppKit

struct ImagePayload: Codable, Equatable, Hashable {
    let filename: String

    var fileURL: URL {
        ImageStore.shared.imageURL(for: filename)
    }
}


extension NSImage {
    func pngData() -> Data? {
        guard
            let tiff = tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff)
        else { return nil }

        return rep.representation(using: .png, properties: [:])
    }
}
