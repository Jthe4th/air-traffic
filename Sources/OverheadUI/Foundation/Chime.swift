import Foundation
import OverheadKit
#if canImport(AVFoundation)
import AVFoundation
#endif

/// The two short sounds that go with a Space Station pass, made from plain sine tones so the app carries no audio files.
public enum ChimeTone {
    private static let rate = 44_100.0

    /// A complete WAV file (16-bit, mono) for the sound.
    public static func wav(for kind: StationChime.Kind) -> Data {
        // A heads-up is two soft bell notes; the start of the pass is a brighter rising arpeggio.
        let notes: [(hz: Double, at: Double, ring: Double)] = switch kind {
        case .headsUp: [(659.25, 0.0, 1.0), (987.77, 0.30, 1.2)]
        case .rising: [(1046.5, 0.0, 0.8), (1318.5, 0.14, 0.8), (1568.0, 0.28, 0.8), (2093.0, 0.42, 1.1)]
        }
        let length = Int((notes.map { $0.at + $0.ring }.max() ?? 1) * rate)
        var mix = [Double](repeating: 0, count: length)
        for note in notes {
            let start = Int(note.at * rate)
            for i in 0..<Int(note.ring * rate) where start + i < length {
                let t = Double(i) / rate
                let attack = min(1, t / 0.005)
                let decay = exp(-t * 4.2 / note.ring)
                let tone = sin(2 * .pi * note.hz * t) + 0.28 * sin(2 * .pi * note.hz * 2 * t) + 0.08 * sin(2 * .pi * note.hz * 3 * t)
                mix[start + i] += attack * decay * tone
            }
        }
        // A short fade at the very end, so the last note never stops with a click.
        let fade = Int(0.04 * rate)
        for i in 0..<min(fade, length) { mix[length - 1 - i] *= Double(i) / Double(fade) }
        let peak = max(mix.map(abs).max() ?? 1, 1e-6)
        var pcm = Data(capacity: length * 2)
        for sample in mix {
            let v = Int16((sample / peak * 0.6 * Double(Int16.max)).rounded())
            pcm.append(contentsOf: [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8)])
        }
        func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: v >> (8 * UInt32($0))) } }
        func le16(_ v: UInt16) -> [UInt8] { [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8)] }
        var wav = Data("RIFF".utf8)
        wav.append(contentsOf: le32(UInt32(36 + pcm.count)))
        wav.append(contentsOf: Data("WAVEfmt ".utf8))
        wav.append(contentsOf: le32(16) + le16(1) + le16(1) + le32(UInt32(rate)) + le32(UInt32(rate) * 2) + le16(2) + le16(16))
        wav.append(contentsOf: Data("data".utf8))
        wav.append(contentsOf: le32(UInt32(pcm.count)))
        wav.append(pcm)
        return wav
    }
}

#if canImport(AVFoundation)
@MainActor
enum Chime {
    private static var player: AVAudioPlayer?

    static func play(_ kind: StationChime.Kind) {
        #if os(tvOS) || os(iOS)
        // Mixes with whatever else the Apple TV is playing instead of interrupting it.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        player = try? AVAudioPlayer(data: ChimeTone.wav(for: kind))
        player?.volume = 0.8
        player?.play()
    }
}
#endif
