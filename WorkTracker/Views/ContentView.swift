import SwiftUI
import UniformTypeIdentifiers

// MARK: - Theme

private enum Theme {
    static let bg = DesignSystem.Colors.background
    static let surface = DesignSystem.Colors.surface
    static let surface2 = DesignSystem.Colors.surfaceHighlight
    static let border = DesignSystem.Colors.border
    static let text = DesignSystem.Colors.textPrimary
    static let dim = DesignSystem.Colors.textSecondary
    static let accent = DesignSystem.Colors.accent
    static let stop = DesignSystem.Colors.danger
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
            VStack(spacing: 0) {
                topSection
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                totalsStrip
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                Divider().overlay(Theme.border)

                tabBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                if selectedTab == .notes || selectedTab == .log {
                    Divider().overlay(Theme.border)
                    dayNavigator
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
            Divider().overlay(Theme.border)

            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 520, idealWidth: 580, minHeight: 600, idealHeight: 700)
        .background(DesignSystem.Gradients.shell)
        .overlay(alignment: .top) { toastOverlay }
        .sheet(isPresented: $vm.isEditingHours) { editHoursSheet }
    }

    // MARK: - Top Section (Hero Card)

    private var topSection: some View {
        SectionCard {
            VStack(spacing: DesignSystem.Layout.spacingMD) {
                HStack {
                    VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingXS) {
                        Text("TODAY FOCUS")
                            .font(DesignSystem.Typography.microBold)
                            .tracking(1.2)
                            .foregroundStyle(Theme.dim)
                        Text(vm.isViewingToday ? "Live tracking dashboard" : "Reviewing \(vm.selectedDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(Theme.text.opacity(0.82))
                    }

                    Spacer()

                    HStack(spacing: DesignSystem.Layout.spacingXS) {
                        Image(systemName: vm.todayWorkHours >= vm.dailyGoalHours ? "flag.checkered.circle.fill" : "scope")
                            .font(DesignSystem.Typography.captionBold)
                        Text("\(vm.todayWorkHours, specifier: "%.1f") / \(vm.dailyGoalHours, specifier: "%.1f")h")
                            .font(DesignSystem.Typography.monoCaption)
                    }
                    .foregroundStyle(vm.todayWorkHours >= vm.dailyGoalHours ? DesignSystem.Colors.success : Theme.accent)
                    .padding(.horizontal, DesignSystem.Layout.spacingSM)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill((vm.todayWorkHours >= vm.dailyGoalHours ? DesignSystem.Colors.success : Theme.accent).opacity(0.10))
                    )
                }

                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingXS) {
                        Text(timeString)
                            .font(DesignSystem.Typography.monoHero)
                            .monospacedDigit()
                            .foregroundStyle(vm.activeEntry?.type.accentColor ?? Theme.text)
                            .contentTransition(.numericText(countsDown: false))
                            .animation(.easeInOut(duration: 0.15), value: timeString)

                        Text(vm.activeEntry == nil ? "Ready to track your next block" : "Current clock time")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(Theme.dim)
                    }

                    Spacer()

                    heroStatusPanel
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: vm.activeEntry?.id)

                controlButtons

                HStack(spacing: DesignSystem.Layout.spacingSM) {
                    topMetricCard(
                        title: "Goal Progress",
                        value: "\(Int(goalProgress * 100))%",
                        subtitle: String(format: "%.1fh tracked", vm.todayWorkHours),
                        color: Theme.accent
                    )
                    topMetricCard(
                        title: "Notes",
                        value: "\(vm.todayNotes.count)",
                        subtitle: vm.todayNotes.isEmpty ? "Nothing captured yet" : "Captured today",
                        color: DesignSystem.Colors.breakTime
                    )
                    topMetricCard(
                        title: "Review Day",
                        value: vm.selectedDate.formatted(.dateTime.month(.abbreviated).day()),
                        subtitle: vm.isViewingToday ? "Live context" : "Historical day",
                        color: DesignSystem.Colors.warning
                    )
                }

                if let reminder = vm.noteReminderMessage {
                    HStack(spacing: DesignSystem.Layout.spacingSM) {
                        Image(systemName: "pencil.and.scribble")
                            .font(DesignSystem.Typography.captionBold)
                            .foregroundStyle(DesignSystem.Colors.warning)
                        Text(reminder)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(Theme.text.opacity(0.85))
                        Spacer()
                        Button("Add note") {
                            selectedTab = .notes
                        }
                        .buttonStyle(.plain)
                        .font(DesignSystem.Typography.captionBold)
                        .foregroundStyle(DesignSystem.Colors.warning)
                    }
                    .padding(.horizontal, DesignSystem.Layout.spacingSM)
                    .padding(.vertical, DesignSystem.Layout.spacingSM)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusMD, style: .continuous)
                            .fill(DesignSystem.Colors.warning.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusMD, style: .continuous)
                            .stroke(DesignSystem.Colors.warning.opacity(0.2), lineWidth: 1)
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    @ViewBuilder
    private var heroStatusPanel: some View {
        VStack(alignment: .trailing, spacing: DesignSystem.Layout.spacingSM) {
            if let active = vm.activeEntry {
                HStack(spacing: DesignSystem.Layout.spacingXS) {
                    Circle()
                        .fill(active.type.accentColor)
                        .frame(width: 7, height: 7)
                        .modifier(PulseModifier())
                    Text(active.type.label.uppercased())
                        .font(DesignSystem.Typography.microBold)
                        .tracking(1)
                }
                .foregroundStyle(active.type.accentColor)

                Text(vm.elapsedFormatted)
                    .font(DesignSystem.Typography.monoTitle)
                    .monospacedDigit()
                    .foregroundStyle(active.type.accentColor)
                    .contentTransition(.numericText(countsDown: false))

                Text("since \(active.startTime.formatted(date: .omitted, time: .shortened))")
                    .font(DesignSystem.Typography.micro)
                    .foregroundStyle(Theme.dim)
            } else {
                HStack(spacing: DesignSystem.Layout.spacingXS) {
                    Image(systemName: "moon.zzz.fill")
                        .font(DesignSystem.Typography.caption)
                    Text("IDLE")
                        .font(DesignSystem.Typography.captionBold)
                        .tracking(1.5)
                }
                .foregroundStyle(Theme.dim)

                Text("No timer running")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(Theme.dim)
            }

            VStack(alignment: .trailing, spacing: 6) {
                Capsule()
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 140, height: 6)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: max(18, 140 * goalProgress))
                    }
                Text("daily goal")
                    .font(DesignSystem.Typography.micro)
                    .foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, DesignSystem.Layout.spacingMD)
        .padding(.vertical, DesignSystem.Layout.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusLG, style: .continuous)
                .fill(Theme.surface2.opacity(0.7))
        )
        .frame(minWidth: 186)
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
        VStack(spacing: DesignSystem.Layout.spacingSM) {
            if let active = vm.activeEntry {
                PrimaryActionButton(
                    title: "Stop \(active.type.label)",
                    icon: "stop.fill",
                    color: Theme.stop,
                    action: { vm.stopActivity() }
                )
                .keyboardShortcut(.space, modifiers: [])

                HStack(spacing: DesignSystem.Layout.spacingSM) {
                    ForEach(ActivityType.allCases) { type in
                        if type != active.type {
                            compactButton(
                                key: "sw-\(type.rawValue)",
                                icon: type.icon,
                                label: "Switch to \(type.label)",
                                fg: type.accentColor,
                                bg: type.accentColor.opacity(0.08),
                                hoverBg: type.accentColor.opacity(0.16)
                            ) { vm.startActivity(type) }
                        }
                    }
                }
            } else {
                PrimaryActionButton(
                    title: "Start Work",
                    icon: ActivityType.work.icon,
                    color: ActivityType.work.accentColor,
                    action: { vm.startActivity(.work) }
                )

                HStack(spacing: DesignSystem.Layout.spacingSM) {
                    ForEach([ActivityType.lunch, ActivityType.break], id: \.self) { type in
                        compactButton(
                            key: type.rawValue,
                            icon: type.icon,
                            label: "Start \(type.label)",
                            fg: type.accentColor,
                            bg: type.accentColor.opacity(0.08),
                            hoverBg: type.accentColor.opacity(0.16)
                        ) { vm.startActivity(type) }
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.activeEntry?.id)
    }

    private func compactButton(key: String, icon: String, label: String, fg: Color, bg: Color, hoverBg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Layout.spacingSM) {
                Image(systemName: icon)
                    .font(DesignSystem.Typography.captionBold)
                Text(label)
                    .font(DesignSystem.Typography.captionBold)
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Layout.spacingMD)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusLG, style: .continuous)
                    .fill(hoveredButton == key ? hoverBg : bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusLG, style: .continuous)
                    .strokeBorder(fg.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hoveredButton = $0 ? key : nil }
    }

    // MARK: - Totals Strip

    private var totalsStrip: some View {
        HStack(spacing: DesignSystem.Layout.spacingSM) {
            ForEach(ActivityType.allCases) { type in
                summaryTile(
                    title: type.label,
                    value: formatDur(vm.todayTotals[type] ?? 0),
                    icon: type.icon,
                    color: type.accentColor
                )
            }

            summaryTile(
                title: "Today",
                value: vm.now.formatted(date: .abbreviated, time: .omitted),
                icon: "calendar",
                color: Theme.accent
            )
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: DesignSystem.Layout.spacingSM) {
            ForEach(Tab.allCases, id: \.self) { tab in
                SecondaryChip(
                    title: tab.label,
                    icon: tab.icon,
                    isActive: selectedTab == tab,
                    activeColor: Theme.accent,
                    action: {
                        withAnimation(.easeOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    }
                )
            }
            Spacer()
        }
    }

    // MARK: - Day Navigator

    private var dayNavigator: some View {
        HStack(spacing: DesignSystem.Layout.spacingSM) {
            dayNavButton(icon: "chevron.left") { shiftSelectedDay(by: -1) }

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

            dayNavButton(icon: "chevron.right", disabled: vm.isViewingToday) {
                shiftSelectedDay(by: 1)
            }

            if !vm.isViewingToday {
                SecondaryChip(title: "Today", icon: "arrow.uturn.backward.circle", isActive: false, activeColor: Theme.accent) {
                    vm.jumpToToday()
                }
            }

            Spacer()

            HStack(spacing: DesignSystem.Layout.spacingXS) {
                Image(systemName: "calendar")
                    .font(DesignSystem.Typography.microBold)
                Text(vm.selectedDate, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(DesignSystem.Typography.caption)
            }
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
                    .font(DesignSystem.Typography.microBold)
                    .tracking(1)
                    .foregroundStyle(Theme.dim)

                Text("\(vm.selectedNotes.count) notes")
                    .font(DesignSystem.Typography.micro)
                    .foregroundStyle(Theme.dim)

                Spacer()

                Button(action: {
                    withAnimation { vm.isMiniMode = true }
                }) {
                    HStack(spacing: DesignSystem.Layout.spacingXS) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(DesignSystem.Typography.captionBold)
                        Text("Mini")
                            .font(DesignSystem.Typography.captionBold)
                    }
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, DesignSystem.Layout.spacingSM)
                    .padding(.vertical, DesignSystem.Layout.spacingXS)
                    .background(Theme.surface2)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Shrink to Mini Widget")

                Button(action: { Task { await vm.generateSummary() } }) {
                    HStack(spacing: DesignSystem.Layout.spacingXS) {
                        if vm.isGeneratingSummary {
                            ProgressView()
                                .scaleEffect(0.35)
                                .frame(width: 10, height: 10)
                        } else {
                            Image(systemName: "sparkles")
                                .font(DesignSystem.Typography.captionBold)
                        }
                        Text(vm.selectedSummary != nil ? "Redo AI" : "AI Summary")
                            .font(DesignSystem.Typography.captionBold)
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, DesignSystem.Layout.spacingSM)
                    .padding(.vertical, DesignSystem.Layout.spacingXS)
                    .background(Theme.accent.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(vm.isGeneratingSummary || vm.selectedNotes.isEmpty)
                .opacity(vm.selectedNotes.isEmpty ? 0.4 : 1)

                Button(action: { Task { await vm.linearSync() } }) {
                    HStack(spacing: DesignSystem.Layout.spacingXS) {
                        if vm.isSyncing {
                            ProgressView()
                                .scaleEffect(0.35)
                                .frame(width: 10, height: 10)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(DesignSystem.Typography.captionBold)
                        }
                        Text("Linear")
                            .font(DesignSystem.Typography.captionBold)
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, DesignSystem.Layout.spacingSM)
                    .padding(.vertical, DesignSystem.Layout.spacingXS)
                    .background(Theme.accent.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(vm.isSyncing)

                Button(action: { Task { await vm.linearSync(lookbackDays: linearResyncLookbackDays) } }) {
                    Text("Resync \(linearResyncLookbackDays)d")
                        .font(DesignSystem.Typography.captionBold)
                        .foregroundStyle(DesignSystem.Colors.info)
                        .padding(.horizontal, DesignSystem.Layout.spacingSM)
                        .padding(.vertical, DesignSystem.Layout.spacingXS)
                        .background(DesignSystem.Colors.info.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(vm.isSyncing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if let summary = vm.selectedSummary {
                SectionCard {
                    HStack(alignment: .top, spacing: DesignSystem.Layout.spacingSM) {
                        Image(systemName: "sparkles")
                            .font(DesignSystem.Typography.bodyBold)
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingXS) {
                            Text(summary.summary)
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(Theme.text.opacity(0.85))
                            Text("Generated \(summary.generatedAt)")
                                .font(DesignSystem.Typography.micro)
                                .foregroundStyle(Theme.dim)
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, DesignSystem.Layout.spacingLG)
                .padding(.vertical, DesignSystem.Layout.spacingSM)
                .transition(.opacity)
            }

            Divider().overlay(Theme.border)

            if vm.selectedNotes.isEmpty {
                Spacer()
                EmptyStateView(
                    title: "No notes",
                    message: vm.isViewingToday ? "You haven't added any notes yet." : "No notes for this day.",
                    icon: "note.text"
                )
                .padding(.horizontal, DesignSystem.Layout.spacingXL)
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

            HStack(spacing: DesignSystem.Layout.spacingSM) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(noteText.isEmpty ? Theme.dim : Theme.accent)

                TextField(notePlaceholder, text: $noteText)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(Theme.text)
                    .onSubmit { submitNote() }

                if !noteText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: { submitNote() }) {
                        Text("Add")
                            .font(DesignSystem.Typography.microBold)
                            .foregroundStyle(Theme.bg)
                            .padding(.horizontal, DesignSystem.Layout.spacingMD)
                            .padding(.vertical, DesignSystem.Layout.spacingXS)
                            .background(Theme.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, DesignSystem.Layout.spacingLG)
            .padding(.vertical, DesignSystem.Layout.spacingMD)
            .animation(.easeOut(duration: 0.15), value: noteText.isEmpty)

            HStack(spacing: DesignSystem.Layout.spacingXS) {
                quickNoteChip("Meeting")
                quickNoteChip("Review")
                quickNoteChip("Bugfix")
                quickNoteChip("Research")
                quickNoteChip("Deploy")
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Layout.spacingLG)
            .padding(.bottom, DesignSystem.Layout.spacingMD)
        }
        .animation(.easeOut(duration: 0.2), value: vm.selectedSummary?.summary)
    }

    private var notePlaceholder: String {
        vm.isViewingToday ? "What did you work on?" : "Add a retrospective note for this day"
    }

    private func noteRow(_ note: DayNote) -> some View {
        HStack(alignment: .center, spacing: DesignSystem.Layout.spacingSM) {
            Text(note.timeOnly)
                .font(DesignSystem.Typography.monoMicro)
                .foregroundStyle(Theme.dim)
                .frame(width: 36)

            if note.isFromLinear {
                Image(systemName: "link")
                    .font(DesignSystem.Typography.microBold)
                    .foregroundStyle(Theme.accent)
                    .padding(2)
                    .background(Theme.accent.opacity(0.1))
                    .clipShape(Circle())
            }

            Text(note.content)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(nil)

            Button(action: { vm.deleteNote(note) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.dim)
                    .padding(4)
                    .background(Theme.dim.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(0.5)
        }
        .padding(.horizontal, DesignSystem.Layout.spacingLG)
        .padding(.vertical, DesignSystem.Layout.spacingSM)
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
                EmptyStateView(
                    title: "No entries",
                    message: vm.isViewingToday ? "No entries yet." : "No entries for this day.",
                    icon: "list.bullet"
                )
                .padding(.horizontal, DesignSystem.Layout.spacingXL)
                Spacer()
            } else {
                HStack {
                    Text("Type").frame(width: 65, alignment: .leading)
                    Text("Start").frame(width: 60)
                    Text("End").frame(width: 60)
                    Spacer()
                    Text("Duration").frame(width: 72, alignment: .trailing)
                }
                .font(DesignSystem.Typography.monoMicro)
                .foregroundStyle(Theme.dim.opacity(0.6))
                .textCase(.uppercase)
                .padding(.horizontal, DesignSystem.Layout.spacingLG)
                .padding(.vertical, DesignSystem.Layout.spacingSM)
                .background(Theme.surface)

                Divider().overlay(Theme.border)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.selectedEntries) { entry in
                            HStack {
                                HStack(spacing: DesignSystem.Layout.spacingXS) {
                                    Circle()
                                        .fill(entry.type.accentColor)
                                        .frame(width: 6, height: 6)
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
                                        .font(DesignSystem.Typography.monoCaption)
                                        .frame(width: 60)
                                }

                                Spacer()

                                Text(entry.formattedDuration(now: vm.now))
                                    .foregroundStyle(Theme.text)
                                    .font(DesignSystem.Typography.monoBody)
                                    .frame(width: 72, alignment: .trailing)
                            }
                            .font(DesignSystem.Typography.monoCaption)
                            .padding(.horizontal, DesignSystem.Layout.spacingLG)
                            .padding(.vertical, DesignSystem.Layout.spacingSM)
                        }
                    }
                }

                Divider().overlay(Theme.border)

                HStack(spacing: DesignSystem.Layout.spacingMD) {
                    ForEach(ActivityType.allCases) { type in
                        if let total = vm.selectedDayTotals[type], total > 0 {
                            HStack(spacing: DesignSystem.Layout.spacingXS) {
                                Image(systemName: type.icon)
                                    .font(DesignSystem.Typography.micro)
                                Text(formatDur(total))
                                    .font(DesignSystem.Typography.monoCaption)
                            }
                            .foregroundStyle(type.accentColor)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, DesignSystem.Layout.spacingLG)
                .padding(.vertical, DesignSystem.Layout.spacingSM)
            }
        }
    }

    // MARK: - Stats Tab

    private var statsTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignSystem.Layout.spacingXS) {
                ForEach(StatsPeriod.allCases) { period in
                    periodButton(period)
                }
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Layout.spacingLG)
            .padding(.vertical, DesignSystem.Layout.spacingSM)

            if vm.statsPeriod == .custom {
                HStack(spacing: DesignSystem.Layout.spacingSM) {
                    DatePicker("", selection: $vm.customStatsStart, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .frame(maxWidth: 110)
                        .onChange(of: vm.customStatsStart) { _ in
                            vm.setCustomRange(start: vm.customStatsStart, end: vm.customStatsEnd)
                        }

                    Image(systemName: "arrow.right")
                        .font(DesignSystem.Typography.micro)
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
                .padding(.horizontal, DesignSystem.Layout.spacingLG)
                .padding(.bottom, DesignSystem.Layout.spacingMD)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            statsInsights
                .padding(.horizontal, DesignSystem.Layout.spacingLG)
                .padding(.bottom, DesignSystem.Layout.spacingMD)

            Divider().overlay(Theme.border)

            if vm.weekStats.isEmpty {
                Spacer()
                EmptyStateView(
                    title: "No data",
                    message: "No data available for this period.",
                    icon: "chart.bar"
                )
                .padding(.horizontal, DesignSystem.Layout.spacingXL)
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    let maxSec = vm.weekStats.map(\.total).max() ?? 1

                    LazyVStack(spacing: 1) {
                        ForEach(vm.weekStats) { day in
                            let restriction = vm.editHoursRestriction(for: day.date)

                            HStack(spacing: DesignSystem.Layout.spacingSM) {
                                Text(day.shortDate)
                                    .font(DesignSystem.Typography.microBold)
                                    .foregroundStyle(Theme.dim)
                                    .frame(width: 42, alignment: .leading)

                                GeometryReader { geo in
                                    HStack(spacing: 1) {
                                        if day.work > 0 {
                                            RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusSM)
                                                .fill(ActivityType.work.accentColor)
                                                .frame(width: max(2, geo.size.width * day.work / maxSec))
                                        }
                                        if day.lunch > 0 {
                                            RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusSM)
                                                .fill(ActivityType.lunch.accentColor)
                                                .frame(width: max(2, geo.size.width * day.lunch / maxSec))
                                        }
                                        if day.breakTime > 0 {
                                            RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusSM)
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
                                        .font(DesignSystem.Typography.monoMicro)
                                        .foregroundStyle(ActivityType.work.accentColor)
                                }
                                .buttonStyle(.plain)
                                .disabled(restriction != nil)
                                .opacity(restriction == nil ? 1 : 0.4)
                                .frame(width: 48, alignment: .trailing)
                                .help(restriction ?? "Click to edit")
                            }
                            .padding(.horizontal, DesignSystem.Layout.spacingLG)
                            .padding(.vertical, DesignSystem.Layout.spacingXS)
                        }
                    }
                }

                Divider().overlay(Theme.border)

                HStack(spacing: DesignSystem.Layout.spacingMD) {
                    statFoot(label: "Total", value: formatDur(vm.periodTotalWork), color: ActivityType.work.accentColor)
                    statFoot(label: "Avg", value: formatDur(vm.periodAveragePerDay), color: Theme.accent)
                    statFoot(label: "Streak", value: "\(vm.periodCurrentStreak)d", color: DesignSystem.Colors.warning)
                    statFoot(label: "Goal", value: signedDuration(vm.periodGoalDelta), color: vm.periodGoalDelta >= 0 ? DesignSystem.Colors.success : DesignSystem.Colors.danger)

                    Spacer()

                    HStack(spacing: DesignSystem.Layout.spacingSM) {
                        ForEach(ActivityType.allCases) { type in
                            HStack(spacing: DesignSystem.Layout.spacingXS) {
                                Circle().fill(type.accentColor).frame(width: 6, height: 6)
                                Text(type.label)
                                    .font(DesignSystem.Typography.microBold)
                            }
                        }
                    }
                    .foregroundStyle(Theme.dim)
                }
                .padding(.horizontal, DesignSystem.Layout.spacingLG)
                .padding(.vertical, DesignSystem.Layout.spacingMD)
            }
        }
        .animation(.easeOut(duration: 0.2), value: vm.statsPeriod)
    }

    private var statsInsights: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Layout.spacingSM) {
                StatPill(label: "Range", value: vm.statsPeriodLabel, color: Theme.dim, icon: "calendar")
                StatPill(label: "Avg/day", value: formatDur(vm.periodAveragePerDay), color: Theme.accent, icon: "chart.line.uptrend.xyaxis")
                StatPill(label: "Streak", value: "\(vm.periodCurrentStreak) days", color: DesignSystem.Colors.warning, icon: "flame")
                StatPill(label: "Goal delta", value: signedDuration(vm.periodGoalDelta), color: vm.periodGoalDelta >= 0 ? DesignSystem.Colors.success : DesignSystem.Colors.danger, icon: "scope")
                if let best = vm.periodBestDay {
                    StatPill(label: "Best day", value: "\(best.shortDate) \(best.formattedWorkHM)", color: ActivityType.work.accentColor, icon: "sparkle")
                }
            }
            .padding(.top, DesignSystem.Layout.spacingXS)
        }
    }

    private func statFoot(label: String, value: String, color: Color) -> some View {
        HStack(spacing: DesignSystem.Layout.spacingXS) {
            Text("\(label):")
                .font(DesignSystem.Typography.micro)
                .foregroundStyle(Theme.dim)
            Text(value)
                .font(DesignSystem.Typography.monoMicro)
                .foregroundStyle(color)
        }
    }

    private func periodButton(_ period: StatsPeriod) -> some View {
        let active = vm.statsPeriod == period
        return Button(action: { vm.setStatsPeriod(period) }) {
            Text(period.label)
                .font(active ? DesignSystem.Typography.microBold : DesignSystem.Typography.micro)
                .foregroundStyle(active ? Theme.bg : Theme.dim)
                .padding(.horizontal, DesignSystem.Layout.spacingMD)
                .padding(.vertical, DesignSystem.Layout.spacingXS)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusSM)
                        .fill(active ? Theme.accent : Theme.surface2)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Export Tab

    private var exportTab: some View {
        VStack(spacing: 0) {
            Spacer()
            SectionCard {
                VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingLG) {
                    SectionHeader(
                        title: "Export snapshots",
                        subtitle: "Save work totals and AI summaries for the selected period."
                    )

                    Picker("", selection: $exportPeriod) {
                        Text("Week").tag("week")
                        Text("Month").tag("month")
                        Text("Year").tag("year")
                        Text("All").tag("all")
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 8) {
                        exportButton(label: "CSV", icon: "doc.text", format: "csv")
                        exportButton(label: "JSON", icon: "curlybraces", format: "json")
                    }
                }
            }
            .frame(maxWidth: 360)
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
                    .foregroundStyle(DesignSystem.Colors.success)
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

    private func dayNavButton(icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DesignSystem.Typography.captionBold)
                .foregroundStyle(disabled ? Theme.dim.opacity(0.5) : Theme.text)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Theme.surface2.opacity(disabled ? 0.35 : 0.8))
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func summaryTile(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingXS) {
            HStack(spacing: DesignSystem.Layout.spacingXS) {
                Image(systemName: icon)
                    .font(DesignSystem.Typography.microBold)
                    .foregroundStyle(color)
                Text(title.uppercased())
                    .font(DesignSystem.Typography.microBold)
                    .foregroundStyle(Theme.dim)
                    .tracking(0.8)
            }

            Text(value)
                .font(title == "Today" ? DesignSystem.Typography.captionBold : DesignSystem.Typography.monoCaption)
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignSystem.Layout.spacingMD)
        .padding(.vertical, DesignSystem.Layout.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusLG, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusLG, style: .continuous)
                .strokeBorder(color.opacity(0.14), lineWidth: 1)
        )
    }

    private func topMetricCard(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingXS) {
            Text(title.uppercased())
                .font(DesignSystem.Typography.microBold)
                .tracking(0.8)
                .foregroundStyle(Theme.dim)
            Text(value)
                .font(DesignSystem.Typography.monoHeading)
                .foregroundStyle(color)
            Text(subtitle)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(Theme.text.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Layout.spacingMD)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusLG, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusLG, style: .continuous)
                .strokeBorder(color.opacity(0.14), lineWidth: 1)
        )
    }

    private func quickNoteChip(_ title: String) -> some View {
        SecondaryChip(title: title, icon: "plus", isActive: false, activeColor: Theme.accent) {
            if noteText.isEmpty {
                noteText = title + ": "
            } else {
                noteText += noteText.hasSuffix(" ") ? "\(title.lowercased()) " : " \(title.lowercased()) "
            }
        }
    }

    private var goalProgress: Double {
        min(1, max(0, vm.todayWorkHours / max(vm.dailyGoalHours, 0.1)))
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
