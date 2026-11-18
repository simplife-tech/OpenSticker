//
//  ImagePasteTextView.swift
//  Sticker
//
//  Created by 周屹峰 on 2025/12/20.
//


import SwiftUI
import AppKit

struct ImagePasteTextView: NSViewRepresentable {

    @ObservedObject var viewModel: StickerCommandViewModel
    var onWindowChanged: (NSWindow?) -> Void = { _ in }

    func makeNSView(context: Context) -> NSView {

        let container = InputContainer()
        container.onWindowChanged = onWindowChanged

        // ===== TextView =====
        let textView = NSTextView()
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 26)
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 6, height: 8)

        // 允许粘贴图片
        textView.isEditable = true
        textView.isSelectable = true

        // ===== Placeholder =====
        let placeholder = NSTextField(labelWithString: "输入文字或粘贴图片")
        placeholder.font = NSFont.systemFont(ofSize: 18)
        placeholder.textColor = NSColor.secondaryLabelColor
        placeholder.backgroundColor = .clear
        placeholder.isBordered = false
        placeholder.isEditable = false

        // ===== Layout =====
        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholder.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(textView)
        container.addSubview(placeholder)

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textView.topAnchor.constraint(equalTo: container.topAnchor),
            textView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            placeholder.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            placeholder.topAnchor.constraint(equalTo: container.topAnchor, constant: 10)
        ])

        context.coordinator.textView = textView
        context.coordinator.placeholder = placeholder

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.updatePlaceholderVisibility()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    private final class InputContainer: NSView {
        var onWindowChanged: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChanged?(window)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {

        let viewModel: StickerCommandViewModel

        weak var textView: NSTextView?
        weak var placeholder: NSTextField?

        init(viewModel: StickerCommandViewModel) {
            self.viewModel = viewModel
        }

        func textDidChange(_ notification: Notification) {
            viewModel.text = textView?.string ?? ""
            updatePlaceholderVisibility()
        }

        func updatePlaceholderVisibility() {
            let hasText = !(textView?.string.isEmpty ?? true)
            let hasImage = false
            placeholder?.isHidden = hasText || hasImage
        }
    }
}

