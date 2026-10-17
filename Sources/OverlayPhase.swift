import Foundation

/// Phases of the top-center pill. `.idle` is the permanent resting state:
/// after app launch the pill is always on screen, and every phase returns
/// to `.idle` instead of dismissing the panel. The pill's appearance is
/// unchanged from upstream freeflow — only its lifetime changed.
enum OverlayPhase {
    /// Permanent idle pill: minimal black pill with a mic glyph. Ignores
    /// mouse events, never steals focus.
    case idle
    case initializing
    case recording
    case transcribing
    case feedback
    case updateAvailable
    /// Dictation finished but no text field had focus, so nothing was
    /// pasted. The pill offers "Text not pasted. Click here to copy text."
    case pasteFailed

    /// Phases that ALWAYS render the drop-down pill (never the winged notch
    /// layout), regardless of display or compact setting. The other phases
    /// may use the winged layout on notched displays in compact mode.
    var alwaysUsesDropDownPill: Bool {
        switch self {
        case .updateAvailable, .pasteFailed, .idle:
            return true
        case .initializing, .recording, .transcribing, .feedback:
            return false
        }
    }
}
