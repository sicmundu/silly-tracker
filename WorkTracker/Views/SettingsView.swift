import SwiftUI
import UniformTypeIdentifiers
import Sparkle

struct SettingsView: View {
    @ObservedObject var vm: TrackerViewModel
    let updater: SPUUpdater

    @AppStorage("linearAPIKey") private var linearAPIKey = ""
    @AppStorage("syncInterval") private var syncInterval: Double = 300
    @AppStorage("linearResyncLookbackDays") private var linearResyncLookbackDays = 30
    @AppStorage("anthropicAPIKey") private var anthropicAPIKey = ""

    @State private var testResult: String?
    @State private var syncResult: String?
    @State private var isTesting = false
    @State private var isResyncing = false
    @State private var showResetConfirm = false
    @State private var showImportConfirm = false
    @State private var pendingImportData: Data?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingLG) {
                header
                aiCard
                linearCard
                storageCard
                aboutCard
            }
            .padding(20)
        }
        .frame(width: 560, height: 620)
        .background(DesignSystem.Gradients.shell)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingXS) {
            Text("Settings")
                .font(DesignSystem.Typography.display)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Text("Configure AI, Linear sync cadence, and local storage without leaving the dashboard flow.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }

    private var aiCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingMD) {
                SectionHeader(
                    title: "AI Summary",
                    subtitle: "Anthropic credentials for daily summaries."
                )

                SecureField("API Key or OAuth token", text: $anthropicAPIKey)
                    .textFieldStyle(.roundedBorder)

                Text("Supports `sk-ant-api` and `sk-ant-oat` tokens. Leave empty to auto-read from `.env`.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
    }

    private var linearCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingMD) {
                SectionHeader(
                    title: "Linear",
                    subtitle: "Background sync cadence and manual recovery imports."
                )

                SecureField("Linear API Key", text: $linearAPIKey)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingSM) {
                    Text("Sync interval")
                        .font(DesignSystem.Typography.captionBold)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Picker("", selection: $syncInterval) {
                        Text("1 min").tag(60.0)
                        Text("5 min").tag(300.0)
                        Text("15 min").tag(900.0)
                        Text("30 min").tag(1800.0)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: syncInterval) { _ in
                        vm.reloadSyncTimer()
                    }
                }

                HStack(alignment: .center, spacing: DesignSystem.Layout.spacingMD) {
                    VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingXS) {
                        Text("Manual resync range")
                            .font(DesignSystem.Typography.captionBold)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        Text("Use this when you want to backfill missing completed tasks.")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }

                    Spacer()

                    Stepper(value: $linearResyncLookbackDays, in: 1...365) {
                        Text("\(linearResyncLookbackDays) days")
                            .font(DesignSystem.Typography.monoCaption)
                            .monospacedDigit()
                    }
                    .frame(width: 170, alignment: .trailing)
                }

                HStack(spacing: DesignSystem.Layout.spacingSM) {
                    PrimaryActionButton(
                        title: "Test Connection",
                        icon: "checkmark.shield",
                        color: DesignSystem.Colors.info,
                        isLoading: isTesting
                    ) {
                        testConnection()
                    }
                    .disabled(linearAPIKey.isEmpty || isTesting)

                    PrimaryActionButton(
                        title: "Run Manual Resync",
                        icon: "arrow.triangle.2.circlepath",
                        color: DesignSystem.Colors.brand,
                        isLoading: isResyncing
                    ) {
                        runManualResync()
                    }
                    .disabled(linearAPIKey.isEmpty || isResyncing)
                }

                if let result = testResult {
                    statusRow(
                        text: result,
                        color: result.contains("Connected") ? DesignSystem.Colors.success : DesignSystem.Colors.danger
                    )
                }

                if let result = syncResult {
                    statusRow(
                        text: result,
                        color: (result.contains("Synced") || result.contains("No new")) ? DesignSystem.Colors.success : DesignSystem.Colors.danger
                    )
                }
            }
        }
    }

    private var storageCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingMD) {
                SectionHeader(
                    title: "Storage",
                    subtitle: "Export, import, or reset your tracking data."
                )

                HStack(spacing: DesignSystem.Layout.spacingSM) {
                    PrimaryActionButton(
                        title: "Export Data",
                        icon: "square.and.arrow.up",
                        color: DesignSystem.Colors.brand,
                        isLoading: false
                    ) {
                        exportFullData()
                    }

                    PrimaryActionButton(
                        title: "Import Data",
                        icon: "square.and.arrow.down",
                        color: DesignSystem.Colors.info,
                        isLoading: false
                    ) {
                        importFullData()
                    }

                    PrimaryActionButton(
                        title: "Reset All Data",
                        icon: "trash",
                        color: DesignSystem.Colors.danger,
                        isLoading: false
                    ) {
                        showResetConfirm = true
                    }
                }

                Text("Data is stored locally and backed up automatically by Time Machine.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
        .alert("Reset All Data?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                DatabaseManager.shared.resetAll()
                vm.refresh()
            }
        } message: {
            Text("This will permanently delete all entries, notes, summaries, and sync history. This cannot be undone.")
        }
        .alert("Import Data?", isPresented: $showImportConfirm) {
            Button("Cancel", role: .cancel) { pendingImportData = nil }
            Button("Import", role: .destructive) {
                if let data = pendingImportData {
                    if DatabaseManager.shared.importAll(from: data) {
                        vm.refresh()
                    }
                }
                pendingImportData = nil
            }
        } message: {
            Text("This will replace all existing data with the imported file. Current data will be lost.")
        }
    }

    private func exportFullData() {
        guard let data = DatabaseManager.shared.exportAll() else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "WorkTracker-backup.json"
        panel.title = "Export WorkTracker Data"

        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func importFullData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = "Import WorkTracker Data"

        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? Data(contentsOf: url) {
                pendingImportData = data
                showImportConfirm = true
            }
        }
    }

    private var appVersion: String {
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(marketing) (\(build))"
    }

    private var aboutCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingMD) {
                SectionHeader(
                    title: "About",
                    subtitle: "Current build capabilities."
                )

                infoRow(label: "Version", value: appVersion)
                infoRow(label: "Data", value: "Local SQLite (Application Support)")
                infoRow(label: "Updates", value: "Automatic via Sparkle")

                HStack(spacing: DesignSystem.Layout.spacingSM) {
                    PrimaryActionButton(
                        title: "Check for Updates",
                        icon: "arrow.clockwise",
                        color: DesignSystem.Colors.brand,
                        isLoading: false
                    ) {
                        updater.checkForUpdates()
                    }

                    Toggle("Auto-check", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(DesignSystem.Typography.caption)
                }
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label.uppercased())
                .font(DesignSystem.Typography.microBold)
                .tracking(0.8)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(DesignSystem.Typography.captionBold)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
    }

    private func statusRow(text: String, color: Color) -> some View {
        HStack(spacing: DesignSystem.Layout.spacingXS) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
        .padding(.horizontal, DesignSystem.Layout.spacingMD)
        .padding(.vertical, DesignSystem.Layout.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Layout.radiusLG, style: .continuous)
                .fill(color.opacity(0.08))
        )
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            let (success, name, error) = await LinearClient.shared.testConnection()
            await MainActor.run {
                isTesting = false
                if success {
                    testResult = "Connected as \(name ?? "unknown")"
                } else {
                    testResult = "Error: \(error ?? "Unknown error")"
                }
            }
        }
    }

    private func runManualResync() {
        isResyncing = true
        syncResult = nil
        Task {
            let result = await LinearClient.shared.syncToNotes(lookbackDays: linearResyncLookbackDays)
            await MainActor.run {
                isResyncing = false
                if let error = result.error {
                    syncResult = "Error: \(error)"
                } else if result.added > 0 {
                    syncResult = "Synced \(result.added) tasks from the last \(linearResyncLookbackDays) days"
                } else {
                    syncResult = "No new Linear tasks in the last \(linearResyncLookbackDays) days"
                }
                vm.refresh()
            }
        }
    }
}
