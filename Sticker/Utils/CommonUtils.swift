//
//  CommonUtils.swift
//  Sticker
//
//  Created by zhouyifeng on 2025/12/19.
//
import ApplicationServices
import AppKit

func getSelectedText() -> String? {
//    print("\n=== 开始获取选中文字 ===")
    
    let systemWide = AXUIElementCreateSystemWide()
    var focused: CFTypeRef?

    let err = AXUIElementCopyAttributeValue(
        systemWide,
        kAXFocusedUIElementAttribute as CFString,
        &focused
    )
    
//    print("1️⃣ 获取焦点元素: \(err == .success ? "✅ 成功" : "❌ 失败 (错误码: \(err.rawValue))")")
    
    guard err == .success, let focusedElement = focused else {
//        print("💡 提示: 请检查辅助功能权限")
        return nil
    }
    
    let element = focusedElement as! AXUIElement
    
    // 打印元素信息
//    printElementInfo(element)
    
    // 尝试获取选中文字
    var selectedText: CFTypeRef?
    let err2 = AXUIElementCopyAttributeValue(
        element,
        kAXSelectedTextAttribute as CFString,
        &selectedText
    )
    
//    print("2️⃣ 获取选中文字: \(err2 == .success ? "✅ 成功" : "❌ 失败 (错误码: \(err2.rawValue))")")
    
    if err2 == .success, let text = selectedText as? String {
        print("3️⃣ 文字内容: '\(text)' (长度: \(text.count))")
        return text.isEmpty ? nil : text
    }
    
    // 如果 kAXSelectedTextAttribute 失败，尝试其他属性
//    print("⚠️ kAXSelectedTextAttribute 失败，尝试其他方法...")
    
    // 方法2: 尝试获取 kAXSelectedTextRangeAttribute 和 kAXValueAttribute
    return getTextViaRange(element)
}

// 调试辅助函数：打印元素信息
func printElementInfo(_ element: AXUIElement) {
    var role: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    print("   - 元素角色: \(role as? String ?? "未知")")
    
    var subrole: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
    print("   - 元素子角色: \(subrole as? String ?? "无")")
    
    // 列出所有可用属性
    var attrNames: CFArray?
    if AXUIElementCopyAttributeNames(element, &attrNames) == .success {
        let names = attrNames as? [String] ?? []
        print("   - 可用属性: \(names.joined(separator: ", "))")
        print("   - 是否支持选中文字: \(names.contains(kAXSelectedTextAttribute as String))")
    }
}

// 方法2: 通过 Range + Value 获取
func getTextViaRange(_ element: AXUIElement) -> String? {
    var rangeValue: CFTypeRef?
    let rangeErr = AXUIElementCopyAttributeValue(
        element,
        kAXSelectedTextRangeAttribute as CFString,
        &rangeValue
    )
    
    guard rangeErr == .success, let range = rangeValue else {
        print("❌ 无法获取选中范围")
        return nil
    }
    
    print("✅ 获取到选中范围: \(range)")
    
    var value: CFTypeRef?
    let valueErr = AXUIElementCopyAttributeValue(
        element,
        kAXValueAttribute as CFString,
        &value
    )
    
    guard valueErr == .success, let fullText = value as? String else {
        print("❌ 无法获取完整文本")
        return nil
    }
    
    print("📝 完整文本: '\(fullText)'")
    
    // 从 range 中提取选中部分
    var rangeStruct = CFRange()
    if AXValueGetValue(range as! AXValue, .cfRange, &rangeStruct) {
        let location = rangeStruct.location
        let length = rangeStruct.length
        
        if location != kCFNotFound && length > 0 {
            let start = fullText.index(fullText.startIndex, offsetBy: location)
            let end = fullText.index(start, offsetBy: length)
            let selectedText = String(fullText[start..<end])
            print("✅ 提取选中文字: '\(selectedText)'")
            return selectedText
        }
    }
    
    print("❌ 无法解析选中范围")
    return nil
}

func copyToClipboard(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
}

func copyImageToClipboard(_ image: NSImage) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects([image])
}

func getCurrentAppInfo() -> (bundleId: String, name: String, icon: NSImage?)? {
    guard let app = NSWorkspace.shared.frontmostApplication else {
        return nil
    }

    return (
        bundleId: app.bundleIdentifier ?? "unknown",
        name: app.localizedName ?? "Unknown App",
        icon: app.icon
    )
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

