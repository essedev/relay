@testable import Core
import Testing

struct BrewUpgradeTests {
    private let expected = SemanticVersion(major: 0, minor: 25, patch: 0)

    @Test func bundleAtTheNewVersionIsInstalled() {
        #expect(BrewUpgrade.verify(onDisk: "0.25.0", expected: expected) == .installed)
    }

    /// Una versione ancora più nuova sul disco (release uscita durante l'upgrade) va bene uguale.
    @Test func newerBundleCountsAsInstalled() {
        #expect(BrewUpgrade.verify(onDisk: "0.26.1", expected: expected) == .installed)
    }

    /// brew è andato ma ha aggiornato un'altra copia: riavviare riaprirebbe la vecchia.
    @Test func oldBundleIsNotReplaced() {
        #expect(
            BrewUpgrade.verify(onDisk: "0.24.0", expected: expected)
                == .notReplaced(onDisk: "0.24.0")
        )
    }

    @Test func unreadableBundleIsNotReplaced() {
        #expect(BrewUpgrade.verify(onDisk: nil, expected: expected) == .notReplaced(onDisk: nil))
        #expect(
            BrewUpgrade.verify(onDisk: "garbage", expected: expected)
                == .notReplaced(onDisk: "garbage")
        )
    }

    @Test func caskNotInstalledPointsToTheInstallCommand() {
        let output = "==> Upgrading\nError: Cask 'relay-terminal' is not installed.\n"
        let message = BrewUpgrade.failureMessage(output: output)
        #expect(message.contains("brew install --cask essedev/relay/relay-terminal"))
    }

    @Test func otherFailuresKeepTheLastLines() {
        let output = "line 1\nline 2\n\n  Error: one\nError: two\nError: three  \n"
        #expect(BrewUpgrade
            .failureMessage(output: output) == "Error: one\nError: two\nError: three")
    }

    @Test func silentFailureStillSaysSomething() {
        #expect(BrewUpgrade.failureMessage(output: "\n \n") == "Homebrew stopped with an error.")
    }
}
