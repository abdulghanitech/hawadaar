import CryptoKit
import Foundation

/// The parts of a GitHub "latest release" response the updater needs.
public struct Release: Equatable {
    public let version: Version
    public let page: URL
    /// The app zip, when the release has one.
    public let download: URL?
    /// Lowercase hex SHA-256 of the zip, as published by GitHub.
    public let sha256: String?

    public static func == (lhs: Release, rhs: Release) -> Bool {
        lhs.version == rhs.version && lhs.page == rhs.page && lhs.download == rhs.download && lhs.sha256 == rhs.sha256
    }

    /// Parses `GET /repos/{owner}/{repo}/releases/latest`. The zip is the first `.zip` asset;
    /// its checksum comes from the asset's `digest` field ("sha256:<hex>").
    public init?(githubJSON data: Data) {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = json["tag_name"] as? String, let version = Version(tag),
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        self.version = version
        self.page = page
        let zip = (json["assets"] as? [[String: Any]] ?? []).first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
        download = (zip?["browser_download_url"] as? String).flatMap(URL.init(string:))
        let digest = zip?["digest"] as? String
        sha256 = digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)).lowercased() : nil }
    }

    /// Whether this release can be installed in place: it has a zip with a published checksum.
    public var isInstallable: Bool { download != nil && sha256 != nil }
}

public enum Checksum {
    /// Lowercase hex SHA-256 of a file.
    public static func sha256(of file: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: file, options: .mappedIfSafe))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
