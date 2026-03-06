import SwiftUI

struct ActivityBadge: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: DesignSystem.Layout.spacingXS) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(title.uppercased())
                .font(DesignSystem.Typography.microBold)
                .tracking(0.6)
        }
        .padding(.horizontal, DesignSystem.Layout.spacingSM)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
        .foregroundColor(color)
        .overlay(
            Capsule()
                .strokeBorder(color.opacity(0.2), lineWidth: 1)
        )
    }
}
