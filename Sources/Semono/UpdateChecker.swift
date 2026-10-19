import AppKit
import Combine
import Foundation

/// A tiny semantic version used only for the GitHub release check. It accepts
/// a leading "v" and a numeric dotted tag; anything else falls back to 0.
struct SemanticVersion: Comparable, Equatable, Sendable {
    let components: [Int]

    init?(_ raw: String) {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }
        let parts = value.split(separator: ".", omittingEmptySubsequences: true)
        guard !parts.isEmpty else { return nil }
        components = parts.map { part in
            let digits = part.prefix { $0.isNumber }
            return Int(digits) ?? 0
        }
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let a = i < lhs.components.count ? lhs.components[i] : 0
            let b = i < rhs.components.count ? rhs.components[i] : 0
            if a != b { return a < b }
        }
        return false
    }
}

/// Checks the latest published GitHub release and drives the menu item and the
/// status bar animation. Manual checks report failures/up-to-date state via an
/// alert; automatic checks stay silent and retry once after ten minutes.
@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case updateAvailable(version: String, url: URL)
        case upToDate
        case failed
    }

    static let shared = UpdateChecker()

    @Published private(set) var state: State = .idle

    private let session: URLSession
    private let releasesURL: URL
    let currentVersion: String

    private var started = false
    private var dailyTimer: Timer?
    private var retryTask: Task<Void, Never>?

    private static let lastCheckKey = "updateLastCheckDate"
    private static let availableVersionKey = "updateAvailableVersion"
    private static let availableURLKey = "updateAvailableURL"
    private static let retryDelay: Duration = .seconds(600)

    var isChecking: Bool {
        if case .checking = state { return true }
        return false
    }

    var hasUpdate: Bool {
        if case .updateAvailable = state { return true }
        return false
    }

    init(
        session: URLSession = .shared,
        releasesURL: URL? = nil,
        currentVersion: String? = nil
    ) {
        self.session = session
        self.releasesURL = releasesURL
            ?? URL(string: "https://api.github.com/repos/WillSat/semono/releases/latest")!
        self.currentVersion = currentVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "0.0.0"
        restoreAvailableUpdate()
    }

    /// Called once at launch and whenever the automatic-update preference
    /// changes. A daily timer checks for the first run of a new calendar day.
    func start() {
        guard !started else {
            settingsChanged()
            return
        }
        started = true
        settingsChanged()
    }

    func settingsChanged() {
        if SettingsStore.shared.autoUpdateCheck {
            startDailyTimer()
            if shouldCheckToday && !hasUpdate && !isChecking && retryTask == nil {
                checkForUpdates(manual: false)
            }
        } else {
            dailyTimer?.invalidate()
            dailyTimer = nil
            retryTask?.cancel()
            retryTask = nil
        }
    }

    func checkForUpdates(manual: Bool) {
        check(manual: manual, retry: false)
    }

    private func check(manual: Bool, retry: Bool) {
        guard !isChecking else { return }
        state = .checking
        Task { @MainActor in
            do {
                let release = try await fetchLatestRelease()
                finishSuccess(release, manual: manual)
            } catch {
                finishFailure(manual: manual, retry: retry)
            }
        }
    }

    func openRelease() {
        guard case let .updateAvailable(_, url) = state else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Scheduling

    private func startDailyTimer() {
        guard dailyTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.dailyTimerFired() }
        }
        timer.tolerance = 60
        dailyTimer = timer
    }

    private func dailyTimerFired() {
        guard SettingsStore.shared.autoUpdateCheck,
              shouldCheckToday,
              !hasUpdate,
              !isChecking,
              retryTask == nil
        else { return }
        checkForUpdates(manual: false)
    }

    private var shouldCheckToday: Bool {
        guard let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date else {
            return true
        }
        return !Calendar.current.isDateInToday(last)
    }

    // MARK: - Results

    private func finishSuccess(_ release: GitHubRelease, manual: Bool) {
        retryTask?.cancel()
        retryTask = nil
        recordCheck()

        let remote = SemanticVersion(release.tagName)
        let current = SemanticVersion(currentVersion)
        if let remote, let current, remote > current {
            state = .updateAvailable(version: release.tagName, url: release.htmlURL)
            UserDefaults.standard.set(release.tagName, forKey: Self.availableVersionKey)
            UserDefaults.standard.set(release.htmlURL.absoluteString, forKey: Self.availableURLKey)
        } else {
            state = .upToDate
            clearAvailableUpdate()
            if manual { presentUpToDateAlert() }
        }
    }

    private func scheduleRetryAfterFailure() {
        retryTask?.cancel()
        retryTask = Task { @MainActor in
            try? await Task.sleep(for: Self.retryDelay)
            guard !Task.isCancelled else { return }
            retryTask = nil
            check(manual: false, retry: true)
        }
    }

    /// Manual checks do not retry; automatic checks get one ten-minute retry.
    private func finishFailure(manual: Bool, retry: Bool) {
        state = .failed
        if manual {
            retryTask?.cancel()
            retryTask = nil
            recordCheck()
            presentFailureAlert()
            return
        }
        if retry {
            recordCheck()
            return
        }
        if retryTask == nil {
            scheduleRetryAfterFailure()
        }
    }

    private func recordCheck() {
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
    }

    private func clearAvailableUpdate() {
        UserDefaults.standard.removeObject(forKey: Self.availableVersionKey)
        UserDefaults.standard.removeObject(forKey: Self.availableURLKey)
    }

    private func restoreAvailableUpdate() {
        guard let version = UserDefaults.standard.string(forKey: Self.availableVersionKey),
              let rawURL = UserDefaults.standard.string(forKey: Self.availableURLKey),
              let url = URL(string: rawURL),
              let remote = SemanticVersion(version),
              let current = SemanticVersion(currentVersion),
              remote > current
        else { return }
        state = .updateAvailable(version: version, url: url)
    }

    // MARK: - Network

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    private enum UpdateError: Error {
        case badResponse
        case invalidRelease
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: releasesURL)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Semono/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.badResponse
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.tagName.isEmpty else { throw UpdateError.invalidRelease }
        return release
    }

    // MARK: - Alerts

    private func presentUpToDateAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = LocaleManager.shared.localized("You're up to date.")
        alert.informativeText = "\(LocaleManager.shared.localized("Version")) \(currentVersion)"
        alert.addButton(withTitle: LocaleManager.shared.localized("OK"))
        alert.runModal()
    }

    private func presentFailureAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = LocaleManager.shared.localized("Update check failed.")
        alert.informativeText = LocaleManager.shared.localized("Please try again later.")
        alert.addButton(withTitle: LocaleManager.shared.localized("OK"))
        alert.runModal()
    }
}
