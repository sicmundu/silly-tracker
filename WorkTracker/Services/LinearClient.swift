import Foundation

/// Pure Swift Linear API client using URLSession (no dependencies).
final class LinearClient {
    static let shared = LinearClient()

    private let apiURL = URL(string: "https://api.linear.app/graphql")!

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
        request.timeoutInterval = 15

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

    func fetchCompletedIssues(since: String? = nil) async throws -> [LinearIssue] {
        let sinceDate: String
        if let since {
            sinceDate = since
        } else {
            let cal = Calendar.current
            let weekAgo = cal.date(byAdding: .day, value: -7, to: Date())!
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            sinceDate = f.string(from: weekAgo)
        }

        let query = """
        query($after: DateTimeOrDuration!) {
          issues(
            filter: {
              state: { type: { eq: "completed" } }
              completedAt: { gte: $after }
            }
            orderBy: updatedAt
            first: 50
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
          }
        }
        """

        let result: GraphQLResponse<IssuesData> = try await graphql(
            query,
            variables: ["after": "\(sinceDate)T00:00:00.000Z"]
        )

        if let errors = result.errors, let first = errors.first {
            throw LinearError.graphql(first.message)
        }

        guard let nodes = result.data?.issues.nodes else { return [] }

        return nodes
            .filter { $0.assignee?.isMe == true }
            .map { LinearIssue(id: $0.id, identifier: $0.identifier, title: $0.title, completedAt: $0.completedAt) }
    }

    // MARK: - Sync to notes

    func syncToNotes() async -> (added: Int, skipped: Int, error: String?) {
        guard isConfigured else { return (0, 0, "Linear API key not configured") }

        do {
            let issues = try await fetchCompletedIssues()
            let db = DatabaseManager.shared
            var added = 0
            var skipped = 0

            for issue in issues {
                if db.isIssueSynced(issue.id) {
                    skipped += 1
                    continue
                }

                let completedDate = String(issue.completedAt.prefix(10))
                let content = "[Linear \(issue.identifier)] \(issue.title)"
                let noteId = db.addNoteReturningId(date: completedDate, content: content)
                db.markIssueSynced(issue, noteId: noteId)
                added += 1
            }

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
    let issues: IssuesNodes
}

struct IssuesNodes: Decodable {
    let nodes: [IssueNode]
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
