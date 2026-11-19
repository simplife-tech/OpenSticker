import SwiftUI

struct StickerCommandView: View {
    @ObservedObject var viewModel: StickerCommandViewModel
    @ObservedObject private var registry = StickerPluginRegistry.shared
    private var plugin: StickerPlugin? { registry.plugins.first { $0.id == viewModel.pluginID } }
    let onCreate: () -> Void
    let onClose: () -> Void
    @State private var showingTypes = false
    @State private var typeButtonHovered = false
    @State private var hoveredTypeID: String?
    @State private var showingColors = false
    @State private var handle = MarkdownStickerEditor.Handle()

    private var typeSelector: some View {
        Button {
            showingTypes.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: plugin == nil ? "note.text" : "puzzlepiece.extension")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(plugin?.name ?? "普通贴纸")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.primary.opacity(showingTypes || typeButtonHovered ? 0.09 : 0.04), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            typeButtonHovered = hovering
        }
        .accessibilityLabel("贴纸类型")
        .accessibilityValue(plugin?.name ?? "普通贴纸")
        .popover(isPresented: $showingTypes, arrowEdge: .bottom) {
            ScrollView {
                VStack(spacing: 3) {
                    typeRow(id: "", name: "普通贴纸", icon: "note.text")
                    ForEach(registry.plugins) { item in
                        typeRow(id: item.id, name: item.name, icon: "puzzlepiece.extension")
                    }
                }
                .padding(6)
            }
            .frame(width: 220, height: min(252, CGFloat(registry.plugins.count + 1) * 35 + 12))
            .onDisappear {
                hoveredTypeID = nil
            }
        }
        .onReceive(registry.$plugins) { plugins in
            if !viewModel.pluginID.isEmpty && !plugins.contains(where: { $0.id == viewModel.pluginID }) {
                selectType("")
            }
        }
    }

    private func typeRow(id: String, name: String, icon: String) -> some View {
        let selected = viewModel.pluginID == id
        let hovered = hoveredTypeID == id
        return Button {
            selectType(id)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(name).lineLimit(1)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.accentColor.opacity(hovered ? 0.17 : 0.10)
                                   : Color.primary.opacity(hovered ? 0.06 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredTypeID = id
            } else if hoveredTypeID == id {
                hoveredTypeID = nil
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func selectType(_ id: String) {
        if id != viewModel.pluginID {
            viewModel.pluginValues = [:]
            viewModel.pluginID = id
        }
        showingTypes = false
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                typeSelector
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("关闭并保留草稿")
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 4)

            Group {
                if let plugin {
                    StickerPluginWebView(plugin: plugin, mode: .create, values: $viewModel.pluginValues)
                        .id(plugin.id)
                } else {
                    ZStack(alignment: .topLeading) {
                        if viewModel.text.isEmpty {
                            Text("写点什么……")
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 18)
                                .padding(.top, 14)
                                .allowsHitTesting(false)
                        }
                        MarkdownStickerEditor(
                            source: viewModel.text, width: 420, isEditing: true, showsSource: false,
                            handle: handle, onFocusChanged: { _ in },
                            onChange: { viewModel.text = $0 }
                        )
                    }
                }
            }
            .frame(height: 196)

            Divider().opacity(0.4)
            HStack(spacing: 8) {
                Button {
                    showingColors.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.color.tint.opacity(0.75))
                            .frame(width: 15, height: 15)
                            .overlay { Circle().strokeBorder(.primary.opacity(0.12)) }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(.primary.opacity(0.04), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("贴纸颜色")
                .popover(isPresented: $showingColors, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("贴纸颜色").font(.subheadline.weight(.semibold))
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 10), count: 6), spacing: 10) {
                            ForEach(StickerPaperColor.allCases, id: \.self) { color in
                                Button {
                                    viewModel.color = color
                                    showingColors = false
                                } label: {
                                    Circle()
                                        .fill(color.tint.opacity(color == .neutral ? 0.18 : 0.70))
                                        .frame(width: 26, height: 26)
                                        .overlay {
                                            if viewModel.color == color {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .bold))
                                            }
                                        }
                                        .overlay { Circle().strokeBorder(.primary.opacity(0.10)) }
                                }
                                .buttonStyle(.plain)
                                .help(color.title)
                                .accessibilityLabel(color.title)
                            }
                        }
                    }
                    .padding(16)
                }

                Text("回车换行").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: onCreate) {
                    HStack(spacing: 10) {
                        Text("创建").fontWeight(.medium)
                        Text("⌘↵").foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(.horizontal, 4)
                }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(plugin == nil && viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 420)

        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(viewModel.color.tint.opacity(0.12))
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onAppear {
            DispatchQueue.main.async { handle.beginEditing(at: nil) }
        }
        .onExitCommand(perform: onClose)
    }
}
