import Testing
@testable import HawadaarCore

struct VersionTests {
    @Test func parsesTagsAndSuffixes() {
        #expect(Version("v1.2.3")?.components == [1, 2, 3])
        #expect(Version("1.0.0-beta.1")?.components == [1, 0, 0])
        #expect(Version("nightly") == nil)
        #expect(Version("") == nil)
    }

    @Test func comparesNumericallyNotLexically() throws {
        #expect(try #require(Version("1.10.0")) > #require(Version("1.9.0")))
        #expect(try #require(Version("2.0")) > #require(Version("1.99.99")))
    }

    @Test func missingComponentsCountAsZero() throws {
        #expect(try #require(Version("1.0")) == #require(Version("v1.0.0")))
        #expect(try #require(Version("1.0.1")) > #require(Version("1.0")))
    }
}
