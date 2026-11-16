/// Recognizes a double tap of a modifier key on its own (default: ⌘ ⌘).
///
/// Fires on the second key down, so there is no wait after the user's gesture.
/// Any other key or modifier in between cancels it, which keeps chords like
/// ⌘C followed quickly by ⌘V from summoning Optik.
public struct DoubleTapDetector: Sendable {
    public enum Input: Equatable, Sendable {
        /// The watched modifier went down with no other modifier held.
        case down(at: Double)
        /// The watched modifier went up.
        case up(at: Double)
        /// Any other key or modifier.
        case other
    }

    /// The first tap must be released within this time to count as a tap.
    public var maxHold: Double
    /// The second press must start within this time after the first press.
    public var maxInterval: Double

    private enum State: Sendable {
        case idle
        case firstDown(at: Double)
        case firstUp(downAt: Double)
    }

    private var state: State = .idle

    public init(maxHold: Double = 0.3, maxInterval: Double = 0.4) {
        self.maxHold = maxHold
        self.maxInterval = maxInterval
    }

    /// Returns true when the input completes a double tap.
    public mutating func handle(_ input: Input) -> Bool {
        switch (state, input) {
        case (_, .other):
            state = .idle
        case (.idle, .down(let time)):
            state = .firstDown(at: time)
        case (.firstDown(let downAt), .up(let time)):
            state = time - downAt <= maxHold ? .firstUp(downAt: downAt) : .idle
        case (.firstUp(let downAt), .down(let time)):
            if time - downAt <= maxInterval {
                state = .idle
                return true
            }
            state = .firstDown(at: time)
        case (.firstDown, .down(let time)):
            // A missed key up: start over from this press.
            state = .firstDown(at: time)
        case (.idle, .up), (.firstUp, .up):
            state = .idle
        }
        return false
    }
}
