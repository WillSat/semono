import Testing
@testable import Semono

struct UpdateCheckerTests {
    @Test func semanticVersionsCompareNumerically() {
        #expect(SemanticVersion("v2.2.0")! < SemanticVersion("v2.2.1")!)
        #expect(SemanticVersion("2.10.0")! > SemanticVersion("2.9.9")!)
        #expect(!(SemanticVersion("v2.2.0")! < SemanticVersion("2.2.0")!))
        #expect(SemanticVersion("2.2.0-beta")! < SemanticVersion("2.2.1")!)
        #expect(SemanticVersion("") == nil)
    }

    @Test @MainActor func automaticUpdatesAreOnByDefault() {
        #expect(SettingsStore.Defaults.autoUpdateCheck)
    }
}
