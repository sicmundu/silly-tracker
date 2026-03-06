import SwiftUI

struct PrimaryActionButton: View {
    let title: String
    let icon: String?
    let color: Color
    let isLoading: Bool
    let action: () -> Void

    @State private var isHovered = false

    init(title: String, icon: String? = nil, color: Color = DesignSystem.Colors.brand, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.color = color
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Layout.spacingSM) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                }

                Text(title)
                    .font(DesignSystem.Typography.bodyBold)
                    .tracking(0.2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Layout.spacingMD)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusXL, style: .continuous)
                    .fill(isHovered ? color.opacity(0.9) : color)
            )
            .foregroundColor(.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
