import AirBarCore
import AppKit

/// Checks GitHub Releases for a newer version once a day. Updating stays manual:
/// the menu links to the release page.
@MainActor
final class UpdateChecker: ObservableObject {
    struct Release {
        let version: Version
        let url: URL
    }

    @Published private(set) var available: Release?

    /// "owner/repo", from the AirBarRepository key in Info.plist.
    private let repository = Bundle.main.object(forInfoDictionaryKey: "AirBarRepository") as? String
    private let interval: TimeInterval = 24 * 60 * 60
    private var timer: Timer?

    var releasesPage: URL? { repository.flatMap { URL(string: "https://github.com/\($0)/releases") } }

    func start() {
        guard repository != nil else { return }
        let last = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        if Date().timeIntervalSince1970 - last > interval {
            Task { await check() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.check() }
        }
    }

    /// Checks now. When `userInitiated`, reports "up to date" or errors in an alert.
    func check(userInitiated: Bool = false) async {
        guard let repository, let current = Version(About.version),
              let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String, let latest = Version(tag),
                  let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
                throw URLError(.badServerResponse)
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
            available = latest > current ? Release(version: latest, url: page) : nil
            if userInitiated && available == nil {
                alert("AirBar is up to date", "You're running the latest version, \(current).")
            }
        } catch {
            if userInitiated { alert("Couldn't check for updates", "Check your internet connection and try again.") }
        }
    }

    private func alert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
