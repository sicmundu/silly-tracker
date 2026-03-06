import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let icon: String

    var body: some View {
        VStack(spacing: DesignSystem.Layout.spacingMD) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.surfaceMuted)
                    .frame(width: 58, height: 58)

                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }

            VStack(spacing: DesignSystem.Layout.spacingXS) {
                Text(title)
                    .font(DesignSystem.Typography.heading)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                Text(message)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(DesignSystem.Layout.spacingXL)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusXL, style: .continuous)
                .fill(DesignSystem.Colors.surfaceMuted.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusXL, style: .continuous)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4]))
        )
    }
}
