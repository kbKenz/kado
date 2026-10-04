import Foundation

/// Portable regression checks for the actual REST/event sources, without an iOS simulator.
@main
enum GoogleCalendarChecks {
    static func main() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let raw = #"{"id":"thomas","summary":"Meeting with Thomas","updated":"2026-10-04T02:00:00.123Z","start":{"dateTime":"2026-10-04T09:30:00+08:00"},"end":{"dateTime":"2026-10-04T10:30:00+08:00"}}"#
        let event = try JSONDecoder().decode(GoogleCalendarEvent.self, from: Data(raw.utf8))
        let schedule = try unwrap(event.schedule(using: calendar), "timed event")
        try check(event.summary == "Meeting with Thomas", "event title")
        try check(schedule.end.timeIntervalSince(schedule.start) == 3600, "RFC3339 offset")
        try check(GoogleCalendarEvent.parseTimestamp(event.updated!) != nil, "fractional timestamp")
        let cancelled = try JSONDecoder().decode(GoogleCalendarEvent.self, from: Data(#"{"id":"gone","status":"cancelled"}"#.utf8))
        try check(cancelled.isCancelled && cancelled.start == nil, "sparse cancellation")
        let allDay = GoogleCalendarEvent(id: "all", start: .init(date: "2026-03-08"), end: .init(date: "2026-03-10"))
        let allDaySchedule = try unwrap(allDay.schedule(using: calendar), "all-day event")
        try check(allDaySchedule.isAllDay, "all-day detection")
        try check(calendar.dateComponents([.day], from: allDaySchedule.start, to: allDaySchedule.end).day == 2, "exclusive all-day end across DST")
        try check(allDaySchedule.end.timeIntervalSince(allDaySchedule.start) == 47 * 3600, "DST day length")
        try check(GoogleCalendarEvent.EventDate(date: "2026-02-30").resolved(using: calendar) == nil, "reject normalized invalid date")
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = calendar.timeZone
        try check(GoogleCalendarEvent.EventDate(date: "2026-03-08").resolved(using: buddhist) == allDaySchedule.start, "Gregorian API dates with Buddhist presentation calendar")
        let invalid = GoogleCalendarEvent(id: "bad", start: .init(dateTime: "2026-10-04T10:30:00Z"), end: .init(dateTime: "2026-10-04T09:30:00Z"))
        try check(invalid.schedule(using: calendar) == nil, "reject reversed interval")

        let from = allDaySchedule.start
        let to = allDaySchedule.end
        let request = try GoogleCalendarClient.request(accessToken: "test-only", calendarID: "primary", from: from, to: to)
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        try check(query.contains(.init(name: "singleEvents", value: "true")), "expand recurring events")
        try check(query.contains(.init(name: "showDeleted", value: "true")), "include cancellations")
        try check(!query.contains { $0.name == "syncToken" }, "bounded snapshots never mix sync tokens")
        try check(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only", "bearer header")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CalendarMockProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = GoogleCalendarClient(session: session)
        CalendarMockProtocol.server.reset(mode: .pages)
        let imported = try await client.events(accessToken: "test-only", calendarID: "primary", from: from, to: to)
        try check(imported.map(\.id) == ["first", "second"], "pagination collects every page")
        try check(CalendarMockProtocol.server.requestCount == 2, "pagination request count")

        CalendarMockProtocol.server.reset(mode: .repeatedToken)
        do {
            _ = try await client.events(accessToken: "test-only", calendarID: "primary", from: from, to: to)
            throw CheckFailure(message: "repeated page token was accepted")
        } catch GoogleCalendarError.repeatedPageToken { }
        CalendarMockProtocol.server.reset(mode: .secondPageFails)
        do {
            _ = try await client.events(accessToken: "test-only", calendarID: "primary", from: from, to: to)
            throw CheckFailure(message: "partial snapshot was accepted")
        } catch GoogleCalendarError.httpStatus(403) { }
        CalendarMockProtocol.server.reset(mode: .unauthorized)
        do {
            _ = try await client.events(accessToken: "test-only", calendarID: "primary", from: from, to: to)
            throw CheckFailure(message: "expired authorization was accepted")
        } catch GoogleCalendarError.authorizationExpired { }
        CalendarMockProtocol.server.reset(mode: .empty)
        let empty = try await client.events(accessToken: "test-only", calendarID: "primary", from: from, to: to)
        try check(empty.isEmpty, "valid empty snapshot")
        print("PASS: Calendar event/date validation, DST, request shape, pagination, duplicate-token protection, partial-response failure, authorization, empty calendar.")
    }

    static func check(_ condition: @autoclosure () -> Bool, _ label: String) throws {
        if !condition() { throw CheckFailure(message: label) }
    }
    static func unwrap<T>(_ value: T?, _ label: String) throws -> T {
        guard let value else { throw CheckFailure(message: label) }
        return value
    }
}

struct CheckFailure: Error { let message: String }

final class CalendarMockProtocol: URLProtocol, @unchecked Sendable {
    static let server = Server()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (code, text) = Self.server.respond(to: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

/// Synchronous URLProtocol callbacks may run on different session queues.
final class Server: @unchecked Sendable {
    enum Mode { case pages, repeatedToken, secondPageFails, unauthorized, empty }
    private let lock = NSLock()
    private var mode: Mode = .pages
    private var count = 0
    var requestCount: Int { lock.withLock { count } }
    func reset(mode: Mode) { lock.withLock { self.mode = mode; count = 0 } }
    func respond(to request: URLRequest) -> (Int, String) {
        lock.withLock {
            count += 1
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "pageToken" }?.value
            switch mode {
            case .unauthorized: return (401, "{}")
            case .empty: return (200, #"{"items":[]}"#)
            case .secondPageFails where page != nil: return (403, "{}")
            case .repeatedToken: return (200, #"{"items":[],"nextPageToken":"again"}"#)
            default:
                if page == nil { return (200, #"{"items":[{"id":"first","status":"cancelled"}],"nextPageToken":"page-two"}"#) }
                return (200, #"{"items":[{"id":"second","status":"cancelled"}]}"#)
            }
        }
    }
}
