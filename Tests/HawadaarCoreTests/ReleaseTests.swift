import Foundation
import Testing
@testable import HawadaarCore

struct ReleaseTests {
    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    @Test func parsesZipAssetAndDigest() throws {
        let data = json([
            "tag_name": "v1.2.0",
            "html_url": "https://github.com/o/r/releases/tag/v1.2.0",
            "assets": [
                ["name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"],
                ["name": "Hawadaar-1.2.0.zip", "browser_download_url": "https://example.com/Hawadaar-1.2.0.zip",
                 "digest": "sha256:ABCDEF"],
            ],
        ])
        let release = try #require(Release(githubJSON: data))
        #expect(release.version == Version("1.2.0"))
        #expect(release.download?.lastPathComponent == "Hawadaar-1.2.0.zip")
        #expect(release.sha256 == "abcdef")
        #expect(release.isInstallable)
    }

    @Test func releaseWithoutDigestIsNotInstallable() throws {
        let data = json(["tag_name": "v1.2.0", "html_url": "https://github.com/o/r",
                         "assets": [["name": "a.zip", "browser_download_url": "https://example.com/a.zip"]]])
        let release = try #require(Release(githubJSON: data))
        #expect(release.sha256 == nil)
        #expect(!release.isInstallable)
    }

    @Test func rejectsMalformedResponses() {
        #expect(Release(githubJSON: Data("{}".utf8)) == nil)
        #expect(Release(githubJSON: json(["tag_name": "nightly", "html_url": "https://x.y"])) == nil)
    }

    @Test func checksumOfFile() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "checksum-test.txt")
        try Data("abc".utf8).write(to: file)
        #expect(try Checksum.sha256(of: file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
