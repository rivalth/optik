/// Sound effects in `assets/sesler/<raw>.wav` (44.1 kHz, 16 bit, mono).
/// Table: `docs/03-karakter.md` section 7.
public enum SoundEffect: String, CaseIterable, Sendable, Hashable {
    /// Tap on the shell: tab, selection, undo.
    case tik
    /// Wake word detected, right before "Efendim?".
    case uyan
    /// Touch, switching to listening.
    case dinliyor
    /// Sound on, positive answer.
    case mutlu
    /// Work is taking a while.
    case dusunceli
    /// Reminder, limit exceeded.
    case uyari
    /// Record saved.
    case tamam
    /// Work done, payment received.
    case kutlama
    /// Day closed.
    case uykulu

    public var fileName: String { "\(rawValue).wav" }
}
