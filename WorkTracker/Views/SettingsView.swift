import SwiftUI

struct SettingsView: View {
    @AppStorage("linearAPIKey") private var linearAPIKey = ""
    @AppStorage("syncInterval") private var syncInterval: Double = 300
    @AppStorage("dbPath") private var dbPath = ""
    @AppStorage("anthropicAPIKey") private var anthropicAPIKey = ""

    @State private var testResult: String?
    @State private var isTesting = false

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
                }

                HStack {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(linearAPIKey.isEmpty || isTesting)

                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.6)
                    }

                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(result.contains("Connected") ? .green : .red)
                    }
                }
            }

            Section("Database") {
                TextField("Custom DB path (leave empty for default)", text: $dbPath)
                    .textFieldStyle(.roundedBorder)

                Text("Default: ~/Documents/WorkTracker/tracker.db")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !dbPath.isEmpty {
                    Button("Reset to Default") {
                        dbPath = ""
                        DatabaseManager.shared.reopen()
                    }
                }

                Button("Reopen Database") {
                    DatabaseManager.shared.reopen()
                }
            }

            Section("About") {
                LabeledContent("Version", value: "1.1.0")
                LabeledContent("Data", value: "Shared SQLite (tracker.db)")
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 480)
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
}
