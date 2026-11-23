//
//  PermissionUtils.swift
//  Sticker
//
//  Created by 周屹峰 on 2025/12/21.
//

import AppKit

// 1️⃣ 权限检测
func hasAccessibilityPermission() -> Bool {
    AXIsProcessTrusted()
}

// 2️⃣ 打开系统设置
func openAccessibilitySettings() {
    let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!
    NSWorkspace.shared.open(url)
}

// 3️⃣ 重启 App
func relaunchApp() {
    let appURL = Bundle.main.bundleURL

    let task = Process()
    task.launchPath = "/usr/bin/open"
    task.arguments = [appURL.path]
    task.launch()

    NSApp.terminate(nil)
}
