import SwiftUI
import UniformTypeIdentifiers

// MARK: - Theme

private enum Theme {
    static let bg       = Color.clear
    static let surface  = Color(nsColor: .controlBackgroundColor)
    static let surface2 = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    static let border   = Color.primary.opacity(0.1)
    static let text     = Color.primary
    static let dim      = Color.secondary
    static let accent   = Color.accentColor
    static let stop     = Color.red
}

// MARK: - Tab

private enum Tab: String, CaseIterable {
    case notes, log, stats, export
    var label: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .notes:  return "note.text"
        case .log:    return "list.bullet"
        case .stats:  return "chart.bar"
        case .export: return "square.and.arrow.up"
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @ObservedObject var vm: TrackerViewModel
    @State private var noteText = ""
    @State private var exportPeriod = "week"
    @State private var hoveredButton: String?
    @State private var selectedTab: Tab = .notes

    var body: some View {
        VStack(spacing: 0) {
            // Top: timer + controls (fixed)
            topSection
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Activity totals strip
            totalsStrip
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            Divider().overlay(Theme.border)

            // Tab bar
            tabBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Divider().overlay(Theme.border)

            // Tab content (fills remaining space)
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 480, idealWidth: 540, minHeight: 560, idealHeight: 640)
        .background(.regularMaterial)
        .overlay(alignment: .top) { toastOverlay }
        .sheet(isPresented: $vm.isEditingHours) { editHoursSheet }
    }

    // MARK: - Top Section (timer + controls)

    private var topSection: some View {
        VStack(spacing: 10) {
            // Row: clock + status + elapsed
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(timeString)
                    .font(.system(size: 42, weight: .heavy, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(
                        vm.activeEntry != nil
                            ? vm.activeEntry!.type.accentColor
                            : Theme.text
                    )
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

            // Controls
            controlButtons
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
                // Stop
                compactButton(
                    key: "stop",
                    icon: "stop.fill",
                    label: "Stop",
                    fg: Theme.stop,
                    bg: Theme.stop.opacity(0.1),
                    hoverBg: Theme.stop.opacity(0.18)
                ) { vm.stopActivity() }
                .keyboardShortcut(.space, modifiers: [])

                // Switch to other types
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
                    withAnimation(.easeOut(duration: 0.15)) { selectedTab = tab }
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

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .notes:  notesTab
        case .log:    logTab
        case .stats:  statsTab
        case .export: exportTab
        }
    }

    // MARK: - Notes Tab

    private var notesTab: some View {
        VStack(spacing: 0) {
            // Header row
            HStack {
                if !vm.todayNotes.isEmpty {
                    Text("\(vm.todayNotes.count) notes")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()

                // Mini Mode Button
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

                // AI Summary button
                Button(action: { Task { await vm.generateSummary() } }) {
                    HStack(spacing: 3) {
                        if vm.isGeneratingSummary {
                            ProgressView().scaleEffect(0.35).frame(width: 10, height: 10)
                        } else {
                            Image(systemName: "sparkles").font(.system(size: 9))
                        }
                        Text(vm.todaySummary != nil ? "Redo AI" : "AI Summary")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(vm.isGeneratingSummary || vm.todayNotes.isEmpty)
                .opacity(vm.todayNotes.isEmpty ? 0.4 : 1)

                Button(action: { Task { await vm.linearSync() } }) {
                    HStack(spacing: 3) {
                        if vm.isSyncing {
                            ProgressView().scaleEffect(0.35).frame(width: 10, height: 10)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 9))
                        }
                        Text("Linear").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(vm.isSyncing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // AI summary (if present)
            if let summary = vm.todaySummary {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.accent)
                    Text(summary.summary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.text.opacity(0.85))
                        .lineLimit(3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.04))
                .transition(.opacity)
            }

            Divider().overlay(Theme.border)

            // Notes list
            if vm.todayNotes.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.dim.opacity(0.4))
                    Text("No notes yet")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.todayNotes) { note in
                            noteRow(note)
                            if note.id != vm.todayNotes.last?.id {
                                Divider().overlay(Theme.border).padding(.leading, 50)
                            }
                        }
                    }
                }
            }

            Divider().overlay(Theme.border)

            // Input
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(noteText.isEmpty ? Theme.dim : Theme.accent)

                TextField("What did you work on?", text: $noteText)
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
        .animation(.easeOut(duration: 0.2), value: vm.todaySummary?.summary)
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
            if vm.todayEntries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.dim.opacity(0.4))
                    Text("No entries yet")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
            } else {
                // Header
                HStack {
                    Text("Type").frame(width: 65, alignment: .leading)
                    Text("Start").frame(width: 55)
                    Text("End").frame(width: 55)
                    Spacer()
                    Text("Duration").frame(width: 65, alignment: .trailing)
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
                        ForEach(vm.todayEntries) { entry in
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
                                    .frame(width: 55)

                                if let end = entry.endTime {
                                    Text(end.formatted(date: .omitted, time: .shortened))
                                        .foregroundStyle(Theme.text.opacity(0.6))
                                        .frame(width: 55)
                                } else {
                                    Text("now")
                                        .foregroundStyle(entry.type.accentColor)
                                        .fontWeight(.bold)
                                        .frame(width: 55)
                                }

                                Spacer()

                                Text(entry.formattedDuration(now: vm.now))
                                    .foregroundStyle(Theme.text)
                                    .fontWeight(.semibold)
                                    .frame(width: 65, alignment: .trailing)
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 5)
                        }
                    }
                }

                Divider().overlay(Theme.border)

                // Totals
                HStack(spacing: 14) {
                    ForEach(ActivityType.allCases) { type in
                        if let total = vm.todayTotals[type], total > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: type.icon).font(.system(size: 8))
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
            // Period picker
            HStack(spacing: 3) {
                ForEach(StatsPeriod.allCases) { period in
                    periodButton(period)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Custom range
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
                            HStack(spacing: 8) {
                                Text(day.shortDate)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.dim)
                                    .frame(width: 42, alignment: .leading)

                                // Stacked bar
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
                                .frame(width: 36, alignment: .trailing)
                                .help("Click to edit")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 3)
                        }
                    }
                }

                Divider().overlay(Theme.border)

                // Summary row
                HStack(spacing: 14) {
                    HStack(spacing: 3) {
                        Text("Total:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.dim)
                        Text(formatDur(vm.periodTotalWork))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(ActivityType.work.accentColor)
                    }

                    if vm.weekStats.count > 1 {
                        HStack(spacing: 3) {
                            Text("Avg:")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Theme.dim)
                            Text(formatDur(vm.periodTotalWork / Double(vm.weekStats.count)))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.accent)
                        }
                    }

                    Spacer()

                    // Legend
                    HStack(spacing: 8) {
                        ForEach(ActivityType.allCases) { type in
                            HStack(spacing: 3) {
                                Circle().fill(type.accentColor).frame(width: 5, height: 5)
                                Text(type.label).font(.system(size: 9, weight: .medium))
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
                .frame(maxWidth: 300)

                HStack(spacing: 8) {
                    exportButton(label: "CSV", icon: "doc.text", format: "csv")
                    exportButton(label: "JSON", icon: "curlybraces", format: "json")
                }
                .frame(maxWidth: 300)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func exportButton(label: String, icon: String, format: String) -> some View {
        Button(action: { doExport(format: format) }) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 12, weight: .semibold))
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

    private func formatDur(_ sec: TimeInterval) -> String {
        let h = Int(sec) / 3600
        let m = Int(sec) % 3600 / 60
        if h > 0 { return "\(h)h \(String(format: "%02d", m))m" }
        return "\(m)m"
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
