import AppKit

/// How the HUD relates to the Spaces macOS creates for full-screen apps.
///
/// macOS gives every full-screen app a Space of its own — the extra desktop
/// that appears beside the ordinary ones in the Space switcher and that the
/// user swipes between. Whether the HUD is allowed on those Spaces is expressed
/// with the window's collection behaviour, which leaves the decision with the
/// window server rather than with this app:
///
///   * on  → `.fullScreenAuxiliary`: the HUD joins full-screen Spaces too, so it
///     is on screen on every desktop the user can swipe to;
///   * off → `.fullScreenNone`: the HUD is kept out of them, and appears on the
///     ordinary desktop Spaces only.
///
/// Nothing here inspects other applications' windows or guesses what
/// "full-screen" means; the membership is macOS's own, and swapping it is the
/// whole of the "show in fullscreen" setting.
enum OverlaySpacePolicy {
    /// The HUD belongs to every Space on every display; only the full-screen
    /// part of its membership varies with the setting.
    static let sharedMembership: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .ignoresCycle]

    static func collectionBehavior(showInFullscreen: Bool) -> NSWindow.CollectionBehavior {
        sharedMembership.union(showInFullscreen ? .fullScreenAuxiliary : .fullScreenNone)
    }

    /// The window server's answer to "is the HUD on the Space the user is
    /// looking at right now?" — which is also the question the sleep decision
    /// asks, since a HUD the user cannot see has nothing to measure.
    ///
    /// `isOnActiveSpace` reports Space membership only. `occlusionState` is
    /// deliberately not used instead: it also goes false when an ordinary
    /// window merely covers the HUD, which has nothing to do with Spaces.
    @MainActor
    static func isDisplayed(_ window: NSWindow) -> Bool {
        window.isVisible && window.isOnActiveSpace
    }
}
