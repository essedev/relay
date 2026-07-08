@testable import Core
import Foundation
import Testing

struct SemanticVersionTests {
    @Test func parsesPlainAndPrefixed() {
        #expect(SemanticVersion("0.5.5") == SemanticVersion(major: 0, minor: 5, patch: 5))
        #expect(SemanticVersion("v0.5.5") == SemanticVersion(major: 0, minor: 5, patch: 5))
        #expect(SemanticVersion("1.2") == SemanticVersion(major: 1, minor: 2, patch: 0))
        #expect(SemanticVersion("3") == SemanticVersion(major: 3, minor: 0, patch: 0))
    }

    @Test func dropsPrereleaseAndBuildSuffix() {
        #expect(SemanticVersion("1.2.3-beta.1") == SemanticVersion(major: 1, minor: 2, patch: 3))
        #expect(SemanticVersion("v1.2.3+sha") == SemanticVersion(major: 1, minor: 2, patch: 3))
    }

    @Test func rejectsGarbage() {
        #expect(SemanticVersion("") == nil)
        #expect(SemanticVersion("nope") == nil)
    }

    @Test func ordersByComponents() {
        #expect(SemanticVersion(major: 0, minor: 5, patch: 4) < SemanticVersion(
            major: 0,
            minor: 5,
            patch: 5
        ))
        #expect(SemanticVersion(major: 0, minor: 5, patch: 5) < SemanticVersion(
            major: 0,
            minor: 6,
            patch: 0
        ))
        #expect(SemanticVersion(major: 0, minor: 9, patch: 9) < SemanticVersion(
            major: 1,
            minor: 0,
            patch: 0
        ))
        #expect(SemanticVersion(major: 1, minor: 0, patch: 0) == SemanticVersion(
            major: 1,
            minor: 0,
            patch: 0
        ))
    }
}

struct ReleaseCheckTests {
    private func json(tag: String, draft: Bool = false, prerelease: Bool = false) -> Data {
        Data(
            """
            {
              "tag_name": "\(tag)",
              "html_url": "https://github.com/essedev/relay/releases/tag/\(tag)",
              "draft": \(draft),
              "prerelease": \(prerelease)
            }
            """.utf8
        )
    }

    private func release(_ version: SemanticVersion) throws -> LatestRelease {
        let url = try #require(URL(string: "https://example.com/r"))
        return LatestRelease(version: version, releaseURL: url)
    }

    @Test func parsesLatest() {
        let release = ReleaseCheck.parseLatest(from: json(tag: "v0.5.6"))
        #expect(release?.version == SemanticVersion(major: 0, minor: 5, patch: 6))
        #expect(release?.releaseURL.absoluteString.hasSuffix("v0.5.6") == true)
    }

    @Test func skipsDraftAndPrerelease() {
        #expect(ReleaseCheck.parseLatest(from: json(tag: "v0.5.6", draft: true)) == nil)
        #expect(ReleaseCheck.parseLatest(from: json(tag: "v0.5.6", prerelease: true)) == nil)
    }

    @Test func rejectsMalformedJSON() {
        #expect(ReleaseCheck.parseLatest(from: Data("{".utf8)) == nil)
    }

    @Test func actionableOnlyWhenNewer() throws {
        let latest = try release(SemanticVersion(major: 0, minor: 5, patch: 6))
        #expect(ReleaseCheck.actionableUpdate(
            currentVersion: "0.5.5",
            latest: latest,
            skipped: nil
        ) != nil)
        #expect(ReleaseCheck.actionableUpdate(
            currentVersion: "0.5.6",
            latest: latest,
            skipped: nil
        ) == nil)
        #expect(ReleaseCheck.actionableUpdate(
            currentVersion: "0.6.0",
            latest: latest,
            skipped: nil
        ) == nil)
    }

    @Test func respectsSkippedVersion() throws {
        let latest = try release(SemanticVersion(major: 0, minor: 5, patch: 6))
        // Skippata proprio la 0.5.6: non si propone.
        #expect(ReleaseCheck.actionableUpdate(
            currentVersion: "0.5.5",
            latest: latest,
            skipped: "0.5.6"
        ) == nil)
        // Skippata una vecchia: la 0.5.6 si propone comunque.
        #expect(ReleaseCheck.actionableUpdate(
            currentVersion: "0.5.5",
            latest: latest,
            skipped: "0.5.4"
        ) != nil)
    }

    @Test func unknownCurrentVersionIsNotActionable() throws {
        let latest = try release(SemanticVersion(major: 0, minor: 5, patch: 6))
        #expect(ReleaseCheck
            .actionableUpdate(currentVersion: "", latest: latest, skipped: nil) == nil)
    }
}
