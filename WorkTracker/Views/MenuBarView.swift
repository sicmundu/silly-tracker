import SwiftUI

struct MenuBarView: View {
    @ObservedObject var vm: TrackerViewModel
    @State private var hoveredAction: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            statusHeader
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().opacity(0.3)

            // Actions
            VStack(spacing: 2) {
                if let active = vm.activeEntry {
                    menuAction(
                        id: "stop",
                        icon: "stop.fill",
                        label: "Stop \(active.type.label)",
                        color: Color(red: 0.97, green: 0.44, blue: 0.44)
                    ) {
                        vm.stopActivity()
                    }

                    Divider().opacity(0.2).padding(.vertical, 2)

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
            .padding(.horizontal, 6)
            .padding(.vertical, 4)

            Divider().opacity(0.3)

            // Today totals
            VStack(spacing: 4) {
                ForEach(ActivityType.allCases) { type in
                    let total = vm.todayTotals[type] ?? 0
                    if total > 0 {
                        HStack {
                            Image(systemName: type.icon)
                                .font(.system(size: 10))
                                .foregroundStyle(type.accentColor)
                                .frame(width: 16)
                            Text(type.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatDuration(total))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(type.accentColor)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider().opacity(0.3)

            // Bottom actions
            VStack(spacing: 2) {
                menuAction(id: "ai", icon: "sparkles", label: "AI Summary", color: .purple) {
                    Task { await vm.generateSummary(for: Date()) }
                }
                .disabled(vm.isGeneratingSummary || vm.todayNotes.isEmpty)
                .opacity(vm.todayNotes.isEmpty ? 0.4 : 1)

                menuAction(id: "sync", icon: "arrow.triangle.2.circlepath", label: "Sync Linear", color: Color(red: 0.65, green: 0.55, blue: 0.98)) {
                    Task { await vm.linearSync() }
                }
                .disabled(vm.isSyncing)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .padding(.bottom, 6)
        }
        .frame(width: 230)
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        Group {
            if let active = vm.activeEntry {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(active.type.accentColor)
                            .frame(width: 7, height: 7)
                            .modifier(PulseModifier())

                        Image(systemName: active.type.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(active.type.accentColor)

                        Text(active.type.label)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(active.type.accentColor)

                        Spacer()
                    }

                    Text(vm.elapsedFormatted)
                        .font(.system(size: 24, weight: .heavy, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(active.type.accentColor)
                        .contentTransition(.numericText(countsDown: false))
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Idle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Menu Action Row

    private func menuAction(id: String, icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hoveredAction == id ? color.opacity(0.1) : .clear)
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
