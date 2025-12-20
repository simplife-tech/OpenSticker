//
//  StickerContext.swift
//  Sticker
//
//  Created by 周屹峰 on 2025/12/20.
//

import AppKit

struct StickerContext {
    let bundleId: String?
    let isBrowser: Bool
    let domain: String?
}

extension StickerContext {
    var resolvedBundleId: String? {
        bundleId?.isEmpty == false ? bundleId : nil
    }
}

let browserBundleIds: Set<String> = [
    "com.apple.Safari",
    "com.google.Chrome",
    "com.microsoft.edgemac",
    "org.mozilla.firefox"
]

func isBrowserApp(_ bundleId: String?) -> Bool {
    guard let bundleId else { return false }
    return browserBundleIds.contains(bundleId)
}


func makeStickerContext() -> StickerContext {
    let app = getCurrentAppInfo()

    return StickerContext(
        bundleId: app?.bundleId,
        isBrowser: app.map { isBrowserApp($0.bundleId) } ?? false,
        domain: currentBrowserDomain(bundleId: app?.bundleId)
    )
}

func currentBrowserDomain(bundleId: String?) -> String? {
    switch bundleId {
    case "com.apple.Safari":
        return nil

    case "com.google.Chrome",
         "com.microsoft.edgemac":
        return nil

    case "org.mozilla.firefox":
        return nil   // Firefox AppleScript 非常不稳定

    default:
        return nil
    }
}

func runAppleScript(_ source: String) -> String? {
    var error: NSDictionary?
    let script = NSAppleScript(source: source)
    let output = script?.executeAndReturnError(&error)

    if let error {
        print("AppleScript error:", error)
        return nil
    }

    return output?.stringValue
}

func chromeDomain() -> String? {
    let script = """
    tell application "Google Chrome"
        if not (exists front window) then return ""
        set theURL to URL of active tab of front window
        return theURL
    end tell
    """

    return runAppleScript(script)	
}

func safariDomain() -> String? {
    let script = """
    tell application "Safari"
        if not (exists front document) then return ""
        set theURL to URL of front document
        return theURL
    end tell
    """

    return runAppleScript(script)
}

final class ContextController: ObservableObject {

    @Published var context = StickerContext(
        bundleId: nil,
        isBrowser: false,
        domain: nil
    )

    func refresh() {
        context = makeStickerContext()
    }
}
