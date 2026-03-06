import SwiftUI

/// Core design tokens for the "Calm Product Dashboard" style.
enum DesignSystem {
    // MARK: - Colors
    enum Colors {
        // Base
        static let background = Color(nsColor: .windowBackgroundColor)
        static let canvas = Color(nsColor: .underPageBackgroundColor)
        static let surface = Color(nsColor: .textBackgroundColor)
        static let surfaceHighlight = Color(nsColor: .controlBackgroundColor)
        static let surfaceMuted = Color(nsColor: .unemphasizedSelectedContentBackgroundColor).opacity(0.65)
        static let border = Color(nsColor: .separatorColor).opacity(0.42)

        // Text
        static let textPrimary = Color(nsColor: .labelColor)
        static let textSecondary = Color(nsColor: .secondaryLabelColor)
        static let textTertiary = Color(nsColor: .tertiaryLabelColor)

        // Semantic
        static let brand = Color(red: 0.13, green: 0.39, blue: 0.66)
        static let info = Color(red: 0.26, green: 0.48, blue: 0.75)
        static let success = Color(red: 0.16, green: 0.57, blue: 0.42)
        static let warning = Color(red: 0.77, green: 0.50, blue: 0.12)
        static let danger = Color(red: 0.78, green: 0.23, blue: 0.21)

        // Activity accents
        static let work = Color(red: 0.18, green: 0.58, blue: 0.46)
        static let lunch = Color(red: 0.78, green: 0.55, blue: 0.13)
        static let breakTime = Color(red: 0.13, green: 0.54, blue: 0.63)

        // Legacy support
        static let accent = brand
    }

    // MARK: - Typography
    enum Typography {
        static let display = Font.system(size: 34, weight: .bold, design: .rounded)
        static let title = Font.system(size: 18, weight: .semibold, design: .rounded)
        static let heading = Font.system(size: 14, weight: .semibold, design: .rounded)
        static let bodyBold = Font.system(size: 12, weight: .semibold)
        static let body = Font.system(size: 12, weight: .regular)
        static let captionBold = Font.system(size: 11, weight: .semibold)
        static let caption = Font.system(size: 11, weight: .regular)
        static let microBold = Font.system(size: 10, weight: .bold)
        static let micro = Font.system(size: 10, weight: .medium)

        static let monoHero = Font.system(size: 42, weight: .heavy, design: .monospaced)
        static let monoTitle = Font.system(size: 24, weight: .bold, design: .monospaced)
        static let monoHeading = Font.system(size: 16, weight: .semibold, design: .monospaced)
        static let monoBody = Font.system(size: 12, weight: .medium, design: .monospaced)
        static let monoCaption = Font.system(size: 11, weight: .semibold, design: .monospaced)
        static let monoMicro = Font.system(size: 10, weight: .medium, design: .monospaced)
    }

    // MARK: - Metrics
    enum Layout {
        static let spacingXS: CGFloat = 4
        static let spacingSM: CGFloat = 8
        static let spacingMD: CGFloat = 12
        static let spacingLG: CGFloat = 16
        static let spacingXL: CGFloat = 24
        static let spacingXXL: CGFloat = 32

        static let radiusSM: CGFloat = 4
        static let radiusMD: CGFloat = 8
        static let radiusLG: CGFloat = 12
        static let radiusXL: CGFloat = 16
        static let radiusXXL: CGFloat = 22
    }

    // MARK: - Shadows
    enum Shadows {
        static let cardSm = Color.black.opacity(0.05)
        static let cardMd = Color.black.opacity(0.09)
    }

    enum Gradients {
        static let shell = LinearGradient(
            colors: [
                Colors.canvas.opacity(0.92),
                Colors.background
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    enum Materials {
        static let shellStroke = Colors.border.opacity(0.85)
    }
}
