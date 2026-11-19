import SwiftUI

struct StickerPluginManagerView: View {
    @ObservedObject private var registry = StickerPluginRegistry.shared
    @State private var selection: String?
    @State private var confirmingRemoval = false
    @State private var errorMessage: String?

    private var selected: StickerPlugin? { registry.plugins.first { $0.id == selection } }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Text("已安装")
                    .font(.headline)
                    .padding(14)
                List(registry.plugins, selection: $selection) { plugin in
                    Label(plugin.name, systemImage: "puzzlepiece.extension")
                        .padding(.vertical, 5)
                        .tag(plugin.id)
                }
                .listStyle(.sidebar)
                Divider()
                HStack(spacing: 4) {
                    Button(action: install) { Image(systemName: "plus") }
                        .help("导入或更新插件")
                        .accessibilityLabel("导入或更新插件")
                    Button { confirmingRemoval = true } label: { Image(systemName: "minus") }
                        .help("卸载所选插件")
                        .accessibilityLabel("卸载所选插件")
                        .disabled(selected == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(10)
            }
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
            .background(.background.secondary)

            if let plugin = selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Label(plugin.name, systemImage: "puzzlepiece.extension")
                            .font(.title2.weight(.semibold))
                        Text(plugin.manifest.description ?? "暂无描述")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Divider()
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 11) {
                            detail("版本", plugin.manifest.version ?? "未提供")
                            detail("作者", plugin.manifest.author ?? "未提供")
                            detail("安装时间", plugin.installedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未记录")
                            detail("插件 ID", plugin.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(26)
                }
                .frame(minWidth: 310)
            } else {
                ContentUnavailableView(
                    "暂无插件",
                    systemImage: "puzzlepiece.extension",
                    description: Text("点击左下角的「＋」导入插件文件夹。")
                )
                .frame(minWidth: 310, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: registry.plugins, initial: true) { _, plugins in
            if selected == nil { selection = plugins.first?.id }
        }
        .alert("卸载插件？", isPresented: $confirmingRemoval, presenting: selected) { plugin in
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) {
                do { try registry.uninstall(plugin.id) }
                catch { errorMessage = error.localizedDescription }
            }
        } message: { plugin in
            Text("卸载「\(plugin.name)」后，已有贴纸的数据会保留。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
        .font(.callout)
    }

    private func install() {
        let picker = NSOpenPanel()
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.prompt = "导入插件"
        picker.begin { result in
            guard result == .OK, let url = picker.url else { return }
            do {
                selection = try registry.install(from: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
