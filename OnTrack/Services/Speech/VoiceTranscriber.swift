@preconcurrency import AVFoundation
import Foundation
import Observation
import Speech

/// Single-use handoff for an audio buffer into a `@Sendable`-typed callback that
/// actually runs synchronously on the calling thread.
private final class BufferBox: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}

/// On-device dictation via iOS 26's SpeechAnalyzer. Nothing leaves the phone,
/// there's no network round-trip before text appears, and it works in aeroplane
/// mode — which matters when the whole point is "speak it before you forget".
@MainActor
@Observable
final class VoiceTranscriber {
    enum State: Equatable {
        case idle
        case preparing
        case listening
        case finished
        case failed(String)
    }

    private(set) var state: State = .idle
    /// Text the recogniser has committed to.
    private(set) var finalText: String = ""
    /// The in-flight guess, shown lighter so you can see it thinking.
    private(set) var volatileText: String = ""
    /// Smoothed mic level, 0…1, for the waveform.
    private(set) var level: Float = 0

    var combinedText: String {
        let joined = (finalText + " " + volatileText).trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
    }

    var isRunning: Bool { state == .listening || state == .preparing }

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private let engine = AVAudioEngine()

    // MARK: - Control

    func start() async {
        guard !isRunning else { return }
        finalText = ""
        volatileText = ""
        state = .preparing

        guard await requestMicrophoneAccess() else {
            state = .failed("Microphone access is off. Turn it on in Settings → On Track.")
            return
        }

        do {
            try await beginSession()
            state = .listening
        } catch {
            await teardown()
            state = .failed(error.localizedDescription)
        }
    }

    /// Stops listening and returns everything heard.
    @discardableResult
    func stop() async -> String {
        guard isRunning else { return combinedText }
        let text = combinedText
        await teardown()
        finalText = text
        volatileText = ""
        state = .finished
        return text
    }

    func reset() {
        finalText = ""
        volatileText = ""
        level = 0
        state = .idle
    }

    // MARK: - Setup

    private func beginSession() async throws {
        let locale = await Self.bestLocale()
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        // The speech assets for this locale are downloaded on demand the first time.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    await MainActor.run {
                        guard let self else { return }
                        if result.isFinal {
                            self.finalText = (self.finalText + " " + text)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            self.volatileText = ""
                        } else {
                            self.volatileText = text
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    // A failure after we've already heard something isn't worth
                    // an error screen — keep the text.
                    if self.combinedText.isEmpty {
                        self.state = .failed(error.localizedDescription)
                    }
                }
            }
        }

        try await analyzer.start(inputSequence: stream)
        try startAudio()
    }

    private func startAudio() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let peak = Self.peakLevel(of: buffer)
            Task { @MainActor in
                // Attack fast, release slow — reads as a responsive meter rather
                // than a twitchy one.
                self.level = max(peak, self.level * 0.82)
            }
            self.submit(buffer: buffer)
        }

        engine.prepare()
        try engine.start()
    }

    /// SpeechAnalyzer wants a specific format; the mic gives us whatever it gives us.
    private func submit(buffer: AVAudioPCMBuffer) {
        guard let continuation = inputContinuation else { return }
        guard let target = analyzerFormat else {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }

        if buffer.format == target {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }

        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        guard let converter else { return }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 512)
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

        // The converter's input block is declared @Sendable but is called
        // synchronously on this thread. A box hands the buffer over exactly once
        // without capturing a mutable local.
        let pending = BufferBox(buffer)
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            guard let next = pending.take() else {
                status.pointee = .noDataNow
                return nil
            }
            status.pointee = .haveData
            return next
        }

        guard error == nil, output.frameLength > 0 else { return }
        continuation.yield(AnalyzerInput(buffer: output))
    }

    private func teardown() async {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }

        inputContinuation?.finish()
        inputContinuation = nil

        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        converter = nil
        level = 0

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Helpers

    private static func bestLocale() async -> Locale {
        let supported = await SpeechTranscriber.supportedLocales
        let current = Locale.current
        if supported.contains(where: { $0.identifier(.bcp47) == current.identifier(.bcp47) }) {
            return current
        }
        // Fall back to a locale that shares the language before giving up entirely.
        if let language = current.language.languageCode?.identifier,
           let match = supported.first(where: { $0.language.languageCode?.identifier == language }) {
            return match
        }
        return supported.first ?? Locale(identifier: "en-US")
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func peakLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<count {
            let sample = channel[i]
            sum += sample * sample
        }
        let rms = (sum / Float(count)).squareRoot()
        // Speech RMS sits well below 1.0; scale so normal talking fills the meter.
        return min(1, rms * 7)
    }
}
