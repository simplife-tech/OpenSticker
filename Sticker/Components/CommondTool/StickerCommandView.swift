//
//  StickerCommandView.swift
//  Sticker
//
//  Created by 周屹峰 on 2025/12/20.
//

import SwiftUI
import AppKit

struct StickerCommandView: View {

    @ObservedObject var viewModel: StickerCommandViewModel
    @FocusState private var focused: Bool

    let actions: [ActionItem]
    let onAction: (ActionItem, String) -> Void
    let onClose: () -> Void

    @State private var keyMonitor: Any?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.windowBackgroundColor))

            VStack(spacing: 8) {

                // =====================
                // 输入区（支持图片粘贴）
                // =====================
                VStack(spacing: 6) {

                    ImagePasteTextView(viewModel: viewModel)
                        .frame(height: 56)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.black.opacity(0.05))
                        )

                    // 🖼 图片回显
                    if let image = viewModel.pastedImage {
                        ZStack(alignment: .topTrailing) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 120)
                                .cornerRadius(8)

                            Button {
                                viewModel.clearImage()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white)
                                    .background(.black.opacity(0.6))
                                    .clipShape(Circle())
                            }
                            .padding(6)
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.top, 2)

                // =====================
                // Action 列表（你原来的）
                // =====================
                VStack(spacing: 2) {
                    ForEach(actions.indices, id: \.self) { index in
                        actionRow(actions[index], index: index)
                    }
                }
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(10)
            }
        }
        .padding(2)
        .frame(width: 520)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onExitCommand { onClose() }
    }

    // MARK: - Action Row（未改）

    private func actionRow(_ action: ActionItem, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(action.title)
                .font(.system(size: 14, weight: .medium))
            if let subtitle = action.subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            viewModel.selectedIndex == index
            ? Color.accentColor.opacity(0.15)
            : Color.clear
        )
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                viewModel.selectedIndex = index
            }
        }
        .onTapGesture {
            viewModel.selectedIndex = index
            execute()
        }
    }


    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers == "v" {

                if let image = NSPasteboard.general.readObjects(
                    forClasses: [NSImage.self],
                    options: nil
                )?.first as? NSImage {

                    viewModel.pastedImage = image
                    return nil
                }
            }
            switch event.keyCode {
            case 126: // ↑
                viewModel.selectedIndex = max(viewModel.selectedIndex - 1, 0)
                return nil

            case 125: // ↓
                viewModel.selectedIndex = min(
                    viewModel.selectedIndex + 1,
                    actions.count - 1
                )
                return nil

            case 36: // Enter
                execute()
                return nil

            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }


    private func execute() {
        let action = actions[viewModel.selectedIndex]
        onAction(action, viewModel.text)
        onClose()
    }

    
}
