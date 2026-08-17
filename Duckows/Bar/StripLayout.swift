import CoreGraphics

/// Decides how the window buttons fit into the space the bar has.
///
/// Buttons give up their titles before they give up their place: a bar full of
/// unlabelled icons is a Dock, and the point of this one is that you can read
/// which window is which. So the order of sacrifice is width first, then
/// titles, and only then does anything move into an overflow list.
///
/// Pure arithmetic so it can be tested without a screen.
struct StripLayout: Equatable {
    let buttonWidth: CGFloat
    /// How many buttons are drawn; the rest go behind the overflow button.
    let visibleCount: Int
    let showsTitles: Bool
    var hasOverflow: Bool { visibleCount < itemCount }

    let itemCount: Int

    /// Below this a title is a couple of characters and an ellipsis, which
    /// tells you less than the icon already did.
    static let minimumTitleWidth: CGFloat = 92
    static let spacing: CGFloat = 6
    static let dividerWidth: CGFloat = 9
    static let overflowButtonWidth: CGFloat = 26

    static func compute(
        available: CGFloat,
        itemCount: Int,
        dividerCount: Int,
        iconSize: CGFloat,
        maximumButtonWidth: CGFloat,
        prefersTitles: Bool
    ) -> StripLayout {
        let iconOnlyWidth = iconSize + 20
        guard itemCount > 0, available > 0 else {
            return StripLayout(buttonWidth: iconOnlyWidth, visibleCount: 0,
                               showsTitles: prefersTitles, itemCount: itemCount)
        }

        let fixed = CGFloat(dividerCount) * dividerWidth
            + CGFloat(max(0, itemCount - 1)) * spacing
        let usable = max(0, available - fixed)
        let perButton = usable / CGFloat(itemCount)

        if prefersTitles {
            // Roomy: every button at its full width.
            if perButton >= maximumButtonWidth {
                return StripLayout(buttonWidth: maximumButtonWidth, visibleCount: itemCount,
                                   showsTitles: true, itemCount: itemCount)
            }
            // Tight: shrink the titles rather than dropping anything.
            if perButton >= minimumTitleWidth {
                return StripLayout(buttonWidth: perButton, visibleCount: itemCount,
                                   showsTitles: true, itemCount: itemCount)
            }
        }

        // Titles are gone; see whether icons alone fit.
        if perButton >= iconOnlyWidth {
            return StripLayout(buttonWidth: iconOnlyWidth, visibleCount: itemCount,
                               showsTitles: false, itemCount: itemCount)
        }

        // They do not, so as many as will fit, and the rest behind a chevron.
        let forButtons = max(0, available - overflowButtonWidth - spacing - fixed)
        let fits = Int(forButtons / (iconOnlyWidth + spacing))
        return StripLayout(
            buttonWidth: iconOnlyWidth,
            visibleCount: max(1, min(itemCount, fits)),
            showsTitles: false,
            itemCount: itemCount
        )
    }
}
