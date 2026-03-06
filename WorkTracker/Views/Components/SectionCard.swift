import SwiftUI

struct SectionCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(DesignSystem.Layout.spacingLG)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusXL, style: .continuous)
                    .fill(DesignSystem.Colors.surface)
                    .shadow(color: DesignSystem.Shadows.cardSm, radius: 10, x: 0, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusXL, style: .continuous)
                    .strokeBorder(DesignSystem.Colors.border, lineWidth: 1)
            )
    }
}
