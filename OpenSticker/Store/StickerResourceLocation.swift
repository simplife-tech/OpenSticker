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
        if let restored = Self.restoreBookmark() {
            rootURL = restored.url
            if restored.refresh { saveBookmark(for: restored.url) }
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

        let destination = base.appendingPathComponent("OpenSticker", isDirectory: true)
        let previous = base.appendingPathComponent("Sticker", isDirectory: true)
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) || !manager.fileExists(atPath: previous.path) {
            return destination
        }

        let staging = base.appendingPathComponent(".OpenSticker-migration-" + UUID().uuidString, isDirectory: true)
        defer { try? manager.removeItem(at: staging) }
        do {
            try manager.copyItem(at: previous, to: staging)
            try manager.moveItem(at: staging, to: destination)
            return destination
        } catch {
            return manager.fileExists(atPath: destination.path) ? destination : previous
        }
    }

    // MARK: - Bookmark

    private func saveBookmark(for url: URL) {
        let data = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    private func clearBookmark() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    private static func restoreBookmark() -> (url: URL, refresh: Bool)? {
        guard let data = UserDefaults.standard.data(forKey: "StickerResourceBookmark") else {
            return nil
        }

        var isStale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                              relativeTo: nil, bookmarkDataIsStale: &isStale) {
            _ = url.startAccessingSecurityScopedResource()
            return (url, isStale)
        }

        // The old Bundle ID's security scope can fail after a rename.
        // The app runs outside App Sandbox and can use the resolved folder directly.
        guard let url = try? URL(resolvingBookmarkData: data, options: .withoutUI,
                                 relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
        return (url, isStale)
    }
}
