import SwiftUI

struct MenuBarView: View {
    @ObservedObject var vm: TrackerViewModel
    @State private var hoveredAction: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingMD) {
            SectionCard {
                VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingMD) {
                    HStack {
                        VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingXS) {
                            Text("WORKTRACKER")
                                .font(DesignSystem.Typography.microBold)
                                .tracking(1.2)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                            Text(vm.activeEntry == nil ? "Ready to start" : "Tracking in progress")
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                        }
                        Spacer()
                        Image(systemName: vm.activeEntry?.type.icon ?? "timer")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(vm.activeEntry?.type.accentColor ?? DesignSystem.Colors.textSecondary)
                    }

                    statusHeader
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingSM) {
                    Text("Controls")
                        .font(DesignSystem.Typography.captionBold)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    if let active = vm.activeEntry {
                        menuAction(
                            id: "stop",
                            icon: "stop.fill",
                            label: "Stop \(active.type.label)",
                            color: DesignSystem.Colors.danger
                        ) {
                            vm.stopActivity()
                        }

                        ForEach(ActivityType.allCases) { type in
                            if type != active.type {
                                menuAction(
                                    id: "switch-\(type.rawValue)",
                                    icon: type.icon,
                                    label: "Switch to \(type.label)",
                                    color: type.accentColor
                                ) {
                                    vm.startActivity(type)
                                }
                            }
                        }
                    } else {
                        ForEach(ActivityType.allCases) { type in
                            menuAction(
                                id: "start-\(type.rawValue)",
                                icon: type.icon,
                                label: "Start \(type.label)",
                                color: type.accentColor
                            ) {
                                vm.startActivity(type)
                            }
                        }
                    }
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingSM) {
                    Text("Today")
                        .font(DesignSystem.Typography.captionBold)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    ForEach(ActivityType.allCases) { type in
                        let total = vm.todayTotals[type] ?? 0
                        if total > 0 {
                            HStack {
                                ActivityBadge(title: type.label, color: type.accentColor)
                                Spacer()
                                Text(formatDuration(total))
                                    .font(DesignSystem.Typography.monoCaption)
                                    .foregroundStyle(type.accentColor)
                            }
                        }
                    }
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingSM) {
                    Text("Actions")
                        .font(DesignSystem.Typography.captionBold)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    menuAction(id: "ai", icon: "sparkles", label: "Generate AI Summary", color: DesignSystem.Colors.brand) {
                        Task { await vm.generateSummary(for: Date()) }
                    }
                    .disabled(vm.isGeneratingSummary || vm.todayNotes.isEmpty)
                    .opacity(vm.todayNotes.isEmpty ? 0.45 : 1)

                    menuAction(id: "sync", icon: "arrow.triangle.2.circlepath", label: "Sync Linear", color: DesignSystem.Colors.info) {
                        Task { await vm.linearSync() }
                    }
                    .disabled(vm.isSyncing)
                }
            }
        }
        .padding(12)
        .frame(width: 276)
        .background(DesignSystem.Gradients.shell)
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        Group {
            if let active = vm.activeEntry {
                VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingSM) {
                    HStack(spacing: DesignSystem.Layout.spacingXS) {
                        Circle()
                            .fill(active.type.accentColor)
                            .frame(width: 7, height: 7)
                            .modifier(PulseModifier())

                        Text(active.type.label.uppercased())
                            .font(DesignSystem.Typography.microBold)
                            .tracking(1)
                            .foregroundStyle(active.type.accentColor)
                    }

                    Text(vm.elapsedFormatted)
                        .font(DesignSystem.Typography.monoTitle)
                        .monospacedDigit()
                        .foregroundStyle(active.type.accentColor)
                        .contentTransition(.numericText(countsDown: false))
                }
            } else {
                VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingXS) {
                    Text("IDLE")
                        .font(DesignSystem.Typography.microBold)
                        .tracking(1.2)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Text("No active timer")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
    }

    // MARK: - Menu Action Row

    private func menuAction(id: String, icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Layout.spacingSM) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 16)
                Text(label)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Layout.spacingMD)
            .padding(.vertical, DesignSystem.Layout.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusLG, style: .continuous)
                    .fill(hoveredAction == id ? color.opacity(0.10) : DesignSystem.Colors.surfaceMuted.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusLG, style: .continuous)
                    .strokeBorder(color.opacity(hoveredAction == id ? 0.15 : 0.08), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredAction = $0 ? id : nil }
    }

    // MARK: - Helpers

    private func formatDuration(_ sec: TimeInterval) -> String {
        let h = Int(sec) / 3600
        let m = Int(sec) % 3600 / 60
        if h > 0 {
            return "\(h)h \(String(format: "%02d", m))m"
        }
        return "\(m)m"
    }
}
