import Foundation

/// Pure Swift Linear API client using URLSession (no dependencies).
final class LinearClient {
    static let shared = LinearClient()

    private let apiURL = URL(string: "https://api.linear.app/graphql")!
    private let lastSuccessfulSyncKey = "linearLastSuccessfulSyncAt"

    private static let apiDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private var apiKey: String {
        UserDefaults.standard.string(forKey: "linearAPIKey") ?? ""
    }

    var isConfigured: Bool { !apiKey.isEmpty }

    // MARK: - GraphQL

    private func graphql<T: Decodable>(_ query: String, variables: [String: Any]? = nil) async throws -> T {
        guard isConfigured else { throw LinearError.notConfigured }

        var body: [String: Any] = ["query": query]
        if let variables { body["variables"] = variables }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LinearError.network("No HTTP response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LinearError.network("HTTP \(http.statusCode): \(body.prefix(200))")
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Fetch completed issues

    private func resolvedSyncStartDate(explicitSince: String?, lookbackDays: Int?) -> Date {
        if let explicitSince,
           let explicitDate = DatabaseManager.dateFromDayString(explicitSince) {
            return explicitDate
        }

        if let lookbackDays {
            let start = Calendar.current.date(byAdding: .day, value: -(max(lookbackDays, 1) - 1), to: Date()) ?? Date()
            return Calendar.current.startOfDay(for: start)
        }

        if let stored = UserDefaults.standard.string(forKey: lastSuccessfulSyncKey),
           let lastSync = DatabaseManager.parseDate(stored) {
            return Calendar.current.date(byAdding: .day, value: -1, to: lastSync) ?? lastSync
        }

        return DatabaseManager.dateFromDayString("2000-01-01") ?? .distantPast
    }

    func fetchCompletedIssues(since: String? = nil, lookbackDays: Int? = nil) async throws -> [LinearIssue] {
        let sinceDate = resolvedSyncStartDate(explicitSince: since, lookbackDays: lookbackDays)
        let query = """
        query($afterDate: DateTimeOrDuration!, $cursor: String) {
          issues(
            filter: {
              state: { type: { eq: "completed" } }
              completedAt: { gte: $afterDate }
            }
            orderBy: updatedAt
            first: 100
            after: $cursor
          ) {
            nodes {
              id
              identifier
              title
              completedAt
              assignee {
                isMe
              }
            }
            pageInfo {
              hasNextPage
              endCursor
            }
          }
        }
        """

        var allIssues: [LinearIssue] = []
        var cursor: String?

        repeat {
            var variables: [String: Any] = [
                "afterDate": Self.apiDateFormatter.string(from: sinceDate)
            ]
            if let cursor {
                variables["cursor"] = cursor
            }

            let result: GraphQLResponse<IssuesData> = try await graphql(query, variables: variables)
            if let errors = result.errors, let first = errors.first {
                throw LinearError.graphql(first.message)
            }

            guard let issues = result.data?.issues else { break }
            allIssues.append(contentsOf: issues.nodes
                .filter { $0.assignee?.isMe == true }
                .map {
                    LinearIssue(
                        id: $0.id,
                        identifier: $0.identifier,
                        title: $0.title,
                        completedAt: $0.completedAt
                    )
                })

            cursor = issues.pageInfo.hasNextPage ? issues.pageInfo.endCursor : nil
        } while cursor != nil

        return allIssues
    }

    // MARK: - Sync to notes

    func syncToNotes(since: String? = nil, lookbackDays: Int? = nil) async -> (added: Int, skipped: Int, error: String?) {
        guard isConfigured else { return (0, 0, "Linear API key not configured") }

        do {
            let issues = try await fetchCompletedIssues(since: since, lookbackDays: lookbackDays)
            let db = DatabaseManager.shared
            var added = 0
            var skipped = 0

            for issue in issues {
                if db.isIssueSynced(issue.id) {
                    skipped += 1
                    continue
                }

                let completedDate = issue.completedDate.map(DatabaseManager.dayString(from:)) ?? String(issue.completedAt.prefix(10))
                let content = "[Linear \(issue.identifier)] \(issue.title)"
                let noteId = db.addNoteReturningId(date: completedDate, content: content)
                guard noteId != -1 else { continue }
                db.markIssueSynced(issue, noteId: noteId)
                added += 1
            }

            UserDefaults.standard.set(DatabaseManager.nowISO(), forKey: lastSuccessfulSyncKey)
            return (added, skipped, nil)
        } catch {
            return (0, 0, error.localizedDescription)
        }
    }

    // MARK: - Test connection

    func testConnection() async -> (success: Bool, name: String?, error: String?) {
        let query = """
        { viewer { name email } }
        """

        do {
            let result: GraphQLResponse<ViewerData> = try await graphql(query)
            if let errors = result.errors, let first = errors.first {
                return (false, nil, first.message)
            }
            let name = result.data?.viewer.name ?? result.data?.viewer.email ?? "Unknown"
            return (true, name, nil)
        } catch {
            return (false, nil, error.localizedDescription)
        }
    }
}

// MARK: - Error

enum LinearError: LocalizedError {
    case notConfigured
    case network(String)
    case graphql(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Linear API key not set"
        case .network(let msg): return msg
        case .graphql(let msg): return msg
        }
    }
}

// MARK: - Decodable types for GraphQL

struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLError]?
}

struct GraphQLError: Decodable {
    let message: String
}

struct IssuesData: Decodable {
    let issues: IssuesConnection
}

struct IssuesConnection: Decodable {
    let nodes: [IssueNode]
    let pageInfo: GraphQLPageInfo
}

struct GraphQLPageInfo: Decodable {
    let hasNextPage: Bool
    let endCursor: String?
}

struct IssueNode: Decodable {
    let id: String
    let identifier: String
    let title: String
    let completedAt: String
    let assignee: IssueAssignee?
}

struct IssueAssignee: Decodable {
    let isMe: Bool
}

struct ViewerData: Decodable {
    let viewer: ViewerInfo
}

struct ViewerInfo: Decodable {
    let name: String?
    let email: String?
}
