import SwiftUI
import UniformTypeIdentifiers
import Sparkle

struct SettingsView: View {
    @ObservedObject var vm: TrackerViewModel
    let updater: SPUUpdater

    // Persisted values
    @AppStorage("linearAPIKey") private var linearAPIKey = ""
    @AppStorage("syncInterval") private var syncInterval: Double = 300
    @AppStorage("linearResyncLookbackDays") private var linearResyncLookbackDays = 30
    @AppStorage("anthropicAPIKey") private var anthropicAPIKey = ""

    // Editing buffers — only save on explicit "Save"
    @State private var editLinearKey = ""
    @State private var editAnthropicKey = ""
    @State private var linearKeyDirty = false
    @State private var anthropicKeyDirty = false

    @State private var testResult: String?
    @State private var syncResult: String?
    @State private var isTesting = false
    @State private var isResyncing = false
    @State private var showResetConfirm = false
    @State private var showImportConfirm = false
    @State private var pendingImportData: Data?
    @State private var saveFlashLinear = false
    @State private var saveFlashAI = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingLG) {
                header
                integrationsCard
                syncCard
                storageCard
                aboutCard
            }
            .padding(20)
        }
        .frame(width: 560, height: 660)
        .background(DesignSystem.Gradients.shell)
        .onAppear {
            editLinearKey = linearAPIKey
            editAnthropicKey = anthropicAPIKey
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingXS) {
            Text("Settings")
                .font(DesignSystem.Typography.display)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Text("API keys, sync preferences, and data management.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
    }

    // MARK: - Integrations (API Keys)

    private var integrationsCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingLG) {
                SectionHeader(
                    title: "Integrations",
                    subtitle: "Connect your accounts to enable sync and AI features."
                )

                // Linear API Key
                VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingSM) {
                    HStack {
                        Label("Linear", systemImage: "link")
                            .font(DesignSystem.Typography.captionBold)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        Spacer()
                        connectionBadge(isConnected: !linearAPIKey.isEmpty)
                    }

                    HStack(spacing: DesignSystem.Layout.spacingSM) {
                        SecureField("lin_api_...", text: $editLinearKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: editLinearKey) { _ in
                                linearKeyDirty = editLinearKey != linearAPIKey
                            }

                        saveButton(
                            dirty: linearKeyDirty,
                            flashing: saveFlashLinear
                        ) {
                            linearAPIKey = editLinearKey
                            linearKeyDirty = false
                            saveFlashLinear = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saveFlashLinear = false }
                        }
                    }

                    Text("Get your key from Linear Settings > API > Personal API keys.")
                        .font(DesignSystem.Typography.micro)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                Divider().overlay(DesignSystem.Colors.border)

                // Anthropic API Key
                VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingSM) {
                    HStack {
                        Label("Anthropic (AI Summary)", systemImage: "sparkles")
                            .font(DesignSystem.Typography.captionBold)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        Spacer()
                        connectionBadge(isConnected: !anthropicAPIKey.isEmpty)
                    }

                    HStack(spacing: DesignSystem.Layout.spacingSM) {
                        SecureField("sk-ant-api-...", text: $editAnthropicKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: editAnthropicKey) { _ in
                                anthropicKeyDirty = editAnthropicKey != anthropicAPIKey
                            }

                        saveButton(
                            dirty: anthropicKeyDirty,
                            flashing: saveFlashAI
                        ) {
                            anthropicAPIKey = editAnthropicKey
                            anthropicKeyDirty = false
                            saveFlashAI = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saveFlashAI = false }
                        }
                    }

                    Text("Supports sk-ant-api and sk-ant-oat tokens. Leave empty to read from .env file.")
                        .font(DesignSystem.Typography.micro)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }
        }
    }

    // MARK: - Sync Settings

    private var syncCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingMD) {
                SectionHeader(
                    title: "Linear Sync",
                    subtitle: "Automatic background sync and manual recovery."
                )

                // Sync interval
                VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingSM) {
                    Text("Auto-sync interval")
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

                Divider().overlay(DesignSystem.Colors.border)

                // Manual resync
                HStack(alignment: .center, spacing: DesignSystem.Layout.spacingMD) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manual resync")
                            .font(DesignSystem.Typography.captionBold)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        Text("Backfill missing completed tasks from Linear.")
                            .font(DesignSystem.Typography.micro)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }

                    Spacer()

                    Stepper(value: $linearResyncLookbackDays, in: 1...365) {
                        Text("\(linearResyncLookbackDays)d")
                            .font(DesignSystem.Typography.monoCaption)
                            .monospacedDigit()
                    }
                    .frame(width: 120, alignment: .trailing)
                }

                // Action buttons
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
                        title: "Resync \(linearResyncLookbackDays)d",
                        icon: "arrow.triangle.2.circlepath",
                        color: DesignSystem.Colors.brand,
                        isLoading: isResyncing
                    ) {
                        runManualResync()
                    }
                    .disabled(linearAPIKey.isEmpty || isResyncing)
                }

                // Status results
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

    // MARK: - Storage

    private var storageCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: DesignSystem.Layout.spacingMD) {
                SectionHeader(
                    title: "Data",
                    subtitle: "Export a backup, import from file, or start fresh."
                )

                HStack(spacing: DesignSystem.Layout.spacingSM) {
                    PrimaryActionButton(
                        title: "Export",
                        icon: "square.and.arrow.up",
                        color: DesignSystem.Colors.brand,
                        isLoading: false
                    ) {
                        exportFullData()
                    }

                    PrimaryActionButton(
                        title: "Import",
                        icon: "square.and.arrow.down",
                        color: DesignSystem.Colors.info,
                        isLoading: false
                    ) {
                        importFullData()
                    }

                    PrimaryActionButton(
                        title: "Reset",
                        icon: "trash",
                        color: DesignSystem.Colors.danger,
                        isLoading: false
                    ) {
                        showResetConfirm = true
                    }
                }

                Text("Stored in ~/Library/Application Support/WorkTracker. Backed up by Time Machine.")
                    .font(DesignSystem.Typography.micro)
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

    // MARK: - About

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
                    subtitle: "WorkTracker v\(appVersion)"
                )

                HStack(spacing: DesignSystem.Layout.spacingSM) {
                    PrimaryActionButton(
                        title: "Check for Updates",
                        icon: "arrow.clockwise",
                        color: DesignSystem.Colors.brand,
                        isLoading: false
                    ) {
                        updater.checkForUpdates()
                    }

                    Spacer()

                    Toggle("Auto-update", isOn: Binding(
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

    // MARK: - Components

    private func connectionBadge(isConnected: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isConnected ? DesignSystem.Colors.success : DesignSystem.Colors.textSecondary.opacity(0.3))
                .frame(width: 6, height: 6)
            Text(isConnected ? "Connected" : "Not set")
                .font(DesignSystem.Typography.micro)
                .foregroundStyle(isConnected ? DesignSystem.Colors.success : DesignSystem.Colors.textSecondary)
        }
    }

    private func saveButton(dirty: Bool, flashing: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: flashing ? "checkmark" : "square.and.arrow.down.on.square")
                    .font(.system(size: 10, weight: .semibold))
                Text(flashing ? "Saved" : "Save")
                    .font(DesignSystem.Typography.captionBold)
            }
            .foregroundStyle(flashing ? DesignSystem.Colors.success : dirty ? .white : DesignSystem.Colors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(flashing ? DesignSystem.Colors.success.opacity(0.15) : dirty ? DesignSystem.Colors.brand : DesignSystem.Colors.surfaceHighlight)
            )
        }
        .buttonStyle(.plain)
        .disabled(!dirty && !flashing)
        .animation(.easeOut(duration: 0.2), value: dirty)
        .animation(.easeOut(duration: 0.2), value: flashing)
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

    // MARK: - Data Actions

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

    // MARK: - Linear Actions

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
