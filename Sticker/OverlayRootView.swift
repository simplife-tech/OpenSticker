//
//  OverlayRootView.swift
//  Sticker
//
//  Created by zhouyifeng on 2025/12/19.
//


import SwiftUI

struct OverlayRootView: View {
    @ObservedObject private var localization = L10n.shared
    @ObservedObject var store: StickerStore
    @ObservedObject var contextController: ContextController

    var topInset: CGFloat
    let onFramesChanged: ([CGRect]) -> Void
    let onResizeRegionsChanged: ([StickerResizeRegion]) -> Void
    let onDraggingChanged: (Bool) -> Void
    let onEdit: () -> Void
    let onManageGroups: () -> Void

    @State private var showingGroups = false
    @State private var groupQuery = ""
    @State private var highlightedGroup = 0
    @State private var hoveredGroup: Int?
    @State private var manageGroupsHovered = false
    private enum GroupFocus: Hashable { case panel, search }
    @FocusState private var groupPickerFocus: GroupFocus?
    @State private var draggingID: UUID?
    @State private var isOverDeleteBar = false
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        GeometryReader { geo in
            let targetWidth = min(300, max(0, geo.size.width - 32))
            let target = CGRect(x: (geo.size.width - targetWidth) / 2, y: topInset + 14,
                                width: targetWidth, height: 48)
            ZStack(alignment: .top) {
                if draggingID != nil {
                    DeleteBarView(active: isOverDeleteBar)
                        .frame(width: target.width, height: target.height)
                        .position(x: target.midX, y: target.midY)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }

                // Stickers
                ForEach(store.stickers.filter { store.validGroupID($0.groupID) == store.activeGroupID }) { sticker in
                    StickerView(
                        sticker: binding(for: sticker),
                        draggingID: $draggingID,
                        isOverDeleteBar: $isOverDeleteBar,
                        deleteTarget: target,
                        screenSize: geo.size,
                        onDelete: deleteSticker,
                        onEdit: onEdit,
                        onSaveText: { text in
                            guard let current = store.stickers.first(where: { $0.id == sticker.id }) else {
                                throw CocoaError(.fileNoSuchFile)
                            }
                            try store.edit(sticker.id, content: .text(text), scopes: current.scopes)
                        }
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .top) {
                if draggingID == nil {
                    VStack(spacing: 6) {
                        groupSwitcher
                        if showingGroups { groupsPanel }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: StickerFramePreference.self,
                                value: [proxy.frame(in: .named("stickerOverlay"))])
                        }
                    }
                    .padding(.top, topInset + 14)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: draggingID != nil)
            .coordinateSpace(name: "stickerOverlay")
            .onPreferenceChange(StickerFramePreference.self, perform: onFramesChanged)
            .onPreferenceChange(StickerResizeRegionPreference.self, perform: onResizeRegionsChanged)
            .background(Color.clear)
            .onChange(of: draggingID) { oldValue, newValue in
                onDraggingChanged(newValue != nil)
                if newValue != nil { showingGroups = false }
                if newValue == nil {
                    StickerStore.shared.save(StickerStore.shared.stickers)
                }
            }
        }
    }
    
    private var filteredGroups: [UUID?] {
        ([nil] + store.groups.map { Optional($0.id) }).filter {
            groupQuery.isEmpty || store.groupName($0).localizedStandardContains(groupQuery)
        }
    }

    private var groupSwitcher: some View {
        Button {
            showingGroups.toggle()
            if showingGroups {
                onEdit()
                groupQuery = ""
                highlightedGroup = filteredGroups.firstIndex(of: store.activeGroupID) ?? 0
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "square.stack")
                Text(store.groupName(store.activeGroupID)).lineLimit(1)
                Image(systemName: showingGroups ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(.regularMaterial, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text("切换贴纸分组"))
        .accessibilityValue(store.groupName(store.activeGroupID))
    }

    private var groupsPanel: some View {
        let ids = filteredGroups
        return VStack(spacing: 6) {
            if store.groups.count >= 7 {
                TextField(L10n.text("搜索分组…"), text: $groupQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($groupPickerFocus, equals: .search)
            }
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(ids.enumerated()), id: \.offset) { index, id in
                            groupRow(id, highlighted: !manageGroupsHovered && index == (hoveredGroup ?? highlightedGroup))
                                .onHover { hovering in
                                    if hovering { hoveredGroup = index }
                                    else if hoveredGroup == index { hoveredGroup = nil }
                                }
                                .id(index)
                        }
                        if ids.isEmpty {
                            Text(L10n.text("没有匹配的分组")).foregroundStyle(.secondary).padding(8)
                        }
                    }
                }
                .frame(height: min(224, CGFloat(max(1, ids.count)) * 32))
                .onChange(of: highlightedGroup) { _, index in scroll.scrollTo(index) }
            }
            Divider()
            Button {
                showingGroups = false
                onManageGroups()
            } label: {
                Label(L10n.text("管理分组…"), systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(manageGroupsHovered ? Color.accentColor.opacity(0.15) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { manageGroupsHovered = $0 }
        }
        .padding(8)
        .frame(width: 226)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        .focusable(store.groups.count < 7)
        .focusEffectDisabled()
        .focused($groupPickerFocus, equals: .panel)
        .onAppear { groupPickerFocus = store.groups.count >= 7 ? .search : .panel }
        .onDisappear {
            hoveredGroup = nil
            manageGroupsHovered = false
        }
        .onChange(of: groupQuery) { _, _ in
            hoveredGroup = nil
            highlightedGroup = 0
        }
        .onKeyPress(.upArrow) {
            hoveredGroup = nil
            highlightedGroup = max(0, highlightedGroup - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            hoveredGroup = nil
            highlightedGroup = min(max(ids.count - 1, 0), highlightedGroup + 1)
            return .handled
        }
        .onKeyPress(.return) {
            let index = hoveredGroup ?? highlightedGroup
            if ids.indices.contains(index) { chooseGroup(ids[index]) }
            return .handled
        }
        .onExitCommand { showingGroups = false }
    }

    private func groupRow(_ id: UUID?, highlighted: Bool) -> some View {
        let count = store.stickers.filter { store.validGroupID($0.groupID) == id }.count
        return Button {
            chooseGroup(id)
        } label: {
            HStack {
                Text(store.groupName(id)).lineLimit(1)
                Spacer()
                Text(count, format: .number).monospacedDigit().foregroundStyle(.secondary)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(store.activeGroupID == id ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(highlighted ? Color.accentColor.opacity(0.15) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chooseGroup(_ id: UUID?) {
        store.selectGroup(id)
        showingGroups = false
    }

    private func binding(for sticker: Sticker) -> Binding<Sticker> {
        // SwiftUI can still read an outgoing card while its removal animates.
        Binding(
            get: { store.stickers.first(where: { $0.id == sticker.id }) ?? sticker },
            set: { updated in
                guard let index = store.stickers.firstIndex(where: { $0.id == sticker.id }) else { return }
                store.stickers[index] = updated
            }
        )
    }
    
    private func deleteSticker(id: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            store.remove(id)
        }
    }
}


struct StickerFramePreference: PreferenceKey {
    static let defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}


struct StickerResizeRegion: Equatable {
    let frame: CGRect
    let isResizing: Bool
}

struct StickerResizeRegionPreference: PreferenceKey {
    static let defaultValue: [StickerResizeRegion] = []

    static func reduce(value: inout [StickerResizeRegion], nextValue: () -> [StickerResizeRegion]) {
        value.append(contentsOf: nextValue())
    }
}
