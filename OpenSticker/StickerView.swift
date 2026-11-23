import SwiftUI
import AppKit
import CoreText

struct StickerView: View {
    @ObservedObject private var localization = L10n.shared
    @ObservedObject private var plugins = StickerPluginRegistry.shared
    @Binding var sticker: Sticker
    @Binding var draggingID: UUID?
    @Binding var isOverDeleteBar: Bool

    let deleteTarget: CGRect
    let screenSize: CGSize
    let display: StickerDisplay
    let displays: [StickerDisplay]
    var onDelete: (UUID) -> Void
    var onEdit: () -> Void
    var onSaveText: (String) throws -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingAppearance = false
    @State private var isHovered = false
    @State private var isEditing = false
    @State private var showsMarkdownSource = false
    @State private var editorHandle = MarkdownStickerEditor.Handle()

    private var showsTools: Bool {
        isHovered || isDragging || showingAppearance
    }
    @State private var dragOrigin: CGPoint?
    @State private var saveFailed = false
    @State private var copied = false
    @State private var unsavedText: String?

    private let collapsedHeight: CGFloat = 36
    private let imagePadding: CGFloat = 10
    private let missingImageHeight: CGFloat = 46

    private var isCollapsed: Bool { sticker.isCollapsed ?? false }
    private var paperColor: StickerPaperColor { sticker.paperColor ?? .honey }
    private var paperOpacity: Double { sticker.paperOpacity ?? 0.92 }
    private var isDragging: Bool { draggingID == sticker.id }
    private var isDeleting: Bool { isDragging && isOverDeleteBar }
    private var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: 14) }

    private var textSize: CGSize {
        sticker.textSize ?? CGSize(width: 284, height: 144)
    }

    var body: some View {
        Group {
            if isCollapsed {
                collapsedCard
            } else {
                expandedCard
            }
        }
        .fixedSize()
        .onHover { isHovered = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            guard isEditing, let window = editorHandle.editor?.window,
                  notification.object as? NSWindow === window else { return }
            window.makeFirstResponder(nil)
            isEditing = false
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: showsTools)
        .background {
            cardShape.fill(.regularMaterial).opacity(paperOpacity)
            cardShape.fill(paperColor.tint.opacity(paperColor == .neutral ? 0.03 : 0.16))
                .opacity(paperOpacity)
        }
        .clipShape(cardShape)
        .overlay {
            if isDragging {
                cardShape
                    .strokeBorder(isDeleting ? Color.red.opacity(0.9) : .primary.opacity(0.22),
                                  lineWidth: isDeleting ? 2 : 1)
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(reduceMotion ? 1 : (isDeleting ? 0.97 : isDragging ? 1.025 : 1))
        .shadow(color: .black.opacity(isDragging ? 0.28 : 0),
                radius: isDragging ? 18 : 0, y: isDragging ? 9 : 0)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.8), value: isDragging)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isDeleting)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: StickerFramePreference.self,
                    value: [geometry.frame(in: .named("stickerOverlay"))]
                )
            }
        }
        .position(x: displayedPosition.x * screenSize.width,
                  y: displayedPosition.y * screenSize.height)
        .opacity(isDragging && sticker.displayID != display.id ? 0 : 1)
        .zIndex(draggingID == sticker.id ? 1 : 0)
    }

    // Keep the view that owns the gesture mounted until the mouse is released.
    private var displayedPosition: CGPoint {
        if isDragging, sticker.displayID != display.id, let dragOrigin { return dragOrigin }
        return sticker.normalizedPosition
    }

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let state = sticker.plugin {
                pluginBody(state)
            } else {
                switch sticker.content {
                case .text(let source):
                    MarkdownStickerEditor(source: source, width: textSize.width, isEditing: isEditing,
                                          showsSource: showsMarkdownSource,
                                          handle: editorHandle, onFocusChanged: { isEditing = $0 }) { text in
                        do {
                            try onSaveText(text)
                            unsavedText = nil
                            saveFailed = false
                        } catch {
                            unsavedText = text
                            saveFailed = true
                        }
                    }
                    .frame(width: textSize.width, height: textSize.height)
                    .allowsHitTesting(isEditing)
                    .overlay {
                        if !isEditing {
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(moveGesture)
                                .simultaneousGesture(
                                    SpatialTapGesture(count: 2)
                                        .exclusively(before: SpatialTapGesture())
                                        .onEnded { tap in
                                            switch tap {
                                            case .first(let tap):
                                                onEdit()
                                                isEditing = true
                                                editorHandle.beginEditing(at: tap.location)
                                            case .second(let tap):
                                                editorHandle.previewClick(at: tap.location)
                                            }
                                        }
                                )
                                .accessibilityAction(named: Text(L10n.text("编辑贴纸"))) {
                                    onEdit()
                                    isEditing = true
                                    editorHandle.beginEditing(at: nil)
                                }
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        StickerResizeHandle(
                            size: Binding(get: { textSize }, set: { sticker.textSize = $0 }),
                            minimum: CGSize(width: 80, height: 90),
                            screenSize: screenSize,
                            onResize: persistSize
                        )
                        .padding(4)
                        .opacity(showsTools ? 1 : 0)
                        .allowsHitTesting(showsTools)
                    }
                case .image(let payload):
                    if let image = NSImage(contentsOf: payload.fileURL) {
                        StickerImageView(image: image, size: $sticker.imageSize, screenSize: screenSize, showsTools: showsTools, onResize: persistSize)
                            .padding(imagePadding)
                            .contentShape(Rectangle())
                            .gesture(moveGesture)
                    } else {
                        Label(L10n.text("图片不可用"), systemImage: "exclamationmark.triangle")
                            .padding(.horizontal, 14)
                            .frame(height: missingImageHeight)
                    }
                }

            }
            if saveFailed {
                Text(L10n.text("保存失败。文字仍在编辑区，可先复制备份。"))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
        .fixedSize()
        .overlay(alignment: .bottomLeading) {
            toolBar
                .padding(4)
                .opacity(showsTools ? 1 : 0)
                .allowsHitTesting(showsTools)
                .accessibilityHidden(!showsTools)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 2) {
                if sticker.plugin == nil, case .text = sticker.content {
                    Button {
                        if editorHandle.editor?.hasMarkedText() == true { return }
                        showsMarkdownSource.toggle()
                    } label: {
                        Image(systemName: showsMarkdownSource ? "doc.richtext" : "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 26, height: 24)
                            .background(.regularMaterial, in: Capsule())
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showsMarkdownSource ? L10n.text("显示渲染结果") : L10n.text("显示 Markdown 源码"))
                    .help(showsMarkdownSource ? L10n.text("显示渲染结果") : L10n.text("显示 Markdown 源码"))
                }

                Button {
                    setCollapsed(true)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 26, height: 24)
                        .background(.regularMaterial, in: Capsule())
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("折叠贴纸"))
                .help(L10n.text("折叠贴纸"))
                .disabled(saveFailed)
            }
            .padding(4)
            .opacity(showsTools ? 1 : 0)
            .allowsHitTesting(showsTools)
            .accessibilityHidden(!showsTools)
            .onContinuousHover { phase in
                if case .active = phase { NSCursor.arrow.set() }
            }
        }
    }

    private func pluginBody(_ state: StickerPluginState) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.secondary.opacity(0.45))
                .frame(width: 28, height: 3)
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .contentShape(Rectangle())
                .gesture(moveGesture)
                .help(L10n.text("拖动贴纸"))
            if let plugin = plugins.plugin(for: state.pluginID) {
                StickerPluginWebView(plugin: plugin, mode: .card, values: Binding(
                    get: { sticker.plugin?.values ?? [:] },
                    set: { sticker.plugin?.values = $0; persistSize() }
                ), onFocus: onEdit, onDrag: { translation, point in
                    moveSticker(translation, pointer: point)
                    isOverDeleteBar = deleteTarget.contains(point)
                }, onDragEnded: { point in
                    finishMove(shouldDelete: point.map { deleteTarget.contains($0) } ?? false)
                })
            } else {
                ContentUnavailableView(L10n.text("插件未安装"), systemImage: "puzzlepiece")
            }
            Color.clear.frame(height: 30)
        }
        .frame(width: textSize.width, height: textSize.height)
        .overlay(alignment: .bottomTrailing) {
            StickerResizeHandle(size: Binding(get: { textSize }, set: { sticker.textSize = $0 }),
                                minimum: CGSize(width: 180, height: 140),
                                screenSize: screenSize, onResize: persistSize)
                .padding(4)
                .opacity(showsTools ? 1 : 0)
                .allowsHitTesting(showsTools)
        }
    }

    private var collapsedCard: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(paperColor.tint.opacity(paperColor == .neutral ? 0.30 : 0.78))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(collapsedTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 3)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .frame(width: collapsedWidth, height: collapsedHeight)
        .contentShape(Rectangle())
        .gesture(moveGesture)
        .simultaneousGesture(TapGesture().onEnded { setCollapsed(false) })
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(L10n.text("展开贴纸"))
        .accessibilityAction { setCollapsed(false) }
        .help(L10n.text("点击展开 · 拖动移动"))
    }

    private var collapsedWidth: CGFloat {
        let expandedWidth: CGFloat
        switch sticker.content {
        case .text: expandedWidth = textSize.width
        case .image: expandedWidth = sticker.imageSize.width + 20
        }
        return min(max(expandedWidth, 120), 240)
    }

    private var collapsedTitle: String {
        if let state = sticker.plugin {
            let title = state.values["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !title.isEmpty { return title }
            if let plugin = plugins.plugin(for: state.pluginID) { return plugin.name }
        }
        switch sticker.content {
        case .image:
            return L10n.text("图片贴纸")
        case .text(let source):
            for line in source.split(whereSeparator: \.isNewline) {
                let text = line.trimmingCharacters(in: .whitespaces)
                if text.hasPrefix("```") { continue }
                if text.hasPrefix("![") { return L10n.text("图片贴纸") }
                let content = text.replacingOccurrences(
                    of: #"^(?:#{1,6}|>|[-+*](?: \[[ xX]\])?)[ \t]+"#,
                    with: "",
                    options: .regularExpression
                )
                let rendered = (try? AttributedString(markdown: content,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                    .map { String($0.characters) } ?? content
                if !rendered.isEmpty { return rendered }
            }
            return L10n.text("空白贴纸")
        }
    }

    private func setCollapsed(_ collapsed: Bool) {
        guard collapsed != isCollapsed, !collapsed || !saveFailed else { return }
        if collapsed {
            editorHandle.editor?.window?.makeFirstResponder(nil)
            isEditing = false
            showingAppearance = false
        }
        var updated = sticker
        updated.isCollapsed = collapsed
        if screenSize.height > 0 {
            // Position stores the center; shift it by half the height change to keep the top fixed.
            let difference = expandedHeight - collapsedHeight
            updated.normalizedPosition.y += (collapsed ? -difference : difference) / (2 * screenSize.height)
        }
        // Swap the card size and its center together, without moving the outgoing card.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            sticker = updated
        }
        persistSize()
    }

    private var expandedHeight: CGFloat {
        if sticker.plugin != nil { return textSize.height }
        switch sticker.content {
        case .text:
            return textSize.height
        case .image(let payload):
            return NSImage(contentsOf: payload.fileURL) == nil
                ? missingImageHeight : sticker.imageSize.height + 2 * imagePadding
        }
    }

    private var toolBar: some View {
        HStack(spacing: 0) {
            Button {
                onEdit()
                showingAppearance.toggle()
            } label: {
                Image(systemName: "paintpalette")
                    .frame(width: 22, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("贴纸外观"))
            .help(L10n.text("贴纸外观"))
            .popover(isPresented: $showingAppearance, arrowEdge: .bottom) {
                appearanceControls
            }
            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .frame(width: 22, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("复制贴纸"))
            .help(L10n.text("复制贴纸"))
        }
        .background(.regularMaterial, in: Capsule())
        .onContinuousHover { phase in
            if case .active = phase { NSCursor.arrow.set() }
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("stickerOverlay"))
            .onChanged { value in
                moveSticker(value.translation, pointer: value.location)
                isOverDeleteBar = deleteTarget.contains(value.location)
            }
            .onEnded { value in
                finishMove(shouldDelete: deleteTarget.contains(value.location))
            }
    }

    private func moveSticker(_ translation: CGSize, pointer: CGPoint) {
        guard screenSize.width > 0, screenSize.height > 0 else { return }
        if dragOrigin == nil {
            dragOrigin = sticker.normalizedPosition
            draggingID = sticker.id
        }
        guard let origin = dragOrigin else { return }
        let start = display.desktopPoint(for: origin)
        let desktopPointer = CGPoint(x: display.frame.minX + pointer.x, y: display.frame.maxY - pointer.y)
        let destination = displays.first { $0.frame.contains(desktopPointer) }
            ?? displays.first { $0.id == sticker.displayID }
            ?? display
        let center = CGPoint(x: start.x + translation.width, y: start.y - translation.height)
        var moved = sticker
        moved.displayID = destination.id
        moved.normalizedPosition = destination.normalizedPosition(for: center)
        sticker = moved
    }

    private func finishMove(shouldDelete: Bool) {
        let id = sticker.id
        dragOrigin = nil
        draggingID = nil
        isOverDeleteBar = false
        if shouldDelete { onDelete(id) }
    }

    private var appearanceControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("贴纸外观")).font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 10) {
                ForEach(StickerPaperColor.allCases, id: \.self) { color in
                    Button {
                        sticker.paperColor = color
                        persistSize()
                    } label: {
                        Circle()
                            .fill(color.tint.opacity(color == .neutral ? 0.18 : 0.74))
                            .frame(width: 26, height: 26)
                            .overlay {
                                if paperColor == color {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                }
                            }
                            .overlay { Circle().strokeBorder(.primary.opacity(0.15)) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.title)
                    .accessibilityAddTraits(paperColor == color ? .isSelected : [])
                    .help(color.title)
                }
            }
            HStack {
                Text(L10n.text("底纸不透明度"))
                Spacer()
                Text(paperOpacity.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(get: { paperOpacity }, set: { sticker.paperOpacity = $0 }),
                in: 0.35...1,
                step: 0.01,
                onEditingChanged: { editing in
                    if !editing { persistSize() }
                },
                label: { Text(L10n.text("底纸不透明度")) }
            )
            .labelsHidden()
        }
        .padding(16)
        .frame(width: 238)
    }

    private func persistSize() {
        StickerStore.shared.save(StickerStore.shared.stickers)
    }

    private func copy() {
        switch sticker.content {
        case .text(let source):
            copyToClipboard(unsavedText ?? source)
        case .image(let payload):
            guard let image = NSImage(contentsOf: payload.fileURL) else { return }
            copyImageToClipboard(image)
        }
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}

struct MarkdownStickerEditor: NSViewRepresentable {
    let source: String
    let width: CGFloat
    let isEditing: Bool
    let showsSource: Bool
    let handle: Handle
    let onFocusChanged: (Bool) -> Void
    let onChange: (String) -> Void

    private var contentInset: NSSize {
        NSSize(width: min(18, max(9, width * 0.075)), height: 14)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer()
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.delegate = context.coordinator
        let editor = Editor(frame: .zero, textContainer: container)
        editor.delegate = context.coordinator
        editor.drawsBackground = false
        editor.showsSource = showsSource
        editor.isRichText = true
        editor.allowsUndo = true
        editor.importsGraphics = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.textContainerInset = contentInset
        editor.textContainer?.lineFragmentPadding = 0
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.frame = scroll.contentView.bounds
        editor.isEditable = false
        editor.isSelectable = false
        handle.editor = editor
        editor.onFocusChanged = { [weak coordinator = context.coordinator] focused in
            coordinator?.parent.onFocusChanged(focused)
        }
        editor.toggleTask = { [weak coordinator = context.coordinator] editor, point in
            coordinator?.toggleTask(in: editor, at: point) ?? false
        }
        editor.markdownSelection = { [weak coordinator = context.coordinator] selection in
            coordinator?.markdown(in: selection)
        }
        context.coordinator.load(source, into: editor)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let widthChanged = width != coordinator.parent.width
        guard let editor = scroll.documentView as? Editor, !editor.hasMarkedText() else { return }
        let sourceModeChanged = editor.showsSource != showsSource
        coordinator.parent = self
        editor.showsSource = showsSource
        if editor.isEditable != isEditing {
            editor.isEditable = isEditing
            editor.isSelectable = isEditing
            editor.window?.invalidateCursorRects(for: editor)
        }
        if sourceModeChanged {
            let current = coordinator.serialize(editor.attributedString())
            coordinator.load(current, into: editor)
        } else if source != coordinator.lastSource {
            coordinator.lastSource = source
            if coordinator.serialize(editor.attributedString()) != source {
                coordinator.load(source, into: editor)
            }
        }
        if widthChanged {
            editor.textContainerInset = contentInset
            coordinator.resizeAttachments(in: editor)
        }
    }

    final class Handle {
        weak var editor: Editor?

        func beginEditing(at point: CGPoint?) {
            guard let editor, let window = editor.window else { return }
            editor.isEditable = true
            editor.isSelectable = true
            guard window.makeFirstResponder(editor) else {
                editor.onFocusChanged?(false)
                return
            }
            window.invalidateCursorRects(for: editor)
            if let point {
                let location = editor.convert(point, from: editor.enclosingScrollView)
                let index = editor.characterIndexForInsertion(at: location)
                editor.setSelectedRange(NSRange(location: index, length: 0))
            }
        }

        func previewClick(at point: CGPoint) {
            guard let editor else { return }
            let location = editor.convert(point, from: editor.enclosingScrollView)
            _ = editor.toggleTask?(editor, location)
            editor.window?.makeFirstResponder(nil)
        }
    }

    private final class MarkdownImage: NSTextAttachment {
        var markdown = ""
    }

    final class Editor: NSTextView {
        var showsSource = false
        var onFocusChanged: ((Bool) -> Void)?

        override func resignFirstResponder() -> Bool {
            guard super.resignFirstResponder() else { return false }
            onFocusChanged?(false)
            return true
        }
        var toggleTask: ((NSTextView, CGPoint) -> Bool)?
        var markdownSelection: ((NSRange) -> String?)?

        override func resetCursorRects() {
            guard let scroll = enclosingScrollView else { return }
            let textCursor: NSCursor = isEditable ? .iBeam : .arrow
            let viewport = scroll.bounds
            let stripHeight = min(34, viewport.height)
            let toolsWidth = min(52, viewport.width)
            let resizeWidth = min(34, max(0, viewport.width - toolsWidth))
            let stripY = scroll.isFlipped ? viewport.maxY - stripHeight : viewport.minY
            let bodyY = scroll.isFlipped ? viewport.minY : viewport.minY + stripHeight

            func register(_ rect: CGRect, as cursor: NSCursor) {
                let visible = convert(rect, from: scroll).intersection(visibleRect)
                guard !visible.isEmpty else { return }
                addCursorRect(visible, cursor: cursor)
            }

            register(CGRect(x: viewport.minX, y: bodyY, width: viewport.width,
                            height: viewport.height - stripHeight), as: textCursor)
            register(CGRect(x: viewport.minX, y: stripY, width: toolsWidth,
                            height: stripHeight), as: .arrow)
            register(CGRect(x: viewport.minX + toolsWidth, y: stripY,
                            width: viewport.width - toolsWidth - resizeWidth, height: stripHeight), as: textCursor)
            register(CGRect(x: viewport.maxX - resizeWidth, y: stripY,
                            width: resizeWidth, height: stripHeight), as: .arrow)
        }

        override func menu(for event: NSEvent) -> NSMenu? { nil }

        override func rightMouseDown(with event: NSEvent) {}

        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            if event.clickCount == 1, !hasMarkedText(), toggleTask?(self, point) == true {
                return
            }
            super.mouseDown(with: event)
        }

        override func cancelOperation(_ sender: Any?) {
            window?.makeFirstResponder(nil)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if window?.firstResponder === self,
               modifiers == .command,
               event.charactersIgnoringModifiers?.lowercased() == "v" {
                paste(nil)
                return true
            }
            return super.performKeyEquivalent(with: event)
        }

        override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
            if item.action == #selector(paste(_:)), isEditable {
                let pasteboard = NSPasteboard.general
                return pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
                    || pasteboard.string(forType: .string) != nil
            }
            return super.validateUserInterfaceItem(item)
        }

        override func paste(_ sender: Any?) {
            guard isEditable else { return }
            let pasteboard = NSPasteboard.general
            let image = (pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage)
                ?? NSImage(pasteboard: pasteboard)
            if let image {
                do {
                    let markdown = try ImageStore.shared.saveMarkdownImage(image)
                    if showsSource {
                        insertText(markdown, replacementRange: selectedRange())
                    } else {
                        let attachment = MarkdownImage()
                        attachment.markdown = markdown
                        attachment.attachmentCell = NSTextAttachmentCell(imageCell: image.copy() as? NSImage)
                        insertText(NSAttributedString(attachment: attachment), replacementRange: selectedRange())
                    }
                } catch {
                    window?.presentError(error)
                }
            } else if let text = pasteboard.string(forType: .string) {
                insertText(text, replacementRange: selectedRange())
            }
        }

        override func copy(_ sender: Any?) {
            let selection = selectedRange()
            guard selection.length > 0 else { return }
            copyToClipboard(markdownSelection?(selection) ?? (string as NSString).substring(with: selection))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        private struct Markup {
            let opening: NSRange
            let content: NSRange
            let closing: NSRange
        }

        private var markup: [Markup] = []
        private var hiddenCharacters = IndexSet()
        private var replacementCharacters: [Int: UniChar] = [:]
        private var codeCharacters = IndexSet()
        private var taskStates: [Int: NSRange] = [:]
        private static let han = try! NSRegularExpression(pattern: #"\p{Han}+"#)

        func toggleTask(in editor: NSTextView, at point: CGPoint) -> Bool {
            guard let layout = editor.layoutManager,
                  let container = editor.textContainer, layout.numberOfGlyphs > 0 else { return false }
            let origin = editor.textContainerOrigin
            let location = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
            let glyph = layout.glyphIndex(for: location, in: container)
            guard glyph < layout.numberOfGlyphs else { return false }

            var lineGlyphs = NSRange()
            let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineGlyphs)
            let markerGlyph = lineGlyphs.location
            let marker = layout.characterIndexForGlyph(at: markerGlyph)
            guard let state = taskStates[marker] else { return false }

            let box = layout.boundingRect(forGlyphRange: NSRange(location: markerGlyph, length: 1), in: container)
            let hitArea = CGRect(x: box.minX - 8, y: line.minY,
                                 width: max(box.width + 14, 32), height: line.height)
            guard hitArea.contains(location) else { return false }
            let current = (editor.string as NSString).substring(with: state)
            let selection = editor.selectedRange()
            let replacement = current == " " ? "x" : " "
            if editor.isEditable {
                editor.insertText(replacement, replacementRange: state)
                editor.setSelectedRange(selection)
            } else if let storage = editor.textStorage {
                storage.replaceCharacters(in: state, with: replacement)
                editor.didChangeText()
            }
            return true
        }
        private var styledSource = NSAttributedString()

        func load(_ source: String, into editor: NSTextView) {
            editor.string = source
            if !parent.showsSource {
                renderImages(in: editor)
                resizeAttachments(in: editor)
            }
            applyStyles(to: editor)
        }

        private func renderImages(in editor: NSTextView) {
            guard let storage = editor.textStorage else { return }
            let source = storage.string as NSString
            let matches = ImageStore.markdownImagePattern.matches(in: source as String, range: NSRange(location: 0, length: source.length))
            guard !matches.isEmpty else { return }

            func offset(_ position: Int, replacing range: NSRange) -> Int {
                if position <= range.location { return position }
                if position < NSMaxRange(range) { return range.location + 1 }
                return position - range.length + 1
            }

            var selection = editor.selectedRange()
            storage.beginEditing()
            for match in matches.reversed() {
                let filename = source.substring(with: match.range(at: 1))
                let url = ImageStore.shared.imageURL(for: filename)
                guard let image = NSImage(contentsOf: url) else { continue }
                let attachment = MarkdownImage()
                attachment.markdown = source.substring(with: match.range)
                let cell = NSTextAttachmentCell(imageCell: image)
                attachment.attachmentCell = cell
                storage.replaceCharacters(in: match.range, with: NSAttributedString(attachment: attachment))
                let start = offset(selection.location, replacing: match.range)
                let end = offset(NSMaxRange(selection), replacing: match.range)
                selection = NSRange(location: start, length: end - start)
            }
            storage.endEditing()
            editor.setSelectedRange(selection)
        }

        func resizeAttachments(in editor: NSTextView) {
            guard let storage = editor.textStorage else { return }
            let range = NSRange(location: 0, length: storage.length)
            storage.enumerateAttribute(.attachment, in: range) { value, _, _ in
                guard let attachment = value as? MarkdownImage,
                      let cell = attachment.attachmentCell as? NSTextAttachmentCell,
                      let image = cell.image,
                      let representation = image.representations.first,
                      representation.pixelsWide > 0, representation.pixelsHigh > 0 else { return }
                let width = min(max(20, parent.width - 2 * parent.contentInset.width), CGFloat(representation.pixelsWide))
                image.size = CGSize(width: width,
                                    height: width * CGFloat(representation.pixelsHigh) / CGFloat(representation.pixelsWide))
            }
            editor.layoutManager?.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        }

        func serialize(_ content: NSAttributedString) -> String {
            var markdown = ""
            let source = content.string as NSString
            let range = NSRange(location: 0, length: content.length)
            content.enumerateAttribute(.attachment, in: range) { value, range, _ in
                if let attachment = value as? MarkdownImage {
                    markdown += attachment.markdown
                } else {
                    markdown += source.substring(with: range)
                }
            }
            return markdown
        }

        func layoutManager(
            _ layoutManager: NSLayoutManager,
            shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
            properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
            characterIndexes: UnsafePointer<Int>,
            font: NSFont,
            forGlyphRange glyphRange: NSRange
        ) -> Int {
            var updated = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
            var displayedGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
            var changed = false
            for index in updated.indices {
                let character = characterIndexes[index]
                if hiddenCharacters.contains(character) {
                    updated[index].insert(.null)
                    changed = true
                } else if var replacement = replacementCharacters[character] {
                    var glyph = CGGlyph()
                    if CTFontGetGlyphsForCharacters(font as CTFont, &replacement, &glyph, 1) {
                        displayedGlyphs[index] = glyph
                        changed = true
                    }
                }
            }
            guard changed else { return 0 }
            displayedGlyphs.withUnsafeBufferPointer { glyphBuffer in
                updated.withUnsafeBufferPointer { propertyBuffer in
                    guard let glyphBase = glyphBuffer.baseAddress,
                          let propertyBase = propertyBuffer.baseAddress else { return }
                    layoutManager.setGlyphs(glyphBase, properties: propertyBase,
                                            characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
                }
            }
            return glyphRange.length
        }

        func markdown(in selection: NSRange) -> String {
            let source = styledSource.string as NSString
            guard NSMaxRange(selection) <= source.length else { return "" }
            let intersecting = markup.filter { NSIntersectionRange($0.content, selection).length > 0 }
            let openings = intersecting.filter { $0.opening.location < selection.location }
                .sorted { $0.opening.location < $1.opening.location }
            let closings = intersecting.filter { NSMaxRange($0.closing) > NSMaxRange(selection) }
                .sorted { $0.closing.location < $1.closing.location }
            let start = openings.reduce(selection.location) { start, mark in
                max(start, NSMaxRange(mark.opening))
            }
            let end = closings.reduce(NSMaxRange(selection)) { end, mark in
                min(end, mark.closing.location)
            }
            return openings.map { source.substring(with: $0.opening) }.joined()
                + serialize(styledSource.attributedSubstring(from: NSRange(location: start, length: max(0, end - start))))
                + closings.map { source.substring(with: $0.closing) }.joined()
        }

        var parent: MarkdownStickerEditor
        var lastSource: String

        init(_ parent: MarkdownStickerEditor) {
            self.parent = parent
            lastSource = parent.source
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView, !editor.hasMarkedText() else { return }
            if !parent.showsSource {
                renderImages(in: editor)
                resizeAttachments(in: editor)
            }
            applyStyles(to: editor)
            parent.onChange(serialize(editor.attributedString()))
        }

        func applyStyles(to editor: NSTextView) {
            guard let storage = editor.textStorage else { return }
            let range = NSRange(location: 0, length: storage.length)
            markup.removeAll()
            hiddenCharacters.removeAll()
            replacementCharacters.removeAll()
            codeCharacters.removeAll()
            taskStates.removeAll()
            let base = parent.showsSource
                ? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                : NSFont(name: "AvenirNext-Regular", size: 15) ?? .systemFont(ofSize: 15)
            storage.beginEditing()
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 5
            paragraph.paragraphSpacing = 6
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: base,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
            storage.removeAttribute(.backgroundColor, range: range)
            storage.removeAttribute(.underlineStyle, range: range)
            storage.removeAttribute(.strikethroughStyle, range: range)
            storage.addAttributes(bodyAttributes, range: range)
            editor.typingAttributes = bodyAttributes
            if !parent.showsSource {
                applyHanFont(in: storage, range: range, size: base.pointSize, bold: false)

                let code: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .backgroundColor: NSColor.labelColor.withAlphaComponent(0.08)
                ]
                style(#"(?m)^(```[^`\r\n]*\r?\n)([\s\S]*?)^[ \t]*```[ \t]*$"#, in: storage, attributes: code, protectsCode: true)
                style(#"(?<!`)(`)([^`\r\n]+?)\1(?!`)"#, in: storage, attributes: code, protectsCode: true)

                for level in 1...6 {
                    let marker = String(repeating: "#", count: level)
                    let size = max(15, 24 - CGFloat(level - 1) * 2)
                    let heading = NSFont(name: "AvenirNext-Bold", size: size) ?? .boldSystemFont(ofSize: size)
                    style("(?m)^(\(marker)[ \t]+)([^\r\n]+)$", in: storage, attributes: [.font: heading], hanHeadingSize: size)
                }

                let quote = NSMutableParagraphStyle()
                quote.lineSpacing = 5
                quote.paragraphSpacing = 6
                quote.firstLineHeadIndent = 8
                quote.headIndent = 8
                style(#"(?m)^(>[ \t]+)([^\r\n]+)$"#, in: storage,
                      attributes: [.foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: quote],
                      marker: 0x2502)
                style(#"(?m)^([-+*] \[ \](?:[ \t]+|$))([^\r\n]*)$"#, in: storage, marker: 0x2610, isTask: true)
                style(#"(?m)^([-+*] \[[xX]\](?:[ \t]+|$))([^\r\n]*)$"#, in: storage,
                      attributes: [.foregroundColor: NSColor.secondaryLabelColor], marker: 0x2611, isTask: true)
                style(#"(?m)^([-+*] )(?!\[[ xX]\](?:[ \t]|$))([^\r\n]+)$"#, in: storage, marker: 0x2022)

                style(#"(?<![!\[])(\[)([^\]\r\n]+)\]\(https?://[^\s)]+\)"#,
                      in: storage, attributes: [.foregroundColor: NSColor.linkColor,
                                                 .underlineStyle: NSUnderlineStyle.single.rawValue])
                style(#"(~~)([^~\r\n]+?)\1"#, in: storage,
                      attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue])
                style(#"(\*\*|__)([^\r\n]+?)\1"#, in: storage, trait: .boldFontMask)
                style(#"(?<![\w*_])([*_])([^*_\r\n]+?)\1(?![\w*_])"#, in: storage, trait: .italicFontMask)
            }
            storage.endEditing()
            styledSource = NSAttributedString(attributedString: storage)
            editor.layoutManager?.invalidateGlyphs(forCharacterRange: range, changeInLength: 0,
                                                   actualCharacterRange: nil)
        }

        private func applyHanFont(in storage: NSTextStorage, range: NSRange, size: CGFloat, bold: Bool) {
            let name = bold ? "PingFangSC-Semibold" : "PingFangSC-Regular"
            guard let font = NSFont(name: name, size: size) else { return }
            for match in Self.han.matches(in: storage.string, range: range) {
                storage.addAttribute(.font, value: font, range: match.range)
            }
        }

        private func style(
            _ pattern: String,
            in storage: NSTextStorage,
            attributes: [NSAttributedString.Key: Any] = [:],
            trait: NSFontTraitMask? = nil,
            hanHeadingSize: CGFloat? = nil,
            marker: UniChar? = nil,
            isTask: Bool = false,
            protectsCode: Bool = false
        ) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let range = NSRange(location: 0, length: storage.length)
            for match in regex.matches(in: storage.string, range: range) {
                let opening = match.range(at: 1)
                let content = match.range(at: 2)
                let closing = NSRange(location: NSMaxRange(content),
                                      length: NSMaxRange(match.range) - NSMaxRange(content))
                let openingIndexes = opening.location..<NSMaxRange(opening)
                let closingIndexes = closing.location..<NSMaxRange(closing)
                if codeCharacters.intersects(integersIn: openingIndexes)
                    || codeCharacters.intersects(integersIn: closingIndexes)
                    || (protectsCode && codeCharacters.intersects(integersIn: match.range.location..<NSMaxRange(match.range))) {
                    continue
                }

                storage.addAttributes(attributes, range: content)
                if let hanHeadingSize {
                    applyHanFont(in: storage, range: content, size: hanHeadingSize, bold: true)
                }
                if let trait {
                    var fonts: [(NSRange, NSFont)] = []
                    storage.enumerateAttribute(.font, in: content) { value, range, _ in
                        if let font = value as? NSFont,
                           !codeCharacters.intersects(integersIn: range.location..<NSMaxRange(range)) {
                            fonts.append((range, NSFontManager.shared.convert(font, toHaveTrait: trait)))
                        }
                    }
                    for (range, font) in fonts {
                        storage.addAttribute(.font, value: font, range: range)
                        if trait == .boldFontMask {
                            applyHanFont(in: storage, range: range, size: font.pointSize, bold: true)
                        }
                    }
                }
                markup.append(Markup(opening: opening, content: content, closing: closing))
                if let marker {
                    let systemFont = NSFont.systemFont(ofSize: 14)
                    let taskFont = isTask ? NSFont(name: "AppleSymbols", size: 21) : nil
                    // The system UI font has a checked box glyph but no empty ballot box glyph.
                    replacementCharacters[opening.location] = isTask && taskFont == nil && marker == 0x2610
                        ? 0x25A1 : marker
                    storage.addAttribute(.font, value: taskFont ?? systemFont,
                                         range: NSRange(location: opening.location, length: 1))
                    let lastCharacter = (storage.string as NSString).character(at: NSMaxRange(opening) - 1)
                    let visibleSpacing = lastCharacter == 32 || lastCharacter == 9 ? 1 : 0
                    let firstHidden = opening.location + 1
                    hiddenCharacters.insert(integersIn: firstHidden..<max(firstHidden, NSMaxRange(opening) - visibleSpacing))
                    if isTask {
                        taskStates[opening.location] = NSRange(location: opening.location + 3, length: 1)
                    }
                } else {
                    hiddenCharacters.insert(integersIn: openingIndexes)
                }
                hiddenCharacters.insert(integersIn: closingIndexes)
                if protectsCode {
                    codeCharacters.insert(integersIn: match.range.location..<NSMaxRange(match.range))
                }
            }
        }
    }
}

struct StickerImageView: View {
    let image: NSImage
    @Binding var size: CGSize
    let screenSize: CGSize
    let showsTools: Bool
    let onResize: () -> Void

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .bottomTrailing) {
                StickerResizeHandle(size: $size, minimum: CGSize(width: 80, height: 60),
                                    screenSize: screenSize, onResize: onResize)
                    .opacity(showsTools ? 1 : 0)
                    .allowsHitTesting(showsTools)
            }
    }
}

struct StickerResizeHandle: View {
    @Binding var size: CGSize
    let minimum: CGSize
    let screenSize: CGSize
    let onResize: () -> Void

    @State private var initialSize: CGSize?
    @State private var cursorWindow: NSWindow?

    private var handle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.caption)
            .padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
    }

    var body: some View {
        handle
            .accessibilityLabel(L10n.text("调整贴纸大小"))
            .help(L10n.text("拖动调整贴纸大小"))
            .onContinuousHover { phase in
                if case .active = phase { NSCursor.arrow.set() }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: StickerResizeRegionPreference.self,
                        value: [StickerResizeRegion(
                            frame: geometry.frame(in: .named("stickerOverlay")),
                            isResizing: initialSize != nil
                        )]
                    )
                }
                .allowsHitTesting(false)
            }
            .gesture(
                DragGesture(coordinateSpace: .named("stickerOverlay"))
                    .onChanged { value in
                        if initialSize == nil {
                            initialSize = size
                            cursorWindow = NSApp.currentEvent?.window
                            cursorWindow?.disableCursorRects()
                        }
                        NSCursor.arrow.set()
                        guard let initialSize else { return }
                        size = CGSize(
                            width: (initialSize.width + value.translation.width)
                                .clamped(minimum: minimum.width, maximum: screenSize.width - 36),
                            height: (initialSize.height + value.translation.height)
                                .clamped(minimum: minimum.height, maximum: screenSize.height - 60)
                        )
                    }
                    .onEnded { _ in
                        initialSize = nil
                        restoreCursorRects()
                        onResize()
                    }
            )
            .onDisappear(perform: restoreCursorRects)
    }

    private func restoreCursorRects() {
        cursorWindow?.enableCursorRects()
        cursorWindow = nil
    }
}

private extension CGFloat {
    func clamped(minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, minimum), Swift.max(minimum, maximum))
    }
}
