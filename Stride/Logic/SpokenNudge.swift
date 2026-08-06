import Foundation
import AVFoundation

// Spoken nudges. Handoff §5.
//
// Plays once, on device, only when the user opened the app from the nudge AND
// `spokenNudgesEnabled` is on. No entitlement, no network call.
// Delivered flat — the voice does not sell anything.

final class SpokenNudge {
    static let shared = SpokenNudge()
    private let synth = AVSpeechSynthesizer()
    private var spokenThisLaunch: Set<String> = []

    private init() {}

    func speakOnce(_ note: AppNotification) {
        guard note.spoken else { return }
        let key = note.trigger.rawValue
        guard !spokenThisLaunch.contains(key) else { return }
        spokenThisLaunch.insert(key)

        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: note.copy)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
        utterance.pitchMultiplier = 0.96
        utterance.postUtteranceDelay = 0
        synth.speak(utterance)
    }
}
