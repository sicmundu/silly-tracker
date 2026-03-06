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
        Form {
            Section("AI Summary (Anthropic)") {
                SecureField("API Key (or OAuth token)", text: $anthropicAPIKey)
                    .textFieldStyle(.roundedBorder)

                Text("Supports sk-ant-api or sk-ant-oat tokens. Leave empty to auto-read from .env")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Linear Integration") {
                SecureField("API Key", text: $linearAPIKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Sync interval")
                    Picker("", selection: $syncInterval) {
                        Text("1 min").tag(60.0)
                        Text("5 min").tag(300.0)
                        Text("15 min").tag(900.0)
                        Text("30 min").tag(1800.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                    .onChange(of: syncInterval) { _ in
                        vm.reloadSyncTimer()
                    }
                }

                HStack {
                    Text("Manual resync range")
                    Stepper(value: $linearResyncLookbackDays, in: 1...365) {
                        Text("\(linearResyncLookbackDays) days")
                            .monospacedDigit()
                    }
                    .frame(maxWidth: 180, alignment: .leading)
                }

                HStack {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(linearAPIKey.isEmpty || isTesting)

                    Button("Run Manual Resync") {
                        runManualResync()
                    }
                    .disabled(linearAPIKey.isEmpty || isResyncing)

                    if isTesting || isResyncing {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                }

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.contains("Connected") ? .green : .red)
                }

                if let result = syncResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.contains("Synced") || result.contains("No new") ? .green : .red)
                }
            }

            Section("Database") {
                TextField("Custom DB path (leave empty for default)", text: $dbPath)
                    .textFieldStyle(.roundedBorder)

                Text("Default: ~/Documents/WorkTracker/tracker.db")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    if !dbPath.isEmpty {
                        Button("Reset to Default") {
                            dbPath = ""
                            DatabaseManager.shared.reopen()
                            vm.refresh()
                        }
                    }

                    Button("Reopen Database") {
                        DatabaseManager.shared.reopen()
                        vm.refresh()
                    }
                }
            }

            Section("About") {
                LabeledContent("Version", value: "1.2.0")
                LabeledContent("Data", value: "Shared SQLite (tracker.db)")
                LabeledContent("History", value: "Per-day notes/logs + analytics")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 540)
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
