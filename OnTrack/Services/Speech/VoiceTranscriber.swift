import AVFoundation
import Foundation
import Observation
import Speech

/// Everything the real-time audio thread touches.
///
/// Deliberately *not* main-actor isolated. `AVAudioEngine` invokes its tap block
/// on a real-time audio thread, so anything it reaches must be safe to call from
/// there — under Swift 6 a main-actor hop from that thread traps outright, and
/// even where it's legal it has no business blocking audio.
private final class AudioPipeline: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var targetFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    func begin(continuation: AsyncStream<AnalyzerInput>.Continuation, targetFormat: AVAudioFormat?) {
        lock.lock()
        defer { lock.unlock() }
        self.continuation = continuation
        self.targetFormat = targetFormat
        self.converter = nil
    }

    func finish() {
        lock.lock()
        let existing = continuation
        continuation = nil
        targetFormat = nil
        converter = nil
        lock.unlock()
        existing?.finish()
    }

    /// Called on the audio thread, once per buffer.
    func submit(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard let continuation else { return }
        guard let targetFormat else {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }
        if buffer.format == targetFormat {
            continuation.yield(AnalyzerInput(buffer: buffer))
            return
        }

        // SpeechAnalyzer wants a specific format; the mic gives us whatever the
        // hardware is running at.
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
        }
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 512)
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        // The converter's input block is typed @Sendable but runs synchronously
        // on this thread; the box hands the buffer over exactly once.
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
}

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

enum VoiceError: LocalizedError {
    case microphoneDenied
    case noAudioInput

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone access is off. Turn it on in Settings → On Track."
        case .noAudioInput:
            return "No microphone input available."
        }
    }
}

/// On-device dictation via iOS 26's SpeechAnalyzer. Nothing leaves the phone,
/// there's no network round-trip before text appears, and it works in aeroplane
/// mode — which matters when the whole point is "speak it before you forget".
///
/// Only observable UI state lives on the main actor. The capture pipeline is
/// held in `AudioPipeline`, which the audio thread owns.
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
    private var resultsTask: Task<Void, Never>?
    private var isTapInstalled = false
    private let pipeline = AudioPipeline()
    private let engine = AVAudioEngine()

    // MARK: - Control

    func start() async {
        guard !isRunning else { return }
        finalText = ""
        volatileText = ""
        state = .preparing

        guard await Self.requestMicrophoneAccess() else {
            state = .failed(VoiceError.microphoneDenied.localizedDescription)
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

        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        pipeline.begin(continuation: continuation, targetFormat: analyzerFormat)

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let isFinal = result.isFinal
                    await MainActor.run {
                        self?.apply(text: text, isFinal: isFinal)
                    }
                }
            } catch {
                await MainActor.run {
                    self?.handleResultsFailure(error)
                }
            }
        }

        try await analyzer.start(inputSequence: stream)
        try startAudio()
    }

    private func apply(text: String, isFinal: Bool) {
        if isFinal {
            finalText = (finalText + " " + text).trimmingCharacters(in: .whitespacesAndNewlines)
            volatileText = ""
        } else {
            volatileText = text
        }
    }

    private func handleResultsFailure(_ error: Error) {
        // A failure after we've already heard something isn't worth an error
        // screen — keep the text.
        if combinedText.isEmpty {
            state = .failed(error.localizedDescription)
        }
    }

    private func startAudio() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        // Installing a tap with a zero-rate or zero-channel format is a hard
        // crash inside AVAudioEngine rather than a thrown error.
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw VoiceError.noAudioInput
        }

        // Captured directly so the tap block never touches `self` synchronously.
        let pipeline = self.pipeline

        // `@Sendable` is load-bearing, not decoration. AVAudioNodeTapBlock is not
        // declared Sendable, so a closure written inside this @MainActor method
        // inherits main-actor isolation — and Swift 6 then checks that isolation
        // on entry. The audio thread fails that check and traps before a single
        // statement in the body runs. Marking it @Sendable opts the closure out.
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { @Sendable [weak self] buffer, _ in
            let peak = Self.peakLevel(of: buffer)
            pipeline.submit(buffer)

            // The only main-actor work is the meter, and it hops asynchronously
            // rather than blocking the audio thread. ~12 buffers a second.
            Task { @MainActor in
                guard let self else { return }
                // Attack fast, release slow — reads as a responsive meter rather
                // than a twitchy one.
                self.level = max(peak, self.level * 0.82)
            }
        }
        isTapInstalled = true

        engine.prepare()
        try engine.start()
    }

    private func teardown() async {
        if isTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        if engine.isRunning { engine.stop() }

        pipeline.finish()

        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
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

    private nonisolated static func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { @Sendable granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Runs on the audio thread — must not touch actor-isolated state.
    nonisolated static func peakLevel(of buffer: AVAudioPCMBuffer) -> Float {
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
