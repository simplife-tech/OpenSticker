//
//  StickerResourceLocation.swift
//  Sticker
//
//  Created by 周屹峰 on 2025/12/21.
//


import Foundation

final class StickerResourceLocation {

    static let shared = StickerResourceLocation()

    private let bookmarkKey = "StickerResourceBookmark"

    private(set) var rootURL: URL

    private init() {
        if let url = Self.restoreBookmark() {
            rootURL = url
        } else {
            rootURL = Self.defaultURL()
        }
        ensureStructure()
    }

    // MARK: - Public

    func useDefault() {
        rootURL = Self.defaultURL()
        clearBookmark()
        ensureStructure()
    }

    func useCustom(url: URL) {
        rootURL = url
        saveBookmark(for: url)
        ensureStructure()
    }

    // MARK: - Paths

    var stickersJSON: URL {
        rootURL.appendingPathComponent("stickers.json")
    }

    var imagesDir: URL {
        rootURL.appendingPathComponent("images", isDirectory: true)
    }

    // MARK: - Structure

    private func ensureStructure() {
        let fm = FileManager.default

        if !fm.fileExists(atPath: rootURL.path) {
            try? fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        if !fm.fileExists(atPath: imagesDir.path) {
            try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Default Location

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return base.appendingPathComponent("Sticker", isDirectory: true)
    }

    // MARK: - Bookmark

    private func saveBookmark(for url: URL) {
        let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    private func clearBookmark() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    private static func restoreBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: "StickerResourceBookmark") else {
            return nil
        }

        var isStale = false
        let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            bookmarkDataIsStale: &isStale
        )

        _ = url?.startAccessingSecurityScopedResource()
        return url
    }
}
