//
//  ImageStore.swift
//  Sticker
//
//  Created by 周屹峰 on 2025/12/20.
//

import AppKit

final class ImageStore {

    static let shared = ImageStore()

    private let location = StickerResourceLocation.shared

    private init() {}

    private var imagesDir: URL {
        location.imagesDir
    }

    func save(image: NSImage) -> ImagePayload {
        let id = UUID().uuidString + ".png"
        let url = imagesDir.appendingPathComponent(id)

        guard let data = image.pngData() else {
            fatalError("Failed to encode image")
        }

        try? data.write(to: url)
        return ImagePayload(filename: id)
    }

    func remove(filename: String) {
        let url = imageURL(for: filename)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }

    func imageURL(for filename: String) -> URL {
        imagesDir.appendingPathComponent(filename)
    }
}

