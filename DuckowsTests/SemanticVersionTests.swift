import XCTest

/// `SemanticVersion` decides whether an update is offered at all, so a bug here
/// either strands users on an old build or offers them a downgrade.
final class SemanticVersionTests: XCTestCase {
    func testParsesPlainVersion() {
        XCTAssertEqual(SemanticVersion("1.2.3")?.description, "1.2.3")
    }

    func testStripsLeadingV() {
        XCTAssertEqual(SemanticVersion("v0.1.0")?.description, "0.1.0")
        XCTAssertEqual(SemanticVersion("V2.0.0")?.description, "2.0.0")
    }

    func testDropsPreReleaseAndBuildMetadata() {
        XCTAssertEqual(SemanticVersion("1.2.3-beta.1")?.description, "1.2.3")
        XCTAssertEqual(SemanticVersion("1.2.3+build7")?.description, "1.2.3")
    }

    func testRejectsGarbage() {
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("nightly"))
        XCTAssertNil(SemanticVersion("1.x.3"))
    }

    func testOrdersByComponent() {
        XCTAssertLessThan(SemanticVersion("1.0.0")!, SemanticVersion("1.0.1")!)
        XCTAssertLessThan(SemanticVersion("1.9.0")!, SemanticVersion("1.10.0")!)
        XCTAssertLessThan(SemanticVersion("1.2.3")!, SemanticVersion("2.0.0")!)
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertEqual(SemanticVersion("1.2")!, SemanticVersion("1.2.0")!)
        XCTAssertLessThan(SemanticVersion("1.2")!, SemanticVersion("1.2.1")!)
    }

    /// Dev builds are pinned to 0.0.0 so every published release looks newer.
    func testDevBuildIsOlderThanAnyRelease() {
        XCTAssertLessThan(SemanticVersion("0.0.0")!, SemanticVersion("0.1.0")!)
    }

    func testEqualVersionDoesNotTriggerAnUpdate() {
        XCTAssertFalse(SemanticVersion("1.0.12")! > SemanticVersion("v1.0.12")!)
    }
}
