import Foundation

/// Anthropic API client for generating workday summaries.
/// Uses the same OAuth token approach as the Python ai_client.py.
final class AIClient {
    static let shared = AIClient()

    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-sonnet-4-20250514"

    private var authToken: String {
        // Read from UserDefaults (set in Settings) or fall back to env
        if let key = UserDefaults.standard.string(forKey: "anthropicAPIKey"), !key.isEmpty {
            return key
        }
        // Try reading from .env file in the project directory
        return readEnvToken() ?? ""
    }

    var isConfigured: Bool { !authToken.isEmpty }

    // MARK: - Generate Summary

    func generateSummary(
        date: String,
        notes: [[String: String]],
        stats: [String: Double]
    ) async -> (summary: String?, error: String?) {

        guard isConfigured else {
            return (nil, "Anthropic API key not configured. Set it in Settings.")
        }

        let notesBlock: String
        if notes.isEmpty {
            notesBlock = "(no notes for today)"
        } else {
            notesBlock = notes.map { n in
                let time = String((n["created_at"] ?? "").dropFirst(11).prefix(5))
                return "- [\(time)] \(n["content"] ?? "")"
            }.joined(separator: "\n")
        }

        func fmtH(_ sec: Double) -> String {
            let h = Int(sec) / 3600
            let m = Int(sec) % 3600 / 60
            return "\(h)h \(String(format: "%02d", m))m"
        }

        let prompt = """
        Summarize my workday for \(date).

        Time tracked:
        - Work: \(fmtH(stats["work"] ?? 0))
        - Lunch: \(fmtH(stats["lunch"] ?? 0))
        - Break: \(fmtH(stats["break"] ?? 0))

        My notes:
        \(notesBlock)

        Write a single sentence summary of what was accomplished today. \
        Be specific, use the notes as context. Write in first person. \
        Reply with the summary text only, no extra formatting or commentary.
        """

        do {
            let body: [String: Any] = [
                "model": model,
                "max_tokens": 512,
                "messages": [
                    ["role": "user", "content": prompt]
                ]
            ]

            var request = URLRequest(url: apiURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            let token = authToken
            if token.hasPrefix("sk-ant-oat") {
                // OAuth token
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("claude-code-20250219,oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            } else {
                // Standard API key
                request.setValue(token, forHTTPHeaderField: "x-api-key")
            }

            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.timeoutInterval = 30

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                return (nil, "No HTTP response")
            }

            guard http.statusCode == 200 else {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                return (nil, "HTTP \(http.statusCode): \(String(bodyStr.prefix(200)))")
            }

            // Parse response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let first = content.first,
                  let text = first["text"] as? String else {
                return (nil, "Failed to parse API response")
            }

            return (text.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    // MARK: - Read .env

    private func readEnvToken() -> String? {
        // Try .env in the current working directory
        let path = FileManager.default.currentDirectoryPath + "/.env"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("ANTHROPIC_AUTH_TOKEN=") || trimmed.hasPrefix("ANTHROPIC_API_KEY=") {
                let value = trimmed.split(separator: "=", maxSplits: 1).last.map(String.init) ?? ""
                return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }
}
