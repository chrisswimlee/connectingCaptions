import AppKit

/// Overlay is text on slides. Pop-up is a boxed board.
/// Idle Overlay hides the in-flow shelf and clicks through, except a top
/// strip. A Tools bar stays in that strip, fades, and returns under the pointer.
/// Pinned Overlay shows the shelf. Placement stays interactive until the rectangle is kept.
enum TheaterOverlayPolicy {
    static let overlayMinSize = NSSize(width: 480, height: 140)
    static let popupMinSize = NSSize(width: 640, height: 260)
    /// Top of an idle Overlay window that wakes the tool bar before it has faded in.
    static let hoverDockWakeHeight: CGFloat = 44
    /// On-screen review. Older lines stay in History. Pop-up still shows the board.
    static let reviewLineCount = 3
    static let plateHorizontalInset: CGFloat = 10
    static let plateVerticalInset: CGFloat = 3
    static let plateCornerRadius: CGFloat = 8
    static let plateFillAlpha: CGFloat = 0.58

    static func isOverlay(_ presentation: TheaterPresentationStyle) -> Bool {
        presentation == .transparent
    }

    static func hidesAllChrome(
        presentation: TheaterPresentationStyle,
        toolsPinned: Bool,
        placing: Bool = false
    ) -> Bool {
        if placing { return false }
        return Self.isOverlay(presentation) && !toolsPinned
    }

    /// The tool bar is up while the pointer is on it, or a menu from it is open.
    static func showsHoverDock(engaged: Bool, holding: Bool) -> Bool {
        engaged || holding
    }

    /// Screen rect of the Overlay tool bar. A zero content height is the resting
    /// wake strip, so a faded bar does not eat clicks on the captions under it.
    static func hoverDockRect(windowFrame: CGRect, contentHeight: CGFloat) -> CGRect {
        let height = min(windowFrame.height, max(contentHeight, Self.hoverDockWakeHeight))
        return CGRect(
            x: windowFrame.minX,
            y: windowFrame.maxY - height,
            width: windowFrame.width,
            height: height
        )
    }

    static func hoverDockContains(
        _ point: CGPoint,
        windowFrame: CGRect,
        contentHeight: CGFloat
    ) -> Bool {
        Self.hoverDockRect(windowFrame: windowFrame, contentHeight: contentHeight).contains(point)
    }

    static func usesCaptionsOnlyChrome(
        presentation: TheaterPresentationStyle,
        hideChrome: Bool
    ) -> Bool {
        presentation == .popup && hideChrome
    }

    /// Resting layout. Pop-up keeps the shelf. Captions only and idle Overlay
    /// give that room to the text until tools are actually showing. A visible
    /// shelf, including hover tools, still insets the board so a line cannot
    /// draw under the buttons.
    static func reservesToolBarSlot(
        presentation: TheaterPresentationStyle,
        hideChrome: Bool,
        toolsPinned: Bool = false,
        placing: Bool = false
    ) -> Bool {
        if placing { return true }
        if presentation == .transparent {
            return toolsPinned
        }
        return !hideChrome
    }

    static func ignoresMouseEvents(
        presentation: TheaterPresentationStyle,
        toolsPinned: Bool,
        minimized: Bool,
        placing: Bool = false,
        pointerInHoverDock: Bool = false
    ) -> Bool {
        if placing || minimized { return false }
        if Self.hidesAllChrome(presentation: presentation, toolsPinned: toolsPinned) {
            return !pointerInHoverDock
        }
        return false
    }

    /// Pop-up keeps a window shadow. Overlay is text on the slide, so it does not.
    static func showsWindowShadow(presentation: TheaterPresentationStyle) -> Bool {
        !Self.isOverlay(presentation)
    }

    static func hidesTitlebarButtons(
        presentation: TheaterPresentationStyle,
        toolsPinned: Bool,
        hideChrome: Bool = false,
        placing: Bool = false
    ) -> Bool {
        if placing { return false }
        if Self.hidesAllChrome(presentation: presentation, toolsPinned: toolsPinned) {
            return true
        }
        return Self.usesCaptionsOnlyChrome(presentation: presentation, hideChrome: hideChrome)
    }

    static func movableByBackground(
        presentation: TheaterPresentationStyle,
        toolsPinned: Bool,
        minimized: Bool,
        placing: Bool = false
    ) -> Bool {
        if minimized { return false }
        if placing || presentation == .popup { return true }
        return toolsPinned
    }

    static func minSize(for presentation: TheaterPresentationStyle) -> NSSize {
        Self.isOverlay(presentation) ? Self.overlayMinSize : Self.popupMinSize
    }

    static func shouldClearPin(
        presentation: TheaterPresentationStyle,
        minimized: Bool,
        windowEnabled: Bool
    ) -> Bool {
        presentation == .popup || minimized || !windowEnabled
    }

    static func showsCaptionPlate(
        presentation: TheaterPresentationStyle,
        backingBar: Bool
    ) -> Bool {
        Self.isOverlay(presentation) && backingBar
    }

    static func plateColor() -> NSColor {
        NSColor.black.withAlphaComponent(Self.plateFillAlpha)
    }

    /// Overlay stays over slides. Pop-up only floats when another app is
    /// front, so Home and Settings can sit on top of the boxed board.
    static func windowLevel(
        presentation: TheaterPresentationStyle,
        appIsActive: Bool
    ) -> NSWindow.Level {
        if presentation == .transparent { return .floating }
        return appIsActive ? .normal : .floating
    }

    static func isFloatingPanel(
        presentation: TheaterPresentationStyle,
        appIsActive: Bool
    ) -> Bool {
        Self.windowLevel(presentation: presentation, appIsActive: appIsActive) == .floating
    }
}
