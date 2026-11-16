/// Optik's moods. Raw values match the CSS classes in `assets/animasyon/optik.css`
/// and the pose files `assets/karakter/svg/optik-<raw>.svg`.
public enum Mood: String, CaseIterable, Sendable, Hashable {
    /// bekliyor: default
    case waiting = "bekliyor"
    /// mutlu: the day is on track
    case happy = "mutlu"
    /// dinliyor: woken up, listening or talking
    case listening = "dinliyor"
    /// dusunceli: planning, work in progress
    case thoughtful = "dusunceli"
    /// uyari: something is due or late
    case alert = "uyari"
    /// kutlama: something got done
    case celebrating = "kutlama"
    /// uykulu: day closed, island idle
    case sleepy = "uykulu"

    /// The sound effect played when Optik switches to this mood.
    public var sound: SoundEffect {
        switch self {
        case .waiting: .tik
        case .happy: .mutlu
        case .listening: .dinliyor
        case .thoughtful: .dusunceli
        case .alert: .uyari
        case .celebrating: .kutlama
        case .sleepy: .uykulu
        }
    }

    /// Transient moods return to the screen's own mood after
    /// `DesignTokens.Motion.transientMoodMilliseconds`.
    public var isTransient: Bool {
        self == .celebrating
    }
}
