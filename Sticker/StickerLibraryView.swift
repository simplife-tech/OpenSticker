import SwiftUI

struct StickerLibraryView: View {
    @ObservedObject var store: StickerStore
    @State private var query = ""
    @State private var editing: Sticker?

    private var results: [Sticker] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.stickers.reversed().filter { sticker in
            term.isEmpty || title(for: sticker).localizedStandardContains(term)
                || sticker.scopes.contains { $0.displayName.localizedStandardContains(term) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索内容或可见范围", text: $query)
                Text("\(results.count) 张")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            Divider()
            if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: store.stickers.isEmpty ? "note" : "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(store.stickers.isEmpty ? "还没有贴纸" : "没有匹配的贴纸")
                        .font(.headline)
                    Text(store.stickers.isEmpty ? "按 ⌥N 新建一张贴纸" : "试试其他关键词")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results) { sticker in
                    HStack(spacing: 12) {
                        StickerThumbnail(content: sticker.content)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(title(for: sticker)).lineLimit(2)
                            Text(sticker.scopes.map(\.displayName).sorted().joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("编辑") { editing = sticker }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .sheet(item: $editing) { sticker in
            StickerLibraryEditor(sticker: sticker, store: store)
        }
    }

    private func title(for sticker: Sticker) -> String {
        switch sticker.content {
        case .text(let text): return text
        case .image(let payload): return "图片 · \(payload.filename)"
        }
    }
}

private struct StickerThumbnail: View {
    let content: StickerContent

    var body: some View {
        Group {
            if case .image(let payload) = content {
                if let image = NSImage(contentsOf: payload.fileURL) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: "exclamationmark.triangle")
                        .accessibilityLabel("图片文件不可用")
                }
            } else {
                Image(systemName: "text.alignleft")
            }
        }
        .frame(width: 44, height: 44)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StickerLibraryEditor: View {
    let sticker: Sticker
    let store: StickerStore
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var scopes: Set<StickerScope>
    @State private var scopeKind: ScopeKind = .app
    @State private var target = ""
    @State private var saveFailed = false

    private enum ScopeKind: String, CaseIterable {
        case app = "应用"
        case domain = "域名"
        case page = "网页"
    }

    init(sticker: Sticker, store: StickerStore) {
        self.sticker = sticker
        self.store = store
        _scopes = State(initialValue: sticker.scopes)
        if case .text(let value) = sticker.content {
            _text = State(initialValue: value)
        } else {
            _text = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("编辑贴纸").font(.title2.bold())
            if case .text = sticker.content {
                TextEditor(text: $text)
                    .font(.body)
                    .frame(height: 100)
                    .border(.quaternary)
                    .accessibilityLabel("贴纸内容")
            } else {
                StickerThumbnail(content: sticker.content)
            }

            Text("可见范围").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(scopeOptions, id: \.self) { scope in
                        Toggle(scope.displayName, isOn: Binding(
                            get: { scopes.contains(scope) },
                            set: { enabled in
                                if enabled { scopes.insert(scope) }
                                else { scopes.remove(scope) }
                            }
                        ))
                        .help(scope.displayName)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 112)

            HStack {
                Picker("类型", selection: $scopeKind) {
                    ForEach(ScopeKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                TextField(targetPlaceholder, text: $target)
                Button("添加范围") {
                    if let scope = proposedScope {
                        scopes.insert(scope)
                        target = ""
                    }
                }
                .disabled(proposedScope == nil)
            }

            HStack {
                if scopes.isEmpty {
                    Text("请选择至少一个范围").foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存", action: save).keyboardShortcut(.defaultAction)
                    .disabled(scopes.isEmpty || !hasContent)
            }
        }
        .padding(22)
        .frame(width: 480)
        .alert("无法保存贴纸", isPresented: $saveFailed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请检查贴纸是否仍存在，以及资源文件夹是否可写。")
        }
    }

    private var scopeOptions: [StickerScope] {
        let common: Set<StickerScope> = [.global, .browser]
        return [.global, .browser] + scopes.union(sticker.scopes)
            .subtracting(common).sorted { $0.displayName < $1.displayName }
    }

    private var targetPlaceholder: String {
        switch scopeKind {
        case .app: return "应用 Bundle ID"
        case .domain: return "example.com"
        case .page: return "https://example.com/page"
        }
    }

    private var proposedScope: StickerScope? {
        let value = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return nil
        }
        switch scopeKind {
        case .app:
            guard value.contains("."), !value.contains("/") else { return nil }
            return .app(bundleId: value)
        case .domain:
            guard value.contains("."), !value.contains("/"), !value.contains(":") else { return nil }
            return .browserDomain(domain: value.lowercased())
        case .page:
            guard let url = URL(string: value), url.host != nil,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            return .browserUrl(url: value)
        }
    }

    private var hasContent: Bool {
        if case .image = sticker.content { return true }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        var content = sticker.content
        if case .text = content { content = .text(text) }
        do {
            try store.edit(sticker.id, content: content, scopes: scopes)
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}

private extension StickerScope {
    var displayName: String {
        switch self {
        case .global: return "全局"
        case .browser: return "浏览器"
        case .app(let id): return "应用 · \(id)"
        case .browserDomain(let domain): return "域名 · \(domain)"
        case .browserUrl(let url): return "网页 · \(url)"
        }
    }
}
