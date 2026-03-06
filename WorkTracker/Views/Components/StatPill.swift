import SwiftUI

struct StatPill: View {
    let label: String
    let value: String
    let color: Color
    let icon: String?

    init(label: String, value: String, color: Color = DesignSystem.Colors.brand, icon: String? = nil) {
        self.label = label
        self.value = value
        self.color = color
        self.icon = icon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingXS) {
            HStack(spacing: DesignSystem.Layout.spacingXS) {
                if let icon {
                    Image(systemName: icon)
                        .font(DesignSystem.Typography.microBold)
                        .foregroundColor(color)
                }
                Text(label.uppercased())
                    .font(DesignSystem.Typography.microBold)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .tracking(0.8)
            }

            HStack(spacing: DesignSystem.Layout.spacingXS) {
                Text(value)
                    .font(DesignSystem.Typography.monoHeading)
                    .foregroundColor(color)
            }
        }
        .padding(DesignSystem.Layout.spacingMD)
        .frame(minWidth: 118, maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusLG, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusLG, style: .continuous)
                .strokeBorder(color.opacity(0.14), lineWidth: 1)
        )
    }
}
