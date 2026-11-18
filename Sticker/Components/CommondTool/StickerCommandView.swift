import SwiftUI

struct StickerCommandView: View {
    @ObservedObject var viewModel: StickerCommandViewModel
    let onCreate: () -> Void
    let onClose: () -> Void
    @State private var showingColors = false
    @State private var handle = MarkdownStickerEditor.Handle()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("新建贴纸").font(.headline)
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
                    .disabled(viewModel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
