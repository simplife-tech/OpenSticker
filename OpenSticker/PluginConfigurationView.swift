import SwiftUI

struct PluginConfigurationView: View {
    @ObservedObject private var registry = StickerPluginRegistry.shared
    @ObservedObject private var configuration = PluginConfiguration.shared
    @ObservedObject private var localization = L10n.shared
    @AppStorage(PluginAI.modelPreferenceKey) private var savedModel = ""
    @AppStorage(PluginAI.baseURLPreferenceKey) private var savedBaseURL = ""
    @State private var modelDraft = ""
    @State private var baseURLDraft = ""
    @State private var apiKeyDraft = ""
    @State private var savedAPIKey: String?
    @State private var drafts: [String: String] = [:]
    @State private var configured: Set<String> = []
    @State private var removing: Set<String> = []
    @State private var authorizing: StickerPlugin?
    @State private var authorizingNetwork: StickerPlugin?
    @State private var authorizingAI: StickerPlugin?
    @State private var error: String?

    private var requestingPlugins: [StickerPlugin] {
        registry.plugins.filter { !($0.manifest.configuration ?? []).isEmpty }
    }

    private var networkingPlugins: [StickerPlugin] {
        registry.plugins.filter { $0.manifest.requestsNetwork }
    }

    private var aiPlugins: [StickerPlugin] {
        registry.plugins.filter { $0.manifest.usesLocalAI == true }
    }

    private func networkDestinations(_ plugin: StickerPlugin, separator: String) -> String {
        var destinations = plugin.manifest.networkHosts ?? []
        if !plugin.manifest.reservedLoopbackKeys.isEmpty {
            destinations.append(L10n.text("在贴纸上确认的本机地址"))
        }
        destinations += (plugin.manifest.loopbackProxyHosts ?? []).map {
            L10n.format("通过本机代理读取 %@", $0)
        }
        if let listener = plugin.manifest.listener {
            destinations.append(L10n.format("监听 %@，转发到 %@", "127.0.0.1:\(listener.port)\(listener.path)",
                                            listener.upstream.absoluteString))
        }
        return destinations.joined(separator: separator)
    }

    private var fields: [PluginConfigurationField] {
        requestingPlugins.flatMap { $0.manifest.configuration ?? [] }
    }

    private var fieldsByNamespace: [String: [String]] {
        Dictionary(grouping: Set(fields.map(\.key))) { key in
            String(key.prefix(while: { $0 != "/" }))
        }
    }

    private var namespaces: [String] {
        fieldsByNamespace.keys.sorted()
    }

    var body: some View {
        content.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            Form {
                Section(L10n.text("AI 能力")) {
                    LabeledContent("Base URL") {
                        TextField("Base URL", text: $baseURLDraft)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .foregroundStyle(Color(nsColor: .controlTextColor))
                            .multilineTextAlignment(.leading)
                            .frame(width: 260)
                            .overlay(alignment: .leading) {
                                if baseURLDraft.isEmpty {
                                    Text("https://api.example.com/v1")
                                        .foregroundStyle(Color(nsColor: .placeholderTextColor))
                                        .padding(.leading, 6)
                                        .allowsHitTesting(false)
                                        .accessibilityHidden(true)
                                }
                            }
                    }
                    LabeledContent("API Key") {
                        SecureField("API Key", text: $apiKeyDraft)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .frame(width: 260)
                            .disabled(savedAPIKey == nil)
                    }
                    LabeledContent(L10n.text("模型名称")) {
                        TextField(L10n.text("模型名称"), text: $modelDraft)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .frame(width: 260)
                    }
                }
                ForEach(namespaces, id: \.self) { namespace in
                    Section {
                        ForEach(fieldsByNamespace[namespace, default: []].sorted(), id: \.self) { key in
                            field(for: key)
                        }
                    } header: {
                        Label(namespace, systemImage: "folder")
                    }
                }
                if !requestingPlugins.isEmpty {
                    Section(L10n.text("插件读取权限")) {
                        ForEach(requestingPlugins) { plugin in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(plugin.name)
                                    let namespaces = Set((plugin.manifest.configuration ?? []).map {
                                        String($0.key.prefix(while: { $0 != "/" }))
                                    })
                                    Text(namespaces.sorted().joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if configuration.isAuthorized(plugin) {
                                    Button(L10n.text("撤销读取权限")) {
                                        configuration.setAuthorized(false, for: plugin)
                                    }
                                } else {
                                    Button(L10n.text("授权读取…")) { authorizing = plugin }
                                }
                            }
                        }
                    }
                }
                if !networkingPlugins.isEmpty {
                    Section(L10n.text("插件网络权限")) {
                        ForEach(networkingPlugins) { plugin in
                            LabeledContent {
                                if configuration.isNetworkAuthorized(plugin) {
                                    Button(L10n.text("撤销网络权限")) {
                                        configuration.setNetworkAuthorized(false, for: plugin)
                                    }
                                } else {
                                    Button(L10n.text("授权联网…")) { authorizingNetwork = plugin }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(plugin.name)
                                    Text(networkDestinations(plugin, separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if !aiPlugins.isEmpty {
                    Section(L10n.text("AI 能力权限")) {
                        ForEach(aiPlugins) { plugin in
                            LabeledContent(plugin.name) {
                                if configuration.isAIAuthorized(plugin) {
                                    Button(L10n.text("撤销 AI 权限")) {
                                        configuration.setAIAuthorized(false, for: plugin)
                                    }
                                } else {
                                    Button(L10n.text("授权使用 AI…")) { authorizingAI = plugin }
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: .infinity)
            Divider()
            HStack {
                Spacer()
                Button(L10n.text("保存"), action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(drafts.isEmpty && removing.isEmpty && modelDraft == savedModel && baseURLDraft == savedBaseURL && apiKeyDraft == (savedAPIKey ?? ""))
            }
            .padding(14)
        }
        .onAppear {
            modelDraft = savedModel
            baseURLDraft = savedBaseURL
            do {
                let key = try PluginAI.apiKey()
                savedAPIKey = key
                apiKeyDraft = key
            } catch {
                self.error = error.localizedDescription
            }
            reload()
        }
        .alert(L10n.text("允许插件读取配置？"), isPresented: Binding(
            get: { authorizing != nil }, set: { if !$0 { authorizing = nil } }
        ), presenting: authorizing) { plugin in
            Button(L10n.text("取消"), role: .cancel) { authorizing = nil }
            Button(L10n.text("允许")) {
                guard registry.plugins.contains(plugin) else { return }
                configuration.setAuthorized(true, for: plugin)
                authorizing = nil
            }
        } message: { plugin in
            let keys = (plugin.manifest.configuration ?? []).map(\.key).joined(separator: ", ")
            Text(L10n.format("「%@」可以读取这些配置的原始值，包括密码和密钥。只授权你信任的插件。\n%@", plugin.name, keys))
        }
        .alert(L10n.text("允许插件联网？"), isPresented: Binding(
            get: { authorizingNetwork != nil }, set: { if !$0 { authorizingNetwork = nil } }
        ), presenting: authorizingNetwork) { plugin in
            Button(L10n.text("取消"), role: .cancel) { authorizingNetwork = nil }
            Button(L10n.text("允许")) {
                if registry.plugins.contains(plugin) {
                    configuration.setNetworkAuthorized(true, for: plugin)
                }
                authorizingNetwork = nil
            }
        } message: { plugin in
            let hosts = networkDestinations(plugin, separator: ", ")
            Text(L10n.format("「%@」可以向下列域名发送数据。只授权你信任的插件。\n%@", plugin.name, hosts))
        }
        .alert(L10n.text("允许插件使用 AI 能力？"), isPresented: Binding(
            get: { authorizingAI != nil }, set: { if !$0 { authorizingAI = nil } }
        ), presenting: authorizingAI) { plugin in
            Button(L10n.text("取消"), role: .cancel) { authorizingAI = nil }
            Button(L10n.text("允许")) {
                if registry.plugins.contains(plugin) {
                    configuration.setAIAuthorized(true, for: plugin)
                }
                authorizingAI = nil
            }
        } message: { plugin in
            Text(L10n.format("「%@」可以向你配置的模型服务发送请求。只授权你信任的插件。", plugin.name))
        }
        .alert(L10n.text("操作失败"), isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) {
            Button(L10n.text("好"), role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func field(for key: String) -> some View {
        let declarations = fields.filter { $0.key == key }
        let secret = declarations.contains { $0.type == .secret }
        let title = declarations.first(where: { $0.type == .secret })?.title ?? declarations.first?.title ?? key
        let value = Binding(
            get: { drafts[key, default: ""] },
            set: { value in
                if value.isEmpty { drafts.removeValue(forKey: key) }
                else {
                    drafts[key] = value
                    removing.remove(key)
                }
            }
        )
        let placeholder = L10n.text(configured.contains(key) ? "已配置" : "输入新值")
        return LabeledContent {
            HStack(spacing: 8) {
                if removing.contains(key) {
                    Text(L10n.text("保存后清除"))
                        .foregroundStyle(.secondary)
                    Button(L10n.text("取消")) { removing.remove(key) }
                } else {
                    Group {
                        if secret {
                            SecureField(title, text: value, prompt: Text(placeholder))
                        } else {
                            TextField(title, text: value, prompt: Text(placeholder))
                        }
                    }
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120, idealWidth: 200, maxWidth: 260)

                    if configured.contains(key) {
                        Button(L10n.text("清除")) {
                            drafts.removeValue(forKey: key)
                            removing.insert(key)
                        }
                    }
                }
            }
            .controlSize(.small)
        } label: {
            Text(title)
                .help(key)
        }
    }

    private func save() {
        let model = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard baseURL.isEmpty || PluginAI.endpoint(baseURL) != nil else {
            error = L10n.text("请输入有效的 HTTP 或 HTTPS Base URL。")
            return
        }
        guard model.utf8.count <= 256, key.utf8.count <= 4096,
              key.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else {
            error = L10n.text("模型名称或 API Key 无效。")
            return
        }
        guard drafts.values.allSatisfy({ $0.utf8.count <= 16_384 }) else {
            error = L10n.text("配置值过长。")
            return
        }
        do {
            if !drafts.isEmpty || !removing.isEmpty {
                try configuration.apply(drafts, removing: removing)
                reload()
            }
            if let savedAPIKey, key != savedAPIKey {
                try PluginAI.saveAPIKey(key)
                self.savedAPIKey = key
            }
            self.savedBaseURL = baseURL
            baseURLDraft = baseURL
            apiKeyDraft = key
            savedModel = model
            modelDraft = model
            drafts = [:]
            removing = []
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reload() {
        do { configured = try configuration.configuredKeys() }
        catch { self.error = error.localizedDescription }
    }
}
