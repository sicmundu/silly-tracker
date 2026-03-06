import SwiftUI
import UniformTypeIdentifiers

// MARK: - Theme

private enum Theme {
    static let bg = Color.clear
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let surface2 = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    static let border = Color.primary.opacity(0.1)
    static let text = Color.primary
    static let dim = Color.secondary
    static let accent = Color.accentColor
    static let stop = Color.red
}

// MARK: - Tab

private enum Tab: String, CaseIterable {
    case notes, log, stats, export

    var label: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .notes: return "note.text"
        case .log: return "list.bullet"
        case .stats: return "chart.bar"
        case .export: return "square.and.arrow.up"
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @ObservedObject var vm: TrackerViewModel

    @AppStorage("linearResyncLookbackDays") private var linearResyncLookbackDays = 30

    @State private var noteText = ""
    @State private var exportPeriod = "week"
    @State private var hoveredButton: String?
    @State private var selectedTab: Tab = .notes

    var body: some View {
        VStack(spacing: 0) {
            topSection
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            totalsStrip
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            Divider().overlay(Theme.border)

            tabBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            if selectedTab == .notes || selectedTab == .log {
                Divider().overlay(Theme.border)
                dayNavigator
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            Divider().overlay(Theme.border)

            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 520, idealWidth: 580, minHeight: 600, idealHeight: 700)
        .background(.regularMaterial)
        .overlay(alignment: .top) { toastOverlay }
        .sheet(isPresented: $vm.isEditingHours) { editHoursSheet }
    }

    // MARK: - Top Section

    private var topSection: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(timeString)
                    .font(.system(size: 42, weight: .heavy, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(vm.activeEntry?.type.accentColor ?? Theme.text)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.easeInOut(duration: 0.15), value: timeString)

                Spacer()

                if let active = vm.activeEntry {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(active.type.accentColor)
                                .frame(width: 6, height: 6)
                                .modifier(PulseModifier())
                            Image(systemName: active.type.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(active.type.label.uppercased())
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(1)
                        }
                        .foregroundStyle(active.type.accentColor)

                        Text(vm.elapsedFormatted)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(active.type.accentColor)
                            .contentTransition(.numericText(countsDown: false))

                        Text("since \(active.startTime.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.dim)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .trailing)))
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 11))
                        Text("IDLE")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.5)
                    }
                    .foregroundStyle(Theme.dim)
                    .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: vm.activeEntry?.id)

            controlButtons

            if let reminder = vm.noteReminderMessage {
                HStack(spacing: 8) {
                    Image(systemName: "pencil.and.scribble")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(reminder)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.text.opacity(0.85))
                    Spacer()
                    Button("Add note") {
                        selectedTab = .notes
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var timeString: String {
        Self.timeFormatter.string(from: vm.now)
    }

    // MARK: - Controls

    private var controlButtons: some View {
        HStack(spacing: 6) {
            if let active = vm.activeEntry {
                compactButton(
                    key: "stop",
                    icon: "stop.fill",
                    label: "Stop",
                    fg: Theme.stop,
                    bg: Theme.stop.opacity(0.1),
                    hoverBg: Theme.stop.opacity(0.18)
                ) { vm.stopActivity() }
                .keyboardShortcut(.space, modifiers: [])

                ForEach(ActivityType.allCases) { type in
                    if type != active.type {
                        compactButton(
                            key: "sw-\(type.rawValue)",
                            icon: type.icon,
                            label: type.label,
                            fg: type.accentColor,
                            bg: type.accentColor.opacity(0.08),
                            hoverBg: type.accentColor.opacity(0.15)
                        ) { vm.startActivity(type) }
                    }
                }
            } else {
                ForEach(ActivityType.allCases) { type in
                    compactButton(
                        key: type.rawValue,
                        icon: type.icon,
                        label: type.label,
                        fg: type.accentColor,
                        bg: type.accentColor.opacity(0.08),
                        hoverBg: type.accentColor.opacity(0.15)
                    ) { vm.startActivity(type) }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.activeEntry?.id)
    }

    private func compactButton(key: String, icon: String, label: String, fg: Color, bg: Color, hoverBg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hoveredButton == key ? hoverBg : bg)
            )
        }
        .buttonStyle(.plain)
        .onHover { hoveredButton = $0 ? key : nil }
    }

    // MARK: - Totals Strip

    private var totalsStrip: some View {
        HStack(spacing: 12) {
            ForEach(ActivityType.allCases) { type in
                let total = vm.todayTotals[type] ?? 0
                HStack(spacing: 4) {
                    Image(systemName: type.icon)
                        .font(.system(size: 9))
                    Text(formatDur(total))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(total > 0 ? type.accentColor : Theme.dim.opacity(0.5))
            }

            Spacer()

            Text("Live today")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.dim.opacity(0.85))

            Text(vm.now, style: .date)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.dim)
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases, id: \.self) { tab in
                let active = selectedTab == tab
                Button(action: {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(tab.label)
                            .font(.system(size: 11, weight: active ? .bold : .medium))
                    }
                    .foregroundStyle(active ? Theme.text : Theme.dim)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(active ? Theme.surface2 : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Day Navigator

    private var dayNavigator: some View {
        HStack(spacing: 8) {
            Button(action: { shiftSelectedDay(by: -1) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)

            DatePicker(
                "",
                selection: Binding(
                    get: { vm.selectedDate },
                    set: { vm.setSelectedDate($0) }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.field)
            .frame(maxWidth: 128)

            Button(action: { shiftSelectedDay(by: 1) }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(vm.isViewingToday)
            .opacity(vm.isViewingToday ? 0.4 : 1)

            if !vm.isViewingToday {
                Button("Today") {
                    vm.jumpToToday()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
            }

            Spacer()

            Text(vm.selectedDate, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.dim)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .notes: notesTab
        case .log: logTab
        case .stats: statsTab
        case .export: exportTab
        }
    }

    // MARK: - Notes Tab

    private var notesTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(vm.isViewingToday ? "Today" : "History")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(Theme.dim)

                Text("\(vm.selectedNotes.count) notes")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.dim)

                Spacer()

                Button(action: {
                    withAnimation { vm.isMiniMode = true }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 9))
                        Text("Mini")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.surface2)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Shrink to Mini Widget")

                Button(action: { Task { await vm.generateSummary() } }) {
                    HStack(spacing: 3) {
                        if vm.isGeneratingSummary {
                            ProgressView()
                                .scaleEffect(0.35)
                                .frame(width: 10, height: 10)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9))
                        }
                        Text(vm.selectedSummary != nil ? "Redo AI" : "AI Summary")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(vm.isGeneratingSummary || vm.selectedNotes.isEmpty)
                .opacity(vm.selectedNotes.isEmpty ? 0.4 : 1)

                Button(action: { Task { await vm.linearSync() } }) {
                    HStack(spacing: 3) {
                        if vm.isSyncing {
                            ProgressView()
                                .scaleEffect(0.35)
                                .frame(width: 10, height: 10)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 9))
                        }
                        Text("Linear")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(vm.isSyncing)

                Button(action: { Task { await vm.linearSync(lookbackDays: linearResyncLookbackDays) } }) {
                    Text("Resync \(linearResyncLookbackDays)d")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(vm.isSyncing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if let summary = vm.selectedSummary {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.summary)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.text.opacity(0.85))
                        Text("Generated \(summary.generatedAt)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.dim)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.04))
                .transition(.opacity)
            }

            Divider().overlay(Theme.border)

            if vm.selectedNotes.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.dim.opacity(0.4))
                    Text(vm.isViewingToday ? "No notes yet" : "No notes for this day")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.selectedNotes) { note in
                            noteRow(note)
                            if note.id != vm.selectedNotes.last?.id {
                                Divider().overlay(Theme.border).padding(.leading, 50)
                            }
                        }
                    }
                }
            }

            Divider().overlay(Theme.border)

            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(noteText.isEmpty ? Theme.dim : Theme.accent)

                TextField(notePlaceholder, text: $noteText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text)
                    .onSubmit { submitNote() }

                if !noteText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: { submitNote() }) {
                        Text("Add")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.bg)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Theme.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .animation(.easeOut(duration: 0.15), value: noteText.isEmpty)
        }
        .animation(.easeOut(duration: 0.2), value: vm.selectedSummary?.summary)
    }

    private var notePlaceholder: String {
        vm.isViewingToday ? "What did you work on?" : "Add a retrospective note for this day"
    }

    private func noteRow(_ note: DayNote) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(note.timeOnly)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.dim)
                .frame(width: 34)

            if note.isFromLinear {
                Image(systemName: "link")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .padding(2)
                    .background(Theme.accent.opacity(0.1))
                    .clipShape(Circle())
            }

            Text(note.content)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)

            Button(action: { vm.deleteNote(note) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Theme.dim)
                    .padding(3)
                    .background(Theme.dim.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(0.5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func submitNote() {
        guard !noteText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        vm.addNote(noteText)
        noteText = ""
    }

    // MARK: - Log Tab

    private var logTab: some View {
        VStack(spacing: 0) {
            if vm.selectedEntries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.dim.opacity(0.4))
                    Text(vm.isViewingToday ? "No entries yet" : "No entries for this day")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
            } else {
                HStack {
                    Text("Type").frame(width: 65, alignment: .leading)
                    Text("Start").frame(width: 60)
                    Text("End").frame(width: 60)
                    Spacer()
                    Text("Duration").frame(width: 72, alignment: .trailing)
                }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.dim.opacity(0.6))
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.surface)

                Divider().overlay(Theme.border)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.selectedEntries) { entry in
                            HStack {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(entry.type.accentColor)
                                        .frame(width: 5, height: 5)
                                    Text(entry.type.label)
                                        .foregroundStyle(entry.type.accentColor)
                                }
                                .frame(width: 65, alignment: .leading)

                                Text(entry.startTime.formatted(date: .omitted, time: .shortened))
                                    .foregroundStyle(Theme.text.opacity(0.6))
                                    .frame(width: 60)

                                if let end = entry.endTime {
                                    Text(end.formatted(date: .omitted, time: .shortened))
                                        .foregroundStyle(Theme.text.opacity(0.6))
                                        .frame(width: 60)
                                } else {
                                    Text("now")
                                        .foregroundStyle(entry.type.accentColor)
                                        .fontWeight(.bold)
                                        .frame(width: 60)
                                }

                                Spacer()

                                Text(entry.formattedDuration(now: vm.now))
                                    .foregroundStyle(Theme.text)
                                    .fontWeight(.semibold)
                                    .frame(width: 72, alignment: .trailing)
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 5)
                        }
                    }
                }

                Divider().overlay(Theme.border)

                HStack(spacing: 14) {
                    ForEach(ActivityType.allCases) { type in
                        if let total = vm.selectedDayTotals[type], total > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: type.icon)
                                    .font(.system(size: 8))
                                Text(formatDur(total))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(type.accentColor)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Stats Tab

    private var statsTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach(StatsPeriod.allCases) { period in
                    periodButton(period)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if vm.statsPeriod == .custom {
                HStack(spacing: 8) {
                    DatePicker("", selection: $vm.customStatsStart, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .frame(maxWidth: 110)
                        .onChange(of: vm.customStatsStart) { _ in
                            vm.setCustomRange(start: vm.customStatsStart, end: vm.customStatsEnd)
                        }

                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.dim)

                    DatePicker("", selection: $vm.customStatsEnd, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .frame(maxWidth: 110)
                        .onChange(of: vm.customStatsEnd) { _ in
                            vm.setCustomRange(start: vm.customStatsStart, end: vm.customStatsEnd)
                        }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            statsInsights
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            Divider().overlay(Theme.border)

            if vm.weekStats.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.dim.opacity(0.4))
                    Text("No data for this period")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    let maxSec = vm.weekStats.map(\.total).max() ?? 1

                    LazyVStack(spacing: 1) {
                        ForEach(vm.weekStats) { day in
                            let restriction = vm.editHoursRestriction(for: day.date)

                            HStack(spacing: 8) {
                                Text(day.shortDate)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.dim)
                                    .frame(width: 42, alignment: .leading)

                                GeometryReader { geo in
                                    HStack(spacing: 1) {
                                        if day.work > 0 {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(ActivityType.work.accentColor)
                                                .frame(width: max(2, geo.size.width * day.work / maxSec))
                                        }
                                        if day.lunch > 0 {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(ActivityType.lunch.accentColor)
                                                .frame(width: max(2, geo.size.width * day.lunch / maxSec))
                                        }
                                        if day.breakTime > 0 {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(ActivityType.break.accentColor)
                                                .frame(width: max(2, geo.size.width * day.breakTime / maxSec))
                                        }
                                    }
                                }
                                .frame(height: 14)

                                Button(action: {
                                    vm.beginEditHours(date: day.date, currentHours: day.workHours)
                                }) {
                                    Text(day.formattedWorkHM)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(ActivityType.work.accentColor)
                                }
                                .buttonStyle(.plain)
                                .disabled(restriction != nil)
                                .opacity(restriction == nil ? 1 : 0.4)
                                .frame(width: 44, alignment: .trailing)
                                .help(restriction ?? "Click to edit")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 3)
                        }
                    }
                }

                Divider().overlay(Theme.border)

                HStack(spacing: 14) {
                    statFoot(label: "Total", value: formatDur(vm.periodTotalWork), color: ActivityType.work.accentColor)
                    statFoot(label: "Avg", value: formatDur(vm.periodAveragePerDay), color: Theme.accent)
                    statFoot(label: "Streak", value: "\(vm.periodCurrentStreak)d", color: .orange)
                    statFoot(label: "Goal", value: signedDuration(vm.periodGoalDelta), color: vm.periodGoalDelta >= 0 ? .green : .red)

                    Spacer()

                    HStack(spacing: 8) {
                        ForEach(ActivityType.allCases) { type in
                            HStack(spacing: 3) {
                                Circle().fill(type.accentColor).frame(width: 5, height: 5)
                                Text(type.label)
                                    .font(.system(size: 9, weight: .medium))
                            }
                        }
                    }
                    .foregroundStyle(Theme.dim)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .animation(.easeOut(duration: 0.2), value: vm.statsPeriod)
    }

    private var statsInsights: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                insightPill(label: "Range", value: vm.statsPeriodLabel, color: Theme.dim)
                insightPill(label: "Avg/day", value: formatDur(vm.periodAveragePerDay), color: Theme.accent)
                insightPill(label: "Streak", value: "\(vm.periodCurrentStreak) days", color: .orange)
                insightPill(label: "Goal delta", value: signedDuration(vm.periodGoalDelta), color: vm.periodGoalDelta >= 0 ? .green : .red)
                if let best = vm.periodBestDay {
                    insightPill(label: "Best day", value: "\(best.shortDate) \(best.formattedWorkHM)", color: ActivityType.work.accentColor)
                }
            }
            .padding(.top, 2)
        }
    }

    private func insightPill(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.dim)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.08))
        )
    }

    private func statFoot(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text("\(label):")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.dim)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private func periodButton(_ period: StatsPeriod) -> some View {
        let active = vm.statsPeriod == period
        return Button(action: { vm.setStatsPeriod(period) }) {
            Text(period.label)
                .font(.system(size: 10, weight: active ? .bold : .medium))
                .foregroundStyle(active ? Theme.bg : Theme.dim)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(active ? Theme.accent : Theme.surface2)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Export Tab

    private var exportTab: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Picker("", selection: $exportPeriod) {
                    Text("Week").tag("week")
                    Text("Month").tag("month")
                    Text("Year").tag("year")
                    Text("All").tag("all")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Text("Exports work hours and saved AI summaries for the selected period.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dim)

                HStack(spacing: 8) {
                    exportButton(label: "CSV", icon: "doc.text", format: "csv")
                    exportButton(label: "JSON", icon: "curlybraces", format: "json")
                }
                .frame(maxWidth: 320)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func exportButton(label: String, icon: String, format: String) -> some View {
        Button(action: { doExport(format: format) }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Theme.surface2)
            .foregroundStyle(Theme.text)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func doExport(format: String) {
        guard let result = vm.exportData(period: exportPeriod, format: format) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = result.filename
        panel.allowedContentTypes = format == "json"
            ? [UTType.json]
            : [UTType(filenameExtension: "csv") ?? .commaSeparatedText]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? result.data.write(to: url)
            }
        }
    }

    // MARK: - Edit Hours Sheet

    private var editHoursSheet: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 24))
                .foregroundStyle(Theme.accent)

            Text("Edit Work Hours")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)

            Text(vm.editingDate)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.dim)

            TextField("H:MM", text: $vm.editingHoursValue)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
                .multilineTextAlignment(.center)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .onSubmit { vm.commitEditHours() }

            HStack(spacing: 10) {
                Button("Cancel") { vm.isEditingHours = false }
                    .buttonStyle(.bordered)
                Button("Save") { vm.commitEditHours() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 260)
    }

    // MARK: - Toast

    @ViewBuilder
    private var toastOverlay: some View {
        if let msg = vm.toastMessage {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
                Text(msg)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.surface2)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 3)
            )
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Helpers

    private func shiftSelectedDay(by offset: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: offset, to: vm.selectedDate) else { return }
        let today = Calendar.current.startOfDay(for: Date())
        if date > today {
            vm.jumpToToday()
        } else {
            vm.setSelectedDate(date)
        }
    }

    private func formatDur(_ sec: TimeInterval) -> String {
        let totalMinutes = Int(sec) / 60
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 { return "\(h)h \(String(format: "%02d", m))m" }
        return "\(m)m"
    }

    private func signedDuration(_ sec: TimeInterval) -> String {
        let prefix = sec >= 0 ? "+" : "-"
        return prefix + formatDur(abs(sec))
    }
}

// MARK: - Pulse Modifier

struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
