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

            VStack(spacing: 0) {

                TextField("输入贴纸内容", text: $viewModel.text)
                    .focused($focused)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .offset(y: -4)
                    .onSubmit { execute() }

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
            DispatchQueue.main.async {
                focused = true
            }
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onExitCommand { onClose() } // Esc
    }

    // MARK: - Action Row

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

    // MARK: - Keyboard

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 126: // ↑
                viewModel.selectedIndex = max(viewModel.selectedIndex - 1, 0)
                return nil   // 吃掉事件，防止 TextField 光标移动

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

    // MARK: - Execute

    private func execute() {
        let action = actions[viewModel.selectedIndex]
        onAction(action, viewModel.text)
        onClose()
    }
}
