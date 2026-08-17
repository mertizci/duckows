import XCTest

/// The layout decides what the bar gives up when it runs out of room, and the
/// order matters: width, then titles, then buttons.
final class StripLayoutTests: XCTestCase {
    private func layout(
        available: CGFloat,
        items: Int,
        dividers: Int = 0,
        prefersTitles: Bool = true
    ) -> StripLayout {
        StripLayout.compute(
            available: available,
            itemCount: items,
            dividerCount: dividers,
            iconSize: 24,
            maximumButtonWidth: 180,
            prefersTitles: prefersTitles
        )
    }

    func testRoomyBarUsesTheFullButtonWidth() {
        let result = layout(available: 2000, items: 5)
        XCTAssertEqual(result.buttonWidth, 180)
        XCTAssertEqual(result.visibleCount, 5)
        XCTAssertTrue(result.showsTitles)
        XCTAssertFalse(result.hasOverflow)
    }

    func testTightBarShrinksTitlesBeforeDroppingAnything() {
        let result = layout(available: 700, items: 5)
        XCTAssertLessThan(result.buttonWidth, 180)
        XCTAssertGreaterThanOrEqual(result.buttonWidth, StripLayout.minimumTitleWidth)
        XCTAssertEqual(result.visibleCount, 5, "nothing should move to overflow while titles still fit")
        XCTAssertTrue(result.showsTitles)
    }

    /// A title squeezed to two characters and an ellipsis says less than the
    /// icon already did, so titles go before buttons do.
    func testTitlesAreDroppedBeforeButtons() {
        let result = layout(available: 420, items: 8)
        XCTAssertFalse(result.showsTitles)
        XCTAssertEqual(result.visibleCount, 8)
        XCTAssertFalse(result.hasOverflow)
    }

    func testOverflowOnlyOnceIconsNoLongerFit() {
        let result = layout(available: 200, items: 20)
        XCTAssertFalse(result.showsTitles)
        XCTAssertTrue(result.hasOverflow)
        XCTAssertLessThan(result.visibleCount, 20)
        XCTAssertGreaterThan(result.visibleCount, 0, "at least one button always stays")
    }

    func testOverflowLeavesRoomForItsOwnButton() {
        let available: CGFloat = 200
        let result = layout(available: available, items: 20)
        let used = CGFloat(result.visibleCount) * result.buttonWidth
            + CGFloat(max(0, result.visibleCount - 1)) * StripLayout.spacing
        XCTAssertLessThanOrEqual(used + StripLayout.overflowButtonWidth, available)
    }

    func testDividersTakeSpaceFromTheButtons() {
        let without = layout(available: 700, items: 5, dividers: 0)
        let with = layout(available: 700, items: 5, dividers: 3)
        XCTAssertLessThan(with.buttonWidth, without.buttonWidth)
    }

    func testIconOnlyPreferenceSkipsTitlesEntirely() {
        let result = layout(available: 2000, items: 5, prefersTitles: false)
        XCTAssertFalse(result.showsTitles)
        XCTAssertEqual(result.buttonWidth, 44, "icon size plus padding")
    }

    func testEmptyBarIsHandled() {
        let result = layout(available: 800, items: 0)
        XCTAssertEqual(result.visibleCount, 0)
        XCTAssertFalse(result.hasOverflow)
    }
}
