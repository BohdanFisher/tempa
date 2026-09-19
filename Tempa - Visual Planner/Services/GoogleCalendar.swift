import Foundation
import AuthenticationServices
import CryptoKit
import CloudKit
import Observation
import UIKit

/// One calendar event, whichever door it came through — the phone's own
/// calendars (EventKit) or a Google account signed in right here.
struct CalendarEvent: Codable, Sendable {
    enum Source: String, Codable, Sendable { case apple, google }

    let source: Source
    /// Stable mirror key. Built the same way for both doors — the iCalendar
    /// UID, plus the original start for one occurrence of a repeating event —
    /// so a Google event seen through the iPhone's accounts AND through the
    /// Google sign-in is ONE block, not two.
    let key: String
    let title: String
    let start: Date
    let end: Date
    /// The event already carries an alert the phone will deliver.
    let ringsOnItsOwn: Bool
    let category: String

    var minutes: Int { min(max(Int(end.timeIntervalSince(start) / 60), 5), 12 * 60) }
    var fingerprint: String { "\(Int(start.timeIntervalSince1970))|\(minutes)|\(title)" }

    /// The colour a block lands in. Only the calendar's own name is a fair
    /// hint — guessing from the event title would be wrong as often as right.
    static func category(calendarName: String, isExchange: Bool = false) -> String {
        let name = calendarName.lowercased()
        let workWords = ["work", "job", "office", "робот", "arbeit", "büro", "trabajo", "travail",
                         "trabalho", "werk", "jobb", "työ", "exchange", "outlook"]
        return isExchange || workWords.contains(where: name.contains) ? "work" : "personal"
    }
}

/// Where the Google OAuth client ID comes from — and whether the Google
/// option is offered at all.
///
/// The client itself (Google Cloud project "Tempa", tempa-509110, iOS client
/// "Tempa iOS") is known to the build. What arrives from outside is the
/// SWITCH: a record in the app's CloudKit PUBLIC database
/// (AppConfig/google-calendar-client-id, String field "value"), the same way
/// the AI key arrives. Until Google has verified the app, an "unverified app"
/// screen in the middle of the funnel would cost more trials than the feature
/// earns — so a Release build shows nothing Google until that record exists.
/// Its value is either "on" (use the bundled client) or a full client ID
/// (swap the client without an update). Delete the record → off again.
/// DEBUG builds always offer Google: the owner is a test user of the client.
/// (A client ID is not a secret: iOS OAuth clients have none, PKCE stands in.)
enum GoogleCalendarConfig {
    private static let cacheKey = "googleCalendarClientID"
    private static let recordName = "google-calendar-client-id"
    private static let cloudContainerID = "iCloud.Bohdan-Rybak.Tempa---Visual-Planner"
    private static let bundledClientID = "959128014557-gj6r7dt3bsh1l68pf1mnnojnnc5opqdu.apps.googleusercontent.com"

    static var clientID: String? {
        #if DEBUG
        // "-google-client-id <id>": try another client; "-google-client-id off": hide the option.
        if let arg = UserDefaults.standard.string(forKey: "google-client-id"), !arg.isEmpty {
            return arg == "off" ? nil : arg
        }
        return bundledClientID
        #else
        guard let value = UserDefaults.standard.string(forKey: cacheKey), !value.isEmpty else { return nil }
        return value.hasSuffix(".apps.googleusercontent.com") ? value : bundledClientID
        #endif
    }

    /// Call once at launch. A missing record clears the cache — deleting the
    /// record is how the option is switched back off.
    static func refreshFromCloud() async {
        do {
            let record = try await CKContainer(identifier: cloudContainerID)
                .publicCloudDatabase.record(for: CKRecord.ID(recordName: recordName))
            let value = (record["value"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            UserDefaults.standard.set(value, forKey: cacheKey)
        } catch let error as CKError where error.code == .unknownItem {
            UserDefaults.standard.removeObject(forKey: cacheKey)
        } catch {
            // Offline, no route to iCloud: keep whatever we knew.
        }
    }
}

enum GoogleCalendarError: Error {
    case notConfigured
    case cancelled
    /// Signed in, but left "view events" unticked on Google's consent page.
    case calendarNotGranted
    case authFailed(String)
    case notConnected
    case network(Error)
    case api(Int)
}

/// A Google account connected for one thing only: READING its calendars.
///
/// No Google SDK and no server: the system browser sheet
/// (ASWebAuthenticationSession) runs OAuth with PKCE, the refresh token lives
/// in the Keychain, and the Calendar API is called straight from the phone.
/// The two narrowest scopes that do the job are asked for — list the
/// calendars, read their events — nothing that can write, and no profile.
@MainActor @Observable
final class GoogleCalendar: NSObject {
    static let shared = GoogleCalendar()

    struct CalendarRef: Codable, Identifiable, Sendable {
        let id: String
        let title: String
        let colorHex: String?
        /// Ticked in the user's own Google Calendar (or their primary one).
        /// What they keep unticked there starts switched off here too.
        var isShownInGoogle: Bool = true
    }

    private static let eventsScope = "https://www.googleapis.com/auth/calendar.events.readonly"
    private static let listScope = "https://www.googleapis.com/auth/calendar.calendarlist.readonly"
    private static let keychainAccount = "com.tempa.google-calendar-refresh-token"
    private static let emailKey = "googleCalendarEmail"
    private static let calendarsKey = "googleCalendarList"
    /// Set when THIS install connected the account. The Keychain outlives the
    /// app: without the marker, a reinstall would open "already connected"
    /// to an account the person never chose here.
    private static let connectedHereKey = "googleCalendarConnectedHere"
    private static let canListKey = "googleCalendarCanList"

    /// The connected account, as Google names its primary calendar.
    private(set) var email: String? = UserDefaults.standard.string(forKey: GoogleCalendar.emailKey)
    private(set) var isConnected = false
    /// The account's calendars as of the last fetch — for the picker.
    private(set) var calendars: [CalendarRef] = []

    private var accessToken: String?
    private var accessTokenExpiry = Date.distantPast
    private var session: ASWebAuthenticationSession?

    /// The option exists at all only once a client ID is known.
    var isAvailable: Bool { GoogleCalendarConfig.clientID != nil }

    private override init() {
        super.init()
        if UserDefaults.standard.bool(forKey: Self.connectedHereKey) {
            isConnected = Self.readRefreshToken() != nil
        } else {
            Self.deleteRefreshToken()   // a leftover from an earlier install
        }
        if let data = UserDefaults.standard.data(forKey: Self.calendarsKey),
           let list = try? JSONDecoder().decode([CalendarRef].self, from: data) {
            calendars = list
        }
    }

    // MARK: - Connect / disconnect

    /// Runs the Google sign-in sheet and keeps the refresh token.
    func connect() async throws {
        guard let clientID = GoogleCalendarConfig.clientID else { throw GoogleCalendarError.notConfigured }
        let scheme = Self.redirectScheme(for: clientID)
        let redirect = "\(scheme):/oauth2redirect"
        let verifier = Self.randomURLSafe(64)
        let state = Self.randomURLSafe(24)

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "\(Self.listScope) \(Self.eventsScope)"),
            .init(name: "code_challenge", value: Self.challenge(for: verifier)),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        let callback = try await authorize(url: comps.url!, scheme: scheme)

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func item(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let problem = item("error") {
            // "access_denied" is the user pressing Cancel on Google's page.
            throw problem == "access_denied" ? GoogleCalendarError.cancelled : GoogleCalendarError.authFailed(problem)
        }
        guard item("state") == state, let code = item("code") else {
            throw GoogleCalendarError.authFailed("state mismatch")
        }

        let token = try await tokenRequest([
            "client_id": clientID, "code": code, "code_verifier": verifier,
            "grant_type": "authorization_code", "redirect_uri": redirect,
        ])
        guard let refresh = token["refresh_token"] as? String else {
            throw GoogleCalendarError.authFailed("no refresh token")
        }
        // Google shows one tick box per scope. Reading events is the one we
        // can't do without; if only the calendar LIST was left unticked, the
        // account's main calendar is still readable — take that.
        let granted = Set((token["scope"] as? String ?? "").split(separator: " ").map(String.init))
        guard granted.contains(Self.eventsScope) else {
            await revoke(refresh)
            throw GoogleCalendarError.calendarNotGranted
        }
        UserDefaults.standard.set(granted.contains(Self.listScope), forKey: Self.canListKey)
        UserDefaults.standard.set(true, forKey: Self.connectedHereKey)
        Self.storeRefreshToken(refresh)
        adopt(token)
        isConnected = true
    }

    /// Forgets the account here and tells Google to forget the grant.
    func disconnect() async {
        if let refresh = Self.readRefreshToken() { await revoke(refresh) }
        forget()
    }

    private func forget() {
        Self.deleteRefreshToken()
        accessToken = nil
        accessTokenExpiry = .distantPast
        email = nil
        calendars = []
        isConnected = false
        UserDefaults.standard.removeObject(forKey: Self.emailKey)
        UserDefaults.standard.removeObject(forKey: Self.calendarsKey)
        UserDefaults.standard.removeObject(forKey: Self.connectedHereKey)
        UserDefaults.standard.removeObject(forKey: Self.canListKey)
    }

    // MARK: - Reading

    /// The account's calendars, fresh from Google (kept for the picker).
    @discardableResult
    func loadCalendars() async throws -> [CalendarRef] {
        guard isConnected else { throw GoogleCalendarError.notConnected }
        guard UserDefaults.standard.bool(forKey: Self.canListKey) else {
            // The list wasn't granted: the main calendar, under Google's alias.
            let only = [CalendarRef(id: "primary", title: "Google", colorHex: nil)]
            calendars = only
            return only
        }
        let list = try await get("/users/me/calendarList", query: [
            .init(name: "minAccessRole", value: "reader"),
            .init(name: "fields", value: "items(id,summary,summaryOverride,backgroundColor,primary,selected)"),
        ])
        let items = list["items"] as? [[String: Any]] ?? []
        let refs = Self.parseCalendars(items)
        calendars = refs
        if let data = try? JSONEncoder().encode(refs) { UserDefaults.standard.set(data, forKey: Self.calendarsKey) }
        if let primary = items.first(where: { $0["primary"] as? Bool == true })?["id"] as? String {
            email = primary
            UserDefaults.standard.set(primary, forKey: Self.emailKey)
        }
        return refs
    }

    /// Timed events in [from, to) from the given calendars (ids as Google
    /// gives them).
    func events(from: Date, to: Date, calendarIDs: [String: String]) async throws -> [CalendarEvent] {
        guard isConnected else { throw GoogleCalendarError.notConnected }
        let stamp = ISO8601DateFormatter()   // UTC with "Z" — no "+" to be misread in a query
        var out: [CalendarEvent] = []
        for (id, title) in calendarIDs {
            var pageToken: String?
            repeat {
                var query: [URLQueryItem] = [
                    .init(name: "singleEvents", value: "true"),
                    .init(name: "orderBy", value: "startTime"),
                    .init(name: "timeMin", value: stamp.string(from: from)),
                    .init(name: "timeMax", value: stamp.string(from: to)),
                    .init(name: "maxResults", value: "250"),
                    .init(name: "fields", value: "nextPageToken,items(id,iCalUID,summary,status,start,end,recurringEventId,originalStartTime,eventType,attendees(self,responseStatus))"),
                ]
                if let pageToken { query.append(.init(name: "pageToken", value: pageToken)) }
                let page = try await get("/calendars/\(Self.pathSegment(id))/events", query: query)
                out += Self.parseEvents(page["items"] as? [[String: Any]] ?? [], calendarName: title)
                    .filter { $0.start >= from }
                pageToken = page["nextPageToken"] as? String
            } while pageToken != nil
        }
        return out
    }

    /// Calendars worth offering: the account's own and shared ones — not
    /// the holiday and birthday feeds (all-day anyway). Google omits
    /// "selected" when a calendar is unticked, so only an explicit true (or
    /// the primary calendar) counts as shown.
    static func parseCalendars(_ items: [[String: Any]]) -> [CalendarRef] {
        items.compactMap { item in
            guard let id = item["id"] as? String,
                  !id.contains("#holiday@"), !id.contains("#contacts@"), !id.contains("#weather@") else { return nil }
            let title = (item["summaryOverride"] as? String) ?? (item["summary"] as? String) ?? id
            let shown = item["selected"] as? Bool == true || item["primary"] as? Bool == true
            return CalendarRef(id: id, title: title, colorHex: item["backgroundColor"] as? String,
                               isShownInGoogle: shown)
        }
    }

    /// Google's event JSON → blocks. Left out: all-day entries (a date, not
    /// a block of time), cancelled events, invitations the user declined,
    /// and "working location" / birthday markers.
    static func parseEvents(_ items: [[String: Any]], calendarName: String) -> [CalendarEvent] {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ any: Any?) -> Date? {
            guard let s = (any as? [String: Any])?["dateTime"] as? String else { return nil }
            return plain.date(from: s) ?? fractional.date(from: s)
        }
        return items.compactMap { item in
            guard item["status"] as? String != "cancelled",
                  !["workingLocation", "birthday"].contains(item["eventType"] as? String ?? ""),
                  let start = date(item["start"]), let end = date(item["end"]), end > start,
                  let uid = (item["iCalUID"] as? String) ?? (item["id"] as? String) else { return nil }
            let declined = (item["attendees"] as? [[String: Any]] ?? []).contains {
                $0["self"] as? Bool == true && $0["responseStatus"] as? String == "declined"
            }
            guard !declined else { return nil }

            var key = uid
            if item["recurringEventId"] != nil {
                let original = date(item["originalStartTime"]) ?? start
                key += "|\(Int(original.timeIntervalSince1970 / 60))"
            }
            let title = (item["summary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return CalendarEvent(
                source: .google, key: key,
                title: title.isEmpty ? String(localized: "Calendar event", bundle: .appLanguage) : title,
                start: start, end: end,
                // Whether a Google reminder reaches this phone depends on the
                // Google Calendar app being installed — not something we can
                // know. Tempa's own gentle nudge stays on.
                ringsOnItsOwn: false,
                category: CalendarEvent.category(calendarName: calendarName)
            )
        }
    }

    // MARK: - HTTP

    private func get(_ path: String, query: [URLQueryItem]) async throws -> [String: Any] {
        // `path` arrives percent-encoded (a calendar id is an e-mail address).
        guard var comps = URLComponents(string: "https://www.googleapis.com") else { throw GoogleCalendarError.api(0) }
        comps.percentEncodedPath = "/calendar/v3" + path
        comps.queryItems = query
        guard let url = comps.url else { throw GoogleCalendarError.api(0) }

        for attempt in 0..<2 {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(try await validAccessToken(forceRefresh: attempt == 1))",
                             forHTTPHeaderField: "Authorization")
            let (data, response) = try await send(request)
            if response.statusCode == 401, attempt == 0 { continue }   // token died early — refresh once
            guard response.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw GoogleCalendarError.api(response.statusCode)
            }
            return json
        }
        throw GoogleCalendarError.api(401)
    }

    private func validAccessToken(forceRefresh: Bool) async throws -> String {
        if !forceRefresh, let token = accessToken, accessTokenExpiry > Date().addingTimeInterval(60) { return token }
        guard let clientID = GoogleCalendarConfig.clientID else { throw GoogleCalendarError.notConfigured }
        guard let refresh = Self.readRefreshToken() else { throw GoogleCalendarError.notConnected }
        let token = try await tokenRequest([
            "client_id": clientID, "refresh_token": refresh, "grant_type": "refresh_token",
        ])
        adopt(token)
        guard let access = accessToken else { throw GoogleCalendarError.authFailed("no access token") }
        return access
    }

    private func adopt(_ token: [String: Any]) {
        accessToken = token["access_token"] as? String
        accessTokenExpiry = Date().addingTimeInterval((token["expires_in"] as? Double) ?? 3000)
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(fields)
        let (data, response) = try await send(request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if response.statusCode == 400, json["error"] as? String == "invalid_grant" {
            // Access was withdrawn on Google's side (or the token aged out):
            // the account is no longer connected, and the UI should say so.
            forget()
            throw GoogleCalendarError.notConnected
        }
        guard response.statusCode == 200 else { throw GoogleCalendarError.api(response.statusCode) }
        return json
    }

    private func revoke(_ token: String) async {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(["token": token])
        _ = try? await send(request)
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw GoogleCalendarError.api(0) }
            return (data, http)
        } catch let error as GoogleCalendarError {
            throw error
        } catch {
            throw GoogleCalendarError.network(error)
        }
    }

    // MARK: - The sign-in sheet

    private func authorize(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { @Sendable callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    continuation.resume(throwing: GoogleCalendarError.cancelled)
                } else {
                    continuation.resume(throwing: GoogleCalendarError.authFailed(error?.localizedDescription ?? "unknown"))
                }
            }
            session.presentationContextProvider = self
            // Shares Safari's cookies on purpose: someone already signed in
            // to Google picks their account instead of typing a password.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                self.session = nil
                continuation.resume(throwing: GoogleCalendarError.authFailed("could not start"))
            }
        }
    }

    // MARK: - Pieces

    /// "123-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.123-abc"
    static func redirectScheme(for clientID: String) -> String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }

    private static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return String(Data(bytes).base64URLEncoded.prefix(count))
    }

    /// RFC 3986 "unreserved" — everything else gets percent-encoded.
    private static let unreserved: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func pathSegment(_ raw: String) -> String {
        raw.addingPercentEncoding(withAllowedCharacters: unreserved) ?? raw
    }

    private static func formEncode(_ fields: [String: String]) -> Data {
        fields
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    // MARK: - Keychain

    private static func readRefreshToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func storeRefreshToken(_ token: String) {
        deleteRefreshToken()
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func deleteRefreshToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension GoogleCalendar: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first ?? ASPresentationAnchor()
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
