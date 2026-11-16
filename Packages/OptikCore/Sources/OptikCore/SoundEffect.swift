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

    /// Length in seconds, from the table. Speech waits for the effect to end, so the
    /// app needs this without opening the file. `MoodTests` checks it against the WAVs.
    public var duration: Double {
        switch self {
        case .tik: 0.07
        case .uyan: 0.38
        case .dinliyor: 0.18
        case .mutlu: 0.23
        case .dusunceli: 0.38
        case .uyari: 0.44
        case .tamam: 0.2
        case .kutlama: 0.47
        case .uykulu: 0.64
        }
    }
}
