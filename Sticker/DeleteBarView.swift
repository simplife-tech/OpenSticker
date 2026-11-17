import SwiftUI

struct DeleteBarView: View {
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label(active ? "松手删除贴纸" : "拖到这里删除贴纸",
              systemImage: active ? "trash.fill" : "trash")
            .font(.callout.weight(.semibold))
            .foregroundStyle(active ? Color.white : .primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Capsule().fill(.regularMaterial)
                Capsule().fill(active ? Color.red : .clear)
                Capsule().strokeBorder(.primary.opacity(0.14))
            }
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: active)
    }
}
