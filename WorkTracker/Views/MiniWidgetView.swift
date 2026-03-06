import SwiftUI

struct MiniWidgetView: View {
    @ObservedObject var vm: TrackerViewModel
    @State private var hoveredAction: String?

    // Pulse animation logic
    @State private var isPulsing = false

    private var progress: Double {
        min(1.0, vm.todayWorkHours / vm.dailyGoalHours)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Top Section (Timer & Expand)
            HStack(alignment: .top) {
                // Circular Progress + Icon
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.1), lineWidth: 4)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            vm.activeEntry?.type.accentColor ?? Color.secondary,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
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
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    if let active = vm.activeEntry {
                        Text(active.type.label.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(active.type.accentColor)
                    } else {
                        Text("IDLE")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                    }

                    Text(vm.elapsedFormatted)
                        .font(.system(size: 20, weight: .heavy, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(vm.activeEntry?.type.accentColor ?? .primary)
                        .contentTransition(.numericText(countsDown: false))
                }
                .padding(.leading, 4)

                Spacer()

                // Expand button
                Button(action: {
                    withAnimation { vm.isMiniMode = false }
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Color(nsColor: .unemphasizedSelectedContentBackgroundColor).opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Bottom Section (Controls)
            HStack(spacing: 6) {
                if let active = vm.activeEntry {
                    compactAction(id: "stop", icon: "stop.fill", color: .red) {
                        vm.stopActivity()
                    }
                    .keyboardShortcut(.space, modifiers: [])

                    ForEach(ActivityType.allCases) { type in
                        if type != active.type {
                            compactAction(id: type.rawValue, icon: type.icon, color: type.accentColor) {
                                vm.startActivity(type)
                            }
                        }
                    }
                } else {
                    ForEach(ActivityType.allCases) { type in
                        compactAction(id: type.rawValue, icon: type.icon, color: type.accentColor) {
                            vm.startActivity(type)
                        }
                    }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.activeEntry?.id)
        }
        .padding(12)
        .frame(width: 250, height: 110)
        .background(.regularMaterial)
        .preferredColorScheme(.dark)
    }

    private func compactAction(id: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(hoveredAction == id ? color.opacity(0.15) : color.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .onHover { hoveredAction = $0 ? id : nil }
    }
}
