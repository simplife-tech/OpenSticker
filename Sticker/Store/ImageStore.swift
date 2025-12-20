//
//  ImageStore.swift
//  Sticker
//
//  Created by 周屹峰 on 2025/12/20.
//


import AppKit

final class ImageStore {

    static let shared = ImageStore()

    private init() {}

    private var baseDir: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let dir = base
            .appendingPathComponent("Sticker", isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)

        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        }

        return dir
    }

    func save(image: NSImage) -> ImagePayload {
        let id = UUID().uuidString + ".png"
        let url = baseDir.appendingPathComponent(id)

        guard
            let data = image.pngData()
        else {
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

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print("❌ Failed to remove image:", error)
        }
    }

    func imageURL(for filename: String) -> URL {
        baseDir.appendingPathComponent(filename)
    }
    
}
