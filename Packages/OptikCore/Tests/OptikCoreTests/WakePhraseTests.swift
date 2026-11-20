import OptikCore
import Testing

struct WakePhraseTests {
    @Test(arguments: ["Optik", "Optik?", "optik, yarın 3'te Yeliz", "Optic.", "Obtik!", "Op tik", "OPTİK", "Optiğim", "-Uptake -Badır"])
    func hearsTheName(_ transcript: String) {
        #expect(WakePhrase.startsWithName(transcript))
    }

    @Test(arguments: ["", "Politik bir konu", "Kritik", "Pratik", "Bu optik bir yanılsama", "Op", "Altyazı M.K."])
    func ignoresOtherSpeech(_ transcript: String) {
        #expect(!WakePhrase.startsWithName(transcript))
    }

    @Test(arguments: [
        ("Optik, bugün hava nasıl?", "bugün hava nasıl?"),
        ("Optik bugün hava nasıl", "bugün hava nasıl"),
        ("Optik?", ""),
        ("Op tik yarın 3'te Yeliz", "yarın 3'te Yeliz"),
        ("-Uptake -Badır", "Badır"),
    ])
    func keepsWhatFollowsTheName(_ transcript: String, _ rest: String) {
        #expect(WakePhrase.remainder(transcript) == rest)
    }

    @Test func noNameNoRemainder() {
        #expect(WakePhrase.remainder("Politik bir konu") == nil)
    }
}
