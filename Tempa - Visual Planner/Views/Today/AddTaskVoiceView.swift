import SwiftUI
import Speech
import AVFoundation
import Observation

/// The recorder itself, with two homes.
///
/// `.cover` is the way it has always worked: presented full-screen from the
/// New task sheet, with a close button, and listening from the moment it
/// appears — the user got here by tapping "Speak it", so they are ready.
///
/// `.tab` is the AI screen. No chrome, and it does NOT open the microphone
/// on its own: arriving at a tab is not the same as asking to be recorded.
/// The mic starts on the first tap, and stops the moment the tab is left.
struct VoiceCaptureView<Footer: View>: View {
    enum Home { case tab, cover }

    var home: Home = .cover
    var onConfirm: (String) -> Void
    var onClose: () -> Void = {}
    @ViewBuilder var footer: () -> Footer

    @State private var transcribedText = ""
    @State private var isListening = false
    @State private var errorMessage: String?
    @State private var breatheScale: CGFloat = 1.0
    @State private var recognizer = SpeechRecognizer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(lightHex: "#FFE9E1", darkHex: "#2C1F18"), T.bg],
                startPoint: .top, endPoint: .center
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                if home == .cover {
                    topBar
                        .padding(.top, 8)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("I HEARD")
                        .font(.custom(T.fontHeader, size: 12).weight(.heavy))
                        .tracking(2)
                        .foregroundColor(T.textSec)
                        .padding(.bottom, 14)

                    Group {
                        if transcribedText.isEmpty && !isListening {
                            Text("Tap the mic to start…")
                                .foregroundColor(T.textTer)
                        } else if transcribedText.isEmpty && isListening {
                            Text("Listening…")
                                .foregroundColor(T.textTer)
                        } else {
                            Text(transcribedText)
                                .foregroundColor(T.text)
                            + Text(isListening ? " …" : "")
                                .foregroundColor(T.textTer)
                        }
                    }
                    .font(.custom(T.fontHeader, size: 28).weight(.bold))
                    .tracking(-0.5)
                    .lineSpacing(2)

                    if let error = errorMessage {
                        Text(error)
                            .font(.custom(T.fontBody, size: 13).weight(.medium))
                            .foregroundColor(T.danger)
                            .padding(.top, 12)
                    }

                    Spacer()

                    waveformView
                        .padding(.bottom, 24)

                    controlRow
                        .padding(.bottom, home == .cover ? 32 : 26)

                    Text(helperText)
                        .font(.custom(T.fontHeader, size: 14).weight(.semibold))
                        .foregroundColor(T.textSec)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, home == .cover ? 50 : 22)

                    footer()
                }
                .padding(.horizontal, 24)
                .padding(.top, home == .cover ? 40 : 24)
            }
        }
        .onAppear {
            recognizer.setLocale(AppLanguage.current.speechLocale)
            startBreathing()
            if home == .cover { startListening() }
        }
        .onDisappear {
            recognizer.stop()
        }
        // Leaving the app must free the microphone too — a tab keeps its
        // view alive, so onDisappear alone isn't enough here.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { recognizer.stop() }
        }
        .onChange(of: recognizer.transcript) {
            transcribedText = recognizer.transcript
        }
        .onChange(of: recognizer.isRecording) {
            isListening = recognizer.isRecording
        }
        .onChange(of: recognizer.error) {
            errorMessage = recognizer.error
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                recognizer.stop()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(T.text)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(T.surface.opacity(0.7))
                    )
            }

            Spacer()

        }
        .padding(.horizontal, 20)
    }

    // MARK: - Waveform

    private var waveformView: some View {
        let count = 29   // odd → there's a true centre bar
        return TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let level = isListening ? Double(recognizer.audioLevel) : 0
            HStack(spacing: 5) {
                ForEach(0..<count, id: \.self) { i in
                    // Bell envelope: ~0 at the edges, 1 in the centre.
                    let env = sin(Double.pi * Double(i) / Double(count - 1))
                    // Gentle travelling idle motion so it always feels alive, centred.
                    let idle = (sin(t * 4 + Double(i) * 0.5) + 1) / 2
                    let height = 6 + env * (10 + idle * 8 + level * 72)
                    Capsule()
                        .fill(T.primary.opacity(0.22 + env * 0.55))
                        .frame(width: 5, height: height)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: home == .cover ? 120 : 104)
        }
    }

    // MARK: - Controls

    private var controlRow: some View {
        Button {
            primaryAction()
        } label: {
            ZStack {
                Circle()
                    .stroke(T.primary, lineWidth: 1.5)
                    .frame(width: 124, height: 124)
                    .opacity(isListening ? 0.4 : 0.15)
                    .scaleEffect(isListening ? breatheScale * 1.1 : 1)

                Circle()
                    .fill(T.primary.opacity(isListening ? 0.18 : 0.08))
                    .frame(width: 108, height: 108)
                    .scaleEffect(isListening ? breatheScale : 1)

                Circle()
                    .fill(buttonFilled ? AnyShapeStyle(T.primaryFill) : AnyShapeStyle(T.surface))
                    .frame(width: 92, height: 92)

                Image(systemName: buttonIcon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(buttonFilled ? .white : T.primary)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(SpringPressStyle(scale: 0.92))
        .frame(maxWidth: .infinity)
    }

    /// Orange (active) while listening or once we have something to add; muted only when idle & empty.
    private var buttonFilled: Bool { isListening || !transcribedText.isEmpty }

    private var buttonIcon: String {
        if !transcribedText.isEmpty { return "checkmark" }
        return isListening ? "stop.fill" : "mic.fill"
    }

    private var helperText: String {
        if !transcribedText.isEmpty { return String(localized: "Tap ✓ — we'll sort it into your day", bundle: .appLanguage) }
        return isListening ? String(localized: "Say everything you need to do…", bundle: .appLanguage) : String(localized: "Tap the mic to speak", bundle: .appLanguage)
    }

    private func primaryAction() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        if !transcribedText.isEmpty {
            recognizer.stop()
            let text = transcribedText
            // The tab stays where it is, so it needs a clean sheet for the
            // next dump; the cover is about to go away either way.
            transcribedText = ""
            recognizer.reset()
            onConfirm(text)
        } else if isListening {
            recognizer.stop()          // nothing captured yet → just pause
        } else {
            startListening()
        }
    }

    private func startListening() {
        errorMessage = nil
        recognizer.start()
    }

    private func startBreathing() {
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            breatheScale = 1.08
        }
    }
}

extension VoiceCaptureView where Footer == EmptyView {
    init(home: Home = .cover, onConfirm: @escaping (String) -> Void, onClose: @escaping () -> Void = {}) {
        self.init(home: home, onConfirm: onConfirm, onClose: onClose) { EmptyView() }
    }
}

// MARK: - Speech Recognizer

@MainActor @Observable
final class SpeechRecognizer {
    var transcript = ""
    var isRecording = false
    var error: String?
    var audioLevel: Float = 0
    private(set) var localeIdentifier: String

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?

    init(localeIdentifier: String = AppLanguage.current.speechLocale) {
        self.localeIdentifier = localeIdentifier
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
    }

    /// Switch recognition language; restarts listening if it was active.
    func setLocale(_ identifier: String) {
        guard identifier != localeIdentifier else { return }
        let wasRecording = isRecording
        stop()
        localeIdentifier = identifier
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier))
        transcript = ""
        error = nil
        if wasRecording {
            start()
        }
    }

    func start() {
        guard !isRecording else { return }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard status == .authorized else {
                    self.error = String(localized: "Tempa needs speech recognition to hear your tasks — you can allow it in Settings.", bundle: .appLanguage)
                    return
                }
                // Microphone permission is separate from speech — ask explicitly
                // so the system prompt reliably appears before recording starts.
                AVAudioApplication.requestRecordPermission { [weak self] granted in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if granted {
                            self.beginRecording()
                        } else {
                            self.error = String(localized: "Tempa needs the microphone to hear you — you can allow it in Settings.", bundle: .appLanguage)
                        }
                    }
                }
            }
        }
    }

    /// Clears what was heard, so the next dump starts from silence. (The
    /// tab keeps this recognizer alive between dumps; a cover is thrown away.)
    func reset() {
        transcript = ""
        error = nil
    }

    func stop() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil
        isRecording = false
        audioLevel = 0
    }

    private func beginRecording() {
        recognitionTask?.cancel()
        recognitionTask = nil
        transcript = ""

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Could not configure audio session."
            return
        }

        let engine = AVAudioEngine()
        self.audioEngine = engine

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            self.error = "Could not create recognition request."
            return
        }
        request.shouldReportPartialResults = true

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            self.error = "Speech recognizer not available for your language."
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, taskError in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if let taskError {
                    let nsError = taskError as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 { return }
                    if nsError.code == 1110 { return }
                    self.error = taskError.localizedDescription
                    self.stop()
                }
            }
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            let channelData = buffer.floatChannelData?[0]
            let frames = buffer.frameLength
            if let data = channelData {
                var sum: Float = 0
                for i in 0..<Int(frames) { sum += abs(data[i]) }
                let avg = sum / Float(frames)
                let level = min(max(avg * 4, 0), 1)
                Task { @MainActor [weak self] in
                    self?.audioLevel = level
                }
            }
        }

        do {
            engine.prepare()
            try engine.start()
            isRecording = true
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
        } catch {
            self.error = "Audio engine failed to start."
            self.stop()
        }
    }
}

#Preview {
    VoiceCaptureView(home: .tab) { _ in }
}
