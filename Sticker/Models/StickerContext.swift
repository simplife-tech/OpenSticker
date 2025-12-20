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
    let url: String?
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


func buildStickerContext() -> StickerContext {
    let app = getCurrentAppInfo()
    var domain: String? = nil
    let url = currentBrowserUrl(bundleId: app?.bundleId)
    if url != nil {
        domain = extractDomain(from: url!)
    }
    return StickerContext(
        bundleId: app?.bundleId,
        isBrowser: app.map { isBrowserApp($0.bundleId) } ?? false,
        domain: domain,
        url: stripQueryAndFragment(from: url)
    )
}

func buildCurrentContextAsync(
    completion: @escaping (StickerContext) -> Void
) {
    // 1️⃣ 同步拿“前台 App”信息（安全、快）
    let frontApp = NSWorkspace.shared.frontmostApplication
    let bundleId = frontApp?.bundleIdentifier

    let isSafari = bundleId == "com.apple.Safari"
    let isChrome = bundleId == "com.google.Chrome"
    let isBrowser = isSafari || isChrome

    // 2️⃣ 不是浏览器，直接返回（不碰 AppleScript）
    guard isBrowser else {
        let context = StickerContext(
            bundleId: bundleId,
            isBrowser: false,
            domain: nil,
            url: nil
        )
        DispatchQueue.main.async {
            completion(context)
        }
        return
    }

    // 3️⃣ 浏览器：后台线程取 domain（⚠️ 关键）
    DispatchQueue.global(qos: .userInitiated).async {
        let urlString: String?

        if isChrome {
            urlString = chromeUrl()
        } else {
            urlString = safariUrl()
        }

        let domain = urlString.flatMap { extractDomain(from: $0) }

        let context = StickerContext(
            bundleId: bundleId,
            isBrowser: true,
            domain: domain,
            url:  stripQueryAndFragment(from: urlString)
        )

        DispatchQueue.main.async {
            completion(context)
        }
    }
}


func currentBrowserUrl(bundleId: String?) -> String? {
    switch bundleId {
    case "com.apple.Safari":
        return safariUrl()

    case "com.google.Chrome",
         "com.microsoft.edgemac":
        return chromeUrl()

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

func chromeUrl() -> String? {
    let script = """
    tell application "Google Chrome"
        if not (exists front window) then return ""
        set theURL to URL of active tab of front window
        return theURL
    end tell
    """

    return runAppleScript(script)	
}

func safariUrl() -> String? {
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
        domain: nil,
        url: nil
    )

    func refresh(completion: ((StickerContext) -> Void)? = nil) {
        buildCurrentContextAsync { [weak self] newContext in
            self?.context = newContext
            completion?(newContext)
        }
    }
}

func extractDomain(from urlString: String) -> String? {
    guard
        let url = URL(string: urlString),
        let host = url.host
    else { return nil }

    return host
}

func stripQueryAndFragment(from urlString: String?) -> String? {
    guard
        let urlString,
        var components = URLComponents(string: urlString)
    else {
        return nil
    }

    components.query = nil
    components.fragment = nil

    return components.string
}

