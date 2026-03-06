import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: TrackerViewModel

    @AppStorage("linearAPIKey") private var linearAPIKey = ""
    @AppStorage("syncInterval") private var syncInterval: Double = 300
    @AppStorage("linearResyncLookbackDays") private var linearResyncLookbackDays = 30
    @AppStorage("dbPath") private var dbPath = ""
    @AppStorage("anthropicAPIKey") private var anthropicAPIKey = ""

    @State private var testResult: String?
    @State private var syncResult: String?
    @State private var isTesting = false
    @State private var isResyncing = false

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
                    subtitle: "Choose the SQLite file used by the tracker."
                )

                TextField("Custom DB path (leave empty for default)", text: $dbPath)
                    .textFieldStyle(.roundedBorder)

                Text("Default location: `~/Documents/WorkTracker/tracker.db`.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                HStack(spacing: DesignSystem.Layout.spacingSM) {
                    if !dbPath.isEmpty {
                        SecondaryChip(title: "Reset to default", icon: "arrow.uturn.backward", isActive: false, activeColor: DesignSystem.Colors.warning) {
                            dbPath = ""
                            DatabaseManager.shared.reopen()
                            vm.refresh()
                        }
                    }

                    SecondaryChip(title: "Reopen database", icon: "externaldrive", isActive: false, activeColor: DesignSystem.Colors.brand) {
                        DatabaseManager.shared.reopen()
                        vm.refresh()
                    }
                }
            }
        }
    }

    private var aboutCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingMD) {
                SectionHeader(
                    title: "About",
                    subtitle: "Current build capabilities."
                )

                infoRow(label: "Version", value: "1.2.0")
                infoRow(label: "Data", value: "Shared SQLite tracker.db")
                infoRow(label: "Experience", value: "History, analytics, redesigned dashboard")
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
