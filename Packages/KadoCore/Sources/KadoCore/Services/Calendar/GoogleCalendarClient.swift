import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

nonisolated public protocol GoogleCalendarFetching: Sendable {
    func events(accessToken: String, calendarID: String, from: Date, to: Date) async throws -> [GoogleCalendarEvent]
}

/// Small read-only Calendar API adapter. Every page must succeed before the caller applies a snapshot.
nonisolated public struct GoogleCalendarClient: GoogleCalendarFetching {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func events(accessToken: String, calendarID: String = "primary", from: Date, to: Date) async throws -> [GoogleCalendarEvent] {
        guard !accessToken.isEmpty, from < to else { throw GoogleCalendarError.invalidRequest }
        var result: [GoogleCalendarEvent] = []
        var pageToken: String?
        var visitedTokens: Set<String> = []
        repeat {
            let request = try Self.request(accessToken: accessToken, calendarID: calendarID,
                                           from: from, to: to, pageToken: pageToken)
            let data = try await fetch(request)
            let page = try JSONDecoder().decode(EventPage.self, from: data)
            result.append(contentsOf: page.items ?? [])
            pageToken = page.nextPageToken
            if let token = pageToken, !visitedTokens.insert(token).inserted {
                throw GoogleCalendarError.repeatedPageToken
            }
        } while pageToken != nil
        return result
    }

    public static func request(accessToken: String, calendarID: String, from: Date, to: Date,
                               pageToken: String? = nil) throws -> URLRequest {
        // Calendar IDs are path segments, not arbitrary URLs.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~@"))
        guard let id = calendarID.addingPercentEncoding(withAllowedCharacters: allowed), !id.isEmpty else {
            throw GoogleCalendarError.invalidRequest
        }
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(id)/events")!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: from)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: to)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "showDeleted", value: "true"),
            URLQueryItem(name: "maxResults", value: "2500")
        ]
        if let pageToken { components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken)) }
        guard let url = components.url else { throw GoogleCalendarError.invalidRequest }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func fetch(_ request: URLRequest) async throws -> Data {
        for attempt in 0...2 {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw GoogleCalendarError.invalidResponse }
            if (200..<300).contains(response.statusCode) { return data }
            if response.statusCode == 401 { throw GoogleCalendarError.authorizationExpired }
            if (response.statusCode == 429 || (500..<600).contains(response.statusCode)), attempt < 2 {
                let retry = min(30, max(1, Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? Double(attempt + 1)))
                try await Task.sleep(for: .seconds(retry))
                continue
            }
            throw GoogleCalendarError.httpStatus(response.statusCode)
        }
        throw GoogleCalendarError.invalidResponse
    }

    private struct EventPage: Decodable {
        let items: [GoogleCalendarEvent]?
        let nextPageToken: String?
    }
}

nonisolated public enum GoogleCalendarError: LocalizedError, Equatable {
    case invalidRequest
    case invalidResponse
    case repeatedPageToken
    case authorizationExpired
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest: return String(localized: "The calendar request is invalid.")
        case .invalidResponse, .repeatedPageToken: return String(localized: "Google returned an incomplete calendar response. Please try again.")
        case .authorizationExpired: return String(localized: "Reconnect Google Calendar to renew access.")
        case .httpStatus(403): return String(localized: "Google Calendar access was denied. Check Calendar API setup and calendar permission.")
        case .httpStatus(429): return String(localized: "Google Calendar is busy. Please try again shortly.")
        case .httpStatus(let status): return String(localized: "Google Calendar could not sync (HTTP \(status)).")
        }
    }
}
