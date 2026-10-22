import Foundation
import XCTest
@testable import LimitbarCore

final class ProviderCatalogTests: XCTestCase {
    func testCatalogCoversEverySupportedProviderExactlyOnce() {
        XCTAssertEqual(Set(ProviderCatalog.providers.map(\.id)), Set(ProviderID.allCases))
        XCTAssertEqual(ProviderCatalog.providers.count, ProviderID.allCases.count)
        for provider in ProviderCatalog.providers {
            XCTAssertEqual(provider.website.scheme, "https")
            XCTAssertFalse(provider.instructions.isEmpty)
        }
    }

    func testManualCredentialsAreLimitedToTokenAndKeyProviders() {
        XCTAssertEqual(ProviderCatalog.providers.filter(\.requiresCredential).map(\.id), [.copilot, .zai, .synthetic])
    }

    func testExistingEnabledConnectionsMigrateWithoutEnablingNewServices() {
        XCTAssertEqual(ProviderCatalog.restoredProviders(saved: nil, previouslyEnabled: [.codex, .antigravity]), [.codex, .antigravity])
        XCTAssertTrue(ProviderCatalog.restoredProviders(saved: nil, previouslyEnabled: []).isEmpty)
    }

    func testRemovedProvidersStayRemovedAndUnknownSavedIDsAreIgnored() {
        XCTAssertTrue(ProviderCatalog.restoredProviders(saved: [], previouslyEnabled: [.codex]).isEmpty)
        XCTAssertEqual(ProviderCatalog.restoredProviders(saved: ["claude", "unknown", "claude", "copilot"],
            previouslyEnabled: [.codex]), [.claude, .copilot])
    }
}
