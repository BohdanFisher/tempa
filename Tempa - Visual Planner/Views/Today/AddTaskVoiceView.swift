import SwiftUI
import Speech
import AVFoundation
import Observation

// MARK: - Supported voice languages

struct VoiceLanguage: Identifiable, Hashable {
    let id: String      // BCP-47 locale identifier for SFSpeechRecognizer
    let name: String    // native display name
    let flag: String

    static let all: [VoiceLanguage] = [
        VoiceLanguage(id: "en-US", name: "English",    flag: "🇬🇧"),
        VoiceLanguage(id: "de-DE", name: "Deutsch",    flag: "🇩🇪"),
        VoiceLanguage(id: "uk-UA", name: "Українська", flag: "🇺🇦"),
        VoiceLanguage(id: "es-ES", name: "Español",    flag: "🇪🇸"),
        VoiceLanguage(id: "fr-FR", name: "Français",   flag: "🇫🇷"),
        VoiceLanguage(id: "pt-PT", name: "Português",  flag: "🇵🇹"),
        VoiceLanguage(id: "fi-FI", name: "Suomi",      flag: "🇫🇮"),
        VoiceLanguage(id: "nb-NO", name: "Norsk",      flag: "🇳🇴"),
        VoiceLanguage(id: "nl-NL", name: "Nederlands", flag: "🇳🇱"),
    ]

    static func named(_ id: String) -> VoiceLanguage {
        all.first { $0.id == id } ?? all[0]
    }

    /// Device language if it's one we support, otherwise English.
    static var defaultIdentifier: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return all.first { $0.id.hasPrefix(code + "-") }?.id ?? "en-US"
    }
}

struct AddTaskVoiceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var transcribedText = ""
    @State private var isListening = false
    @State private var errorMessage: String?
    @State private var breatheScale: CGFloat = 1.0
    @AppStorage("voiceLocaleIdentifier") private var voiceLocale = VoiceLanguage.defaultIdentifier
    @State private var recognizer = SpeechRecognizer()
    var onConfirm: (String) -> Void = { _ in }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(lightHex: "#FFE9E1", darkHex: "#2C1F18"), T.bg],
                startPoint: .top, endPoint: .center
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 8)

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
                        .padding(.bottom, 32)

                    Text(helperText)
                        .font(.custom(T.fontHeader, size: 14).weight(.semibold))
                        .foregroundColor(T.textSec)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 50)
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
            }
        }
        .onAppear {
            recognizer.setLocale(voiceLocale)
            startBreathing()
            startListening()
        }
        .onDisappear {
            recognizer.stop()
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
                dismiss()
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

            Menu {
                ForEach(VoiceLanguage.all) { lang in
                    Button {
                        voiceLocale = lang.id
                        recognizer.setLocale(lang.id)
                    } label: {
                        if lang.id == voiceLocale {
                            Label("\(lang.flag)  \(lang.name)", systemImage: "checkmark")
                        } else {
                            Text("\(lang.flag)  \(lang.name)")
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(VoiceLanguage.named(voiceLocale).flag)
                        .font(.system(size: 18))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(T.textSec)
                }
                .frame(height: 38)
                .padding(.horizontal, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(T.surface.opacity(0.7))
                )
            }
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
            .frame(height: 120)
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
                    .fill(buttonFilled ? T.primary : T.surface)
                    .frame(width: 92, height: 92)
                    .shadow(color: Color(hex: "#FF7A59").opacity(buttonFilled ? 0.4 : 0), radius: 15, x: 0, y: 12)

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
        if !transcribedText.isEmpty { return String(localized: "Tap ✓ — we'll sort it into your day") }
        return isListening ? String(localized: "Say everything you need to do…") : String(localized: "Tap the mic to speak")
    }

    private func primaryAction() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        if !transcribedText.isEmpty {
            recognizer.stop()
            onConfirm(transcribedText)
            dismiss()
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

    init(localeIdentifier: String = VoiceLanguage.defaultIdentifier) {
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
                switch status {
                case .authorized:
                    self.beginRecording()
                case .denied:
                    self.error = "Speech recognition denied. Enable in Settings → Privacy."
                case .restricted:
                    self.error = "Speech recognition is restricted on this device."
                case .notDetermined:
                    self.error = "Speech recognition permission not determined."
                @unknown default:
                    self.error = "Unknown speech recognition status."
                }
            }
        }
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
    AddTaskVoiceView()
}
