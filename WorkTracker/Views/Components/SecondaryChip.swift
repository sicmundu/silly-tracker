import SwiftUI

struct SecondaryChip: View {
    let title: String
    let icon: String?
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void

    @State private var isHovered = false

    init(title: String, icon: String? = nil, isActive: Bool = false, activeColor: Color = DesignSystem.Colors.brand, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isActive = isActive
        self.activeColor = activeColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Layout.spacingXS) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(isActive ? DesignSystem.Typography.captionBold : DesignSystem.Typography.caption)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, DesignSystem.Layout.spacingMD)
            .padding(.vertical, DesignSystem.Layout.spacingSM)
            .background(
                Capsule()
                    .fill(
                        isActive ? activeColor.opacity(0.16) :
                            isHovered ? DesignSystem.Colors.surfaceHighlight : DesignSystem.Colors.surfaceMuted
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isActive ? activeColor.opacity(0.3) : DesignSystem.Colors.border,
                        lineWidth: 1
                    )
            )
            .foregroundColor(isActive ? activeColor : DesignSystem.Colors.textPrimary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
