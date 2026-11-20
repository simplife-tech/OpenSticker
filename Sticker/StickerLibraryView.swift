import SwiftUI

struct StickerLibraryView: View {
    @ObservedObject private var localization = L10n.shared
    @ObservedObject var store: StickerStore
    @State private var query = ""
    @State private var editing: Sticker?

    @State private var groupFilter = "all"
    @State private var editingGroup = false
    @State private var deletingGroup = false
    @State private var groupName = ""
    @State private var groupToEdit: UUID?
    @State private var groupError: String?

    private var selectedGroup: StickerGroup? {
        store.groups.first { $0.id.uuidString == groupFilter }
    }

    private var results: [Sticker] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.stickers.reversed().filter { sticker in
            let id = store.validGroupID(sticker.groupID)?.uuidString ?? "default"
            return (groupFilter == "all" || groupFilter == id)
                && (term.isEmpty || title(for: sticker).localizedStandardContains(term))
        }
    }

    var body: some View {
        HSplitView {
            groupSidebar
                .frame(minWidth: 164, idealWidth: 188, maxWidth: 240)
            stickerList
                .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert(groupToEdit == nil ? L10n.text("新建分组") : L10n.text("重命名分组"), isPresented: $editingGroup) {
            TextField(L10n.text("分组名称"), text: $groupName)
            Button(L10n.text("取消"), role: .cancel) {}
            Button(L10n.text("保存")) { performGroupAction { try store.saveGroup(id: groupToEdit, name: groupName) } }
        }
        .alert(L10n.text("删除分组？"), isPresented: $deletingGroup) {
            Button(L10n.text("取消"), role: .cancel) {}
            Button(L10n.text("删除"), role: .destructive) {
                guard let id = groupToEdit else { return }
                performGroupAction {
                    try store.removeGroup(id)
                    groupFilter = "default"
                }
            }
        } message: {
            Text(L10n.text("组内贴纸会移回「默认」。"))
        }
        .alert(L10n.text("分组操作失败"), isPresented: Binding(
            get: { groupError != nil }, set: { if !$0 { groupError = nil } }
        )) {
            Button(L10n.text("好"), role: .cancel) {}
        } message: { Text(groupError ?? "") }
        .onReceive(store.$groups) { groups in
            if groupFilter != "all" && groupFilter != "default"
                && !groups.contains(where: { $0.id.uuidString == groupFilter }) {
                groupFilter = "all"
            }
        }
        .sheet(item: $editing) { sticker in
            StickerLibraryEditor(sticker: sticker, store: store)
        }
    }

    private var groupSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text("分组"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            List(selection: $groupFilter) {
                Label(L10n.text("全部贴纸"), systemImage: "square.stack").tag("all")
                Label(L10n.text("默认"), systemImage: "tray").tag("default")
                ForEach(store.groups) { group in
                    Label(group.name, systemImage: "folder")
                        .tag(group.id.uuidString)
                        .contextMenu {
                            Button(L10n.text("重命名…")) { editGroup(group) }
                            Button(L10n.text("上移")) { reorder(group, by: -1) }
                                .disabled(!store.canMoveGroup(group.id, by: -1))
                            Button(L10n.text("下移")) { reorder(group, by: 1) }
                                .disabled(!store.canMoveGroup(group.id, by: 1))
                            Button(L10n.text("删除…"), role: .destructive) { confirmDeletion(group) }
                        }
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack(spacing: 4) {
                Button { editGroup(nil) } label: { Image(systemName: "plus") }
                    .help(L10n.text("新建分组"))
                    .accessibilityLabel(L10n.text("新建分组"))
                Button {
                    if let selectedGroup { editGroup(selectedGroup) }
                } label: {
                    Image(systemName: "pencil")
                }
                .help(L10n.text("重命名所选分组"))
                .accessibilityLabel(L10n.text("重命名所选分组"))
                .disabled(selectedGroup == nil)
                Button {
                    if let selectedGroup { confirmDeletion(selectedGroup) }
                } label: {
                    Image(systemName: "minus")
                }
                .help(L10n.text("删除所选分组"))
                .accessibilityLabel(L10n.text("删除所选分组"))
                .disabled(selectedGroup == nil)
                Spacer(minLength: 4)
                reorderButton(L10n.text("上移分组"), icon: "arrow.up", offset: -1)
                reorderButton(L10n.text("下移分组"), icon: "arrow.down", offset: 1)
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .background(.background.secondary)
    }

    private func reorderButton(_ title: String, icon: String, offset: Int) -> some View {
        Button {
            if let selectedGroup { reorder(selectedGroup, by: offset) }
        } label: {
            Image(systemName: icon)
        }
        .help(title)
        .accessibilityLabel(title)
        .disabled(selectedGroup.map { !store.canMoveGroup($0.id, by: offset) } ?? true)
    }

    private func reorder(_ group: StickerGroup, by offset: Int) {
        performGroupAction { try store.moveGroup(group.id, by: offset) }
    }

    private var stickerList: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(groupFilter == "all" ? L10n.text("全部贴纸") : selectedGroup?.name ?? L10n.text("默认"))
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(L10n.format("%lld 张", results.count))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L10n.text("搜索贴纸内容"), text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()
            if results.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: query.isEmpty ? "note" : "magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(query.isEmpty ? L10n.text("这里还没有贴纸") : L10n.text("没有匹配的贴纸"))
                        .font(.headline)
                    Text(query.isEmpty ? L10n.text("可以新建贴纸，或从其他分组移入。") : L10n.text("试试其他关键词"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results) { sticker in
                    HStack(spacing: 12) {
                        StickerThumbnail(content: sticker.content)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(title(for: sticker)).lineLimit(2)
                            Text(store.groupName(sticker.groupID))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu(L10n.text("移到")) {
                            Button(L10n.text("默认")) { move(sticker, to: nil) }
                            ForEach(store.groups) { group in
                                Button(group.name) { move(sticker, to: group.id) }
                            }
                        }
                        .fixedSize()
                        Button(L10n.text("编辑")) { editing = sticker }
                    }
                    .padding(.vertical, 7)
                }
                .listStyle(.plain)
            }
        }
    }

    private func confirmDeletion(_ group: StickerGroup) {
        groupToEdit = group.id
        deletingGroup = true
    }

    private func editGroup(_ group: StickerGroup?) {
        groupToEdit = group?.id
        groupName = group?.name ?? ""
        editingGroup = true
    }

    private func move(_ sticker: Sticker, to id: UUID?) {
        performGroupAction { try store.moveSticker(sticker.id, to: id) }
    }

    private func performGroupAction(_ action: () throws -> Void) {
        do { try action() }
        catch { groupError = error.localizedDescription }
    }

    private func title(for sticker: Sticker) -> String {
        switch sticker.content {
        case .text(let text): return text
        case .image(let payload): return L10n.format("图片 · %@", payload.filename)
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
                        .accessibilityLabel(L10n.text("图片文件不可用"))
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
    @ObservedObject private var localization = L10n.shared
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
            Text(L10n.text("编辑贴纸")).font(.title2.bold())
            if case .text = sticker.content {
                TextEditor(text: $text)
                    .font(.body)
                    .frame(height: 100)
                    .border(.quaternary)
                    .accessibilityLabel(L10n.text("贴纸内容"))
            } else {
                StickerThumbnail(content: sticker.content)
            }

            HStack {
                Spacer()
                Button(L10n.text("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.text("保存"), action: save).keyboardShortcut(.defaultAction)
                    .disabled(!hasContent)
            }
        }
        .padding(22)
        .frame(width: 480)
        .alert(L10n.text("无法保存贴纸"), isPresented: $saveFailed) {
            Button(L10n.text("好"), role: .cancel) {}
        } message: {
            Text(L10n.text("请检查贴纸是否仍存在，以及资源文件夹是否可写。"))
        }
    }

    private var scopeOptions: [StickerScope] {
        let common: Set<StickerScope> = [.global, .browser]
        return [.global, .browser] + scopes.union(sticker.scopes)
            .subtracting(common).sorted { $0.displayName < $1.displayName }
    }

    private var targetPlaceholder: String {
        switch scopeKind {
        case .app: return L10n.text("应用 Bundle ID")
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
            try store.edit(sticker.id, content: content, scopes: [.global])
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}

private extension StickerScope {
    var displayName: String {
        switch self {
        case .global: return L10n.text("全局")
        case .browser: return L10n.text("浏览器")
        case .app(let id): return L10n.format("应用 · %@", id)
        case .browserDomain(let domain): return L10n.format("域名 · %@", domain)
        case .browserUrl(let url): return L10n.format("网页 · %@", url)
        }
    }
}
