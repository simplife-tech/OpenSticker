import SwiftUI

struct StickerPluginManagerView: View {
    @ObservedObject private var localization = L10n.shared
    @ObservedObject private var registry = StickerPluginRegistry.shared
    @State private var selection: String?
    @State private var confirmingRemoval = false
    @State private var errorMessage: String?
    @State private var showingLinkPrompt = false
    @State private var pluginLink = ""
    @State private var downloading = false
    @State private var pendingUpdate: PluginUpdate?
    @State private var showingUpdate = false
    @State private var showingUpToDate = false

    private struct PluginUpdate {
        let plugin: StickerPlugin
        let sourceURL: URL
        let manifest: Data
        let html: Data
        let script: Data
        let version: String
    }

    private var selected: StickerPlugin? { registry.plugins.first { $0.id == selection } }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.text("已安装"))
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
                    Menu {
                        Button(L10n.text("从本地文件夹导入…"), action: install)
                        Button(L10n.text("从 GitHub 链接导入…")) { showingLinkPrompt = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(L10n.text("导入或更新插件"))
                    .accessibilityLabel(L10n.text("导入或更新插件"))
                    .disabled(downloading)
                    Button { confirmingRemoval = true } label: { Image(systemName: "minus") }
                        .help(L10n.text("卸载所选插件"))
                        .accessibilityLabel(L10n.text("卸载所选插件"))
                        .disabled(selected == nil || downloading)
                    Spacer()
                    if downloading {
                        ProgressView().controlSize(.small)
                            .accessibilityLabel(L10n.text("正在下载插件"))
                    }
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
                        Text(plugin.description ?? L10n.text("暂无描述"))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Divider()
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 11) {
                            detail(L10n.text("版本"), plugin.manifest.version ?? L10n.text("未提供"))
                            detail(L10n.text("作者"), plugin.author ?? L10n.text("未提供"))
                            detail(L10n.text("安装时间"), plugin.installedAt?.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(localization.locale)) ?? L10n.text("未记录"))
                            detail(L10n.text("插件 ID"), plugin.id)
                        }
                        if let url = plugin.sourceURL {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L10n.text("来源链接")).font(.callout.weight(.medium))
                                Link(url.absoluteString, destination: url)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                Button(L10n.text("检查更新…")) { checkForUpdate(plugin, at: url) }
                                    .disabled(downloading)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(26)
                }
                .frame(minWidth: 310)
            } else {
                ContentUnavailableView(
                    L10n.text("暂无插件"),
                    systemImage: "puzzlepiece.extension",
                    description: Text(L10n.text("点击左下角的「＋」，从文件夹或 GitHub 导入。"))
                )
                .frame(minWidth: 310, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: registry.plugins, initial: true) { _, plugins in
            if selected == nil { selection = plugins.first?.id }
        }
        .alert(L10n.text("从 GitHub 导入插件"), isPresented: $showingLinkPrompt) {
            TextField("https://github.com/…/tree/main/…", text: $pluginLink)
            Button(L10n.text("取消"), role: .cancel) {}
            Button(L10n.text("导入"), action: installFromLink)
        } message: {
            Text(L10n.text("粘贴包含 manifest.json、index.html 和 plugin.js 的文件夹链接。"))
        }
        .alert(L10n.text("卸载插件？"), isPresented: $confirmingRemoval, presenting: selected) { plugin in
            Button(L10n.text("取消"), role: .cancel) {}
            Button(L10n.text("卸载"), role: .destructive) {
                do { try registry.uninstall(plugin.id) }
                catch { errorMessage = error.localizedDescription }
            }
        } message: { plugin in
            Text(L10n.format("卸载「%@」后，已有贴纸的数据会保留。", plugin.name))
        }
        .alert(L10n.text("有可用的插件更新"), isPresented: $showingUpdate, presenting: pendingUpdate) { update in
            Button(L10n.text("取消"), role: .cancel) { pendingUpdate = nil }
            Button(L10n.text("更新")) { applyUpdate(update) }
        } message: { update in
            Text(L10n.format("%@：%@ → %@", update.plugin.name,
                             update.plugin.manifest.version ?? "", update.version))
        }
        .alert(L10n.text("插件已是最新版本"), isPresented: $showingUpToDate) {
            Button(L10n.text("好"), role: .cancel) {}
        }
        .alert(L10n.text("操作失败"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(L10n.text("好"), role: .cancel) {}
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

    private func installFromLink() {
        guard !downloading else { return }
        downloading = true
        Task { @MainActor in
            defer { downloading = false }
            do {
                let source = try GitHubPluginSource(pluginLink)
                let files = try await download(source)
                selection = try registry.install(manifestData: files.0, htmlData: files.1,
                                                 scriptData: files.2, sourceURL: source.sourceURL)
                pluginLink = ""
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor private func download(_ source: GitHubPluginSource) async throws -> (Data, Data, Data) {
        let credentials = UpdateChecker.shared
        let token = source.usesStickerCredentials ? credentials.readToken() : nil
        do {
            return try await source.download(token: token)
        } catch let error as GitHubPluginSource.Failure
            where source.usesStickerCredentials && error.mayNeedCredentials {
            guard let entered = credentials.requestToken(replacing: token != nil, importing: true) else {
                throw CancellationError()
            }
            let files = try await source.download(token: entered)
            try? credentials.saveToken(entered)
            return files
        }
    }

    private func checkForUpdate(_ plugin: StickerPlugin, at url: URL) {
        guard !downloading else { return }
        downloading = true
        Task { @MainActor in
            defer { downloading = false }
            do {
                let source = try GitHubPluginSource(url.absoluteString)
                let (manifest, html, script) = try await download(source)
                let latest = try JSONDecoder().decode(StickerPlugin.Manifest.self, from: manifest)
                guard latest.id == plugin.id || latest.previousIDs?.contains(plugin.id) == true else {
                    errorMessage = L10n.text("插件已变化或来源不匹配，请重新检查。")
                    return
                }
                guard let version = latest.version, let available = UpdateChecker.versionParts(version),
                      let installed = plugin.manifest.version.flatMap(UpdateChecker.versionParts) else {
                    errorMessage = L10n.text("无法比较插件版本，请使用数字版本号。")
                    return
                }
                guard installed.lexicographicallyPrecedes(available) else {
                    showingUpToDate = true
                    return
                }
                pendingUpdate = PluginUpdate(plugin: plugin, sourceURL: source.sourceURL,
                                             manifest: manifest, html: html, script: script, version: version)
                showingUpdate = true
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func applyUpdate(_ update: PluginUpdate) {
        defer { pendingUpdate = nil }
        do {
            selection = try registry.install(manifestData: update.manifest, htmlData: update.html,
                                             scriptData: update.script, sourceURL: update.sourceURL,
                                             updating: update.plugin)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func install() {
        let picker = NSOpenPanel()
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.prompt = L10n.text("导入插件")
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
