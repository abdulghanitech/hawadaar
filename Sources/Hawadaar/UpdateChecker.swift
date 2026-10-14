import AppKit
import CryptoKit
import HawadaarCore
import Security

/// Checks GitHub Releases for a newer version once a day and installs it in place on request:
/// download, verify the checksum GitHub publishes and the code signature, swap the app, relaunch.
@MainActor
final class UpdateChecker: ObservableObject {
    enum InstallState: Equatable { case idle, installing }

    @Published private(set) var available: Release?
    @Published private(set) var installState: InstallState = .idle

    /// "owner/repo", from the HawadaarRepository key in Info.plist.
    private let repository = Bundle.main.object(forInfoDictionaryKey: "HawadaarRepository") as? String
    private let interval: TimeInterval = 24 * 60 * 60
    private var timer: Timer?

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
            guard (response as? HTTPURLResponse)?.statusCode == 200, let latest = Release(githubJSON: data) else {
                throw URLError(.badServerResponse)
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
            available = latest.version > current ? latest : nil
            if userInitiated && available == nil {
                alert("Hawadaar is up to date", "You're running the latest version, \(current).")
            }
        } catch {
            if userInitiated { alert("Couldn't check for updates", "Check your internet connection and try again.") }
        }
    }

    // MARK: - Installing

    /// Installs the available release and relaunches. Falls back to the release page when
    /// in-place installation isn't possible.
    func install() {
        guard let release = available, installState == .idle else { return }
        let appURL = Self.installedAppURL
        guard release.isInstallable, let download = release.download, let checksum = release.sha256 else {
            NSWorkspace.shared.open(release.page)
            return
        }
        if let problem = Self.locationProblem(appURL) {
            offerReleasePage(release, reason: problem)
            return
        }
        installState = .installing
        Task {
            do {
                try await Self.installUpdate(from: download, sha256: checksum, version: release.version, replacing: appURL)
                Self.relaunch(appURL)
            } catch {
                installState = .idle
                offerReleasePage(release, reason: error.localizedDescription)
            }
        }
    }

    private struct UpdateError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// Where the app really lives. macOS runs a freshly downloaded app from a random read-only copy
    /// ("App Translocation"); the original location is what has to be replaced.
    static var installedAppURL: URL {
        let running = Bundle.main.bundleURL
        guard running.path.contains("/AppTranslocation/"),
              let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW),
              let symbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL") else { return running }
        typealias OriginalPath = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        let originalPath = unsafeBitCast(symbol, to: OriginalPath.self)
        return (originalPath(running as CFURL, nil)?.takeRetainedValue() as URL?) ?? running
    }

    /// Why the app can't be replaced in place, if it can't.
    private static func locationProblem(_ appURL: URL) -> String? {
        if appURL.path.contains("/AppTranslocation/") {
            return "Move Hawadaar to your Applications folder to enable one-click updates."
        }
        if !FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) {
            return "Hawadaar doesn't have permission to replace itself in \(appURL.deletingLastPathComponent().path)."
        }
        return nil
    }

    private nonisolated static func installUpdate(from download: URL, sha256: String, version: Version,
                                                  replacing appURL: URL) async throws {
        let work = FileManager.default.temporaryDirectory.appending(path: "HawadaarUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        // 1. Download and check the file is exactly the one GitHub published.
        let (downloaded, response) = try await URLSession.shared.download(from: download)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("The download failed.") }
        let zip = work.appending(path: "update.zip")
        try FileManager.default.moveItem(at: downloaded, to: zip)
        guard try Checksum.sha256(of: zip) == sha256 else {
            throw UpdateError("The downloaded file didn't match the published checksum.")
        }

        // 2. Unpack and check it's a newer Hawadaar, signed by the same certificate as this one.
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, work.path]
        try unzip.run()
        unzip.waitUntilExit()
        let newApp = work.appending(path: appURL.lastPathComponent)
        guard unzip.terminationStatus == 0, let bundle = Bundle(url: newApp),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(Version.init) == version else {
            throw UpdateError("The update didn't contain the expected version of Hawadaar.")
        }
        guard let current = signingCertificate(of: appURL), signingCertificate(of: newApp) == current else {
            throw UpdateError("The update isn't signed by the Hawadaar release certificate.")
        }

        // 3. Swap it in.
        _ = try FileManager.default.replaceItemAt(appURL, withItemAt: newApp)
    }

    /// SHA-256 of the leaf signing certificate, after checking the signature is valid.
    private nonisolated static func signingCertificate(of app: URL) -> Data? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), nil) == errSecSuccess
        else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let certificates = (info as? [String: Any])?[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else { return nil }
        return Data(SHA256.hash(data: SecCertificateCopyData(leaf) as Data))
    }

    /// Starts the new copy once this one has quit.
    private static func relaunch(_ appURL: URL) {
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                              appURL.path]
        try? relaunch.run()
        NSApp.terminate(nil)
    }

    private func offerReleasePage(_ release: Release, reason: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn't install Hawadaar \(release.version) automatically"
        alert.informativeText = "\(reason)\n\nYou can download it from the release page instead."
        alert.addButton(withTitle: "Open Release Page")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.page) }
    }

    private func alert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
