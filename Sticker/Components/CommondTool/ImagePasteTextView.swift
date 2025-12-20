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

    func makeNSView(context: Context) -> NSTextView {
        let textView = PasteAwareTextView()
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: 14)
        textView.isRichText = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.viewModel = viewModel
        return textView
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        if nsView.string != viewModel.text {
            nsView.string = viewModel.text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let viewModel: StickerCommandViewModel

        init(viewModel: StickerCommandViewModel) {
            self.viewModel = viewModel
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            viewModel.text = tv.string
        }
    }
}

final class PasteAwareTextView: NSTextView {

    weak var viewModel: StickerCommandViewModel?

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general

        if let data = pb.data(forType: .tiff),
           let image = NSImage(data: data) {
            viewModel?.pastedImage = image
            return
        }

        super.paste(sender)
    }
}
