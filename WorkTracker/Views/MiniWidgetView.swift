import SwiftUI

struct MiniWidgetView: View {
    @ObservedObject var vm: TrackerViewModel
    @State private var hoveredAction: String?
    @State private var isPulsing = false

    private var progress: Double {
        min(1.0, vm.todayWorkHours / max(vm.dailyGoalHours, 0.1))
    }

    var body: some View {
        SectionCard {
            VStack(spacing: DesignSystem.Layout.spacingMD) {
                HStack(alignment: .top, spacing: DesignSystem.Layout.spacingMD) {
                    ZStack {
                        Circle()
                            .stroke(DesignSystem.Colors.surfaceMuted, lineWidth: 5)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                vm.activeEntry?.type.accentColor ?? DesignSystem.Colors.textTertiary,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)

                        if let active = vm.activeEntry {
                            Image(systemName: active.type.icon)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(active.type.accentColor)
                                .scaleEffect(isPulsing ? 1.05 : 0.95)
                                .animation(.easeInOut(duration: 1).repeatForever(), value: isPulsing)
                                .onAppear { isPulsing = true }
                                .onChange(of: vm.activeEntry?.id) { _ in
                                    isPulsing = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { isPulsing = true }
                                }
                        } else {
                            Image(systemName: "moon.zzz.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingXS) {
                        HStack(spacing: DesignSystem.Layout.spacingXS) {
                            if let active = vm.activeEntry {
                                Circle()
                                    .fill(active.type.accentColor)
                                    .frame(width: 7, height: 7)
                                Text(active.type.label.uppercased())
                                    .font(DesignSystem.Typography.microBold)
                                    .tracking(1)
                                    .foregroundStyle(active.type.accentColor)
                            } else {
                                Text("IDLE")
                                    .font(DesignSystem.Typography.microBold)
                                    .tracking(1.2)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }

                            if vm.noteReminderMessage != nil {
                                Circle()
                                    .fill(DesignSystem.Colors.warning)
                                    .frame(width: 6, height: 6)
                            }
                        }

                        Text(vm.elapsedFormatted)
                            .font(DesignSystem.Typography.monoTitle)
                            .monospacedDigit()
                            .foregroundStyle(vm.activeEntry?.type.accentColor ?? DesignSystem.Colors.textPrimary)
                            .contentTransition(.numericText(countsDown: false))

                        Text("Goal \(Int(progress * 100))%")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }

                    Spacer()

                    Button(action: {
                        withAnimation { vm.isMiniMode = false }
                    }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(DesignSystem.Colors.surfaceMuted)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: DesignSystem.Layout.spacingSM) {
                    if let active = vm.activeEntry {
                        compactAction(id: "stop", icon: "stop.fill", color: DesignSystem.Colors.danger, title: "Stop") {
                            vm.stopActivity()
                        }
                        .keyboardShortcut(.space, modifiers: [])

                        ForEach(ActivityType.allCases) { type in
                            if type != active.type {
                                compactAction(id: type.rawValue, icon: type.icon, color: type.accentColor, title: type.label) {
                                    vm.startActivity(type)
                                }
                            }
                        }
                    } else {
                        compactAction(id: ActivityType.work.rawValue, icon: ActivityType.work.icon, color: ActivityType.work.accentColor, title: "Work") {
                            vm.startActivity(.work)
                        }
                        compactAction(id: ActivityType.lunch.rawValue, icon: ActivityType.lunch.icon, color: ActivityType.lunch.accentColor, title: "Lunch") {
                            vm.startActivity(.lunch)
                        }
                        compactAction(id: ActivityType.break.rawValue, icon: ActivityType.break.icon, color: ActivityType.break.accentColor, title: "Break") {
                            vm.startActivity(.break)
                        }
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.activeEntry?.id)
            }
        }
        .padding(10)
        .frame(width: 288, height: 172)
        .background(DesignSystem.Gradients.shell)
    }

    private func compactAction(id: String, icon: String, color: Color, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: DesignSystem.Layout.spacingXS) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(DesignSystem.Typography.microBold)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Layout.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusLG, style: .continuous)
                    .fill(hoveredAction == id ? color.opacity(0.16) : color.opacity(0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusLG, style: .continuous)
                    .strokeBorder(color.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hoveredAction = $0 ? id : nil }
    }
}
