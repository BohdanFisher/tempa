import SwiftUI
import CoreData
import Combine
import AVFoundation
import AudioToolbox

// MARK: - Sand Particle

private struct SandParticle: Identifiable {
    let id: UInt32
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var life: CGFloat
    var maxLife: CGFloat
    var size: CGFloat
}

// MARK: - Focus View

struct FocusView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter.shared

    // Timer state
    @State private var selectedMinutes: Int = 15
    @State private var isActive = false
    @State private var sessionCategory: String?   // set when started from a task
    @State private var lastFocusReqID: UUID?
    @State private var pendingFocusRequest: FocusRequest?
    @State private var showSwitchConfirm = false
    @State private var lastHeartbeat = Date()
    @State private var pauseTick = Date()      // 1s render nudge while paused — keeps the end-time line live
    @State private var touchActive = false     // finger on the ring, whether or not the knob captured it
    @State private var sessionStart: Date?
    @State private var elapsed: TimeInterval = 0
    @State private var isPaused = false
    @State private var pauseAccum: TimeInterval = 0
    @State private var pauseStart: Date?

    // Drag-to-complete
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var dragAnchor: Double? = nil      // last fraction this drag — gives the dial end-stops
    @State private var lastActiveStep: Int = -1       // last haptic step on the finish dial
    @State private var lastRawFraction: Double = 0    // finish dial: previous raw angle, for delta tracking
    @State private var dragCompleted = false          // swallow the rest of a drag that just finished a session
    @State private var lastLeft: Date?                // when the app left the foreground; ticks freeze while set
    @State private var showFinishCheck = false        // checkmark pop in the dial centre on completion
    #if os(iOS)
    @State private var dialHaptic = UIImpactFeedbackGenerator(style: .rigid)
    #endif

    // Particles
    @State private var particles: [SandParticle] = []
    @State private var particleID: UInt32 = 0

    // Audio
    @State private var completionPlayer: AVAudioPlayer?

    // Timers
    private let clock = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    private let particleClock = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    // Design-spec constants
    private let SIZE: CGFloat = 340
    private let rRing: CGFloat = 122
    private let ringW: CGFloat = 42
    private let rNumber: CGFloat = 165
    // Screen background — adaptive: cream in light mode, warm charcoal in dark.
    private let darkBg = Color(lightHex: "#FBF8F3", darkHex: "#1A1512")
    // Base dial track — light warm-grey on light, deep brown on dark.
    private let trackColor = Color(lightHex: "#ECE5D9", darkHex: "#2A1D18")
    // Soft backdrop behind the hourglass — matches each render's own background.
    private let imageBackdrop = Color(lightHex: "#FBF8F3", darkHex: "#040304")

    private var center: CGPoint { CGPoint(x: SIZE / 2, y: SIZE / 2) }
    private var totalSec: TimeInterval { TimeInterval(selectedMinutes) * 60 }
    private var remain: TimeInterval { max(0, totalSec - elapsed) }

    private var activeProgress: Double {
        guard totalSec > 0 else { return 0 }
        return min(elapsed / totalSec, 1)
    }

    // What fraction of the ring is filled
    private var arcFraction: Double {
        if isActive {
            return isDragging ? dragProgress : activeProgress
        }
        return Double(selectedMinutes) / 60.0
    }

    private var countdown: String {
        let t = Int(remain)
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    /// "{Category} Time" when a session was started from a task, otherwise "Focus".
    private var focusTitle: String {
        if isActive, let cat = sessionCategory {
            return String(localized: "\(catDisplayName(cat)) Time", bundle: .appLanguage)
        }
        return String(localized: "Focus", bundle: .appLanguage)
    }

    private var timeRange: String {
        guard let s = sessionStart else { return "" }
        // Pauses push the finish out — show the real projected end.
        let pausedSoFar = pauseAccum + (isPaused ? Date().timeIntervalSince(pauseStart ?? Date()) : 0)
        let end = s.addingTimeInterval(totalSec + pausedSoFar)
        // Locale-aware: 24h in Europe, AM/PM in the US/Canada, and it honours
        // the user's own 24-Hour Time toggle.
        return "\(s.formatted(date: .omitted, time: .shortened)) → \(end.formatted(date: .omitted, time: .shortened))"
    }

    private func knobAngle(for frac: Double) -> Double {
        -.pi / 2 + frac * .pi * 2
    }

    private func knobPoint(for frac: Double) -> CGPoint {
        let a = knobAngle(for: frac)
        return CGPoint(
            x: SIZE / 2 + rRing * cos(a),
            y: SIZE / 2 + rRing * sin(a)
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            darkBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Title
                VStack(spacing: 4) {
                    Text(focusTitle)
                        .font(.custom("Charter", size: 52).weight(.regular))
                        .tracking(-1)
                        .foregroundColor(T.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    if isActive {
                        Text(timeRange)
                            .font(.custom(T.fontHeader, size: 14).weight(.semibold))
                            .foregroundColor(T.text.opacity(0.45))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.top, 36)
                .animation(.easeInOut(duration: 0.35), value: isActive)

                Spacer()

                // Ring + particles
                ZStack {
                    ringView

                    // Particles
                    Canvas { ctx, _ in
                        for p in particles {
                            let alpha = Double(p.life / p.maxLife) * 0.7
                            let s = Double(p.size * (p.life / p.maxLife))
                            let rect = CGRect(x: Double(p.x) - s / 2, y: Double(p.y) - s / 2, width: s, height: s)
                            ctx.opacity = alpha
                            ctx.fill(Path(ellipseIn: rect), with: .color(Color(hex: "#D4A574")))
                        }
                    }
                    .frame(width: SIZE, height: SIZE)
                    .allowsHitTesting(false)
                }

                if isActive {
                    activeControls
                } else {
                    startButton
                        .padding(.top, 28)
                }

                Spacer()
                Spacer().frame(height: 20)
            }
        }
        .onReceive(clock) { _ in tickClock() }
        .onReceive(particleClock) { _ in tickParticles() }
        .onChange(of: router.focusRequest) { _, req in
            guard let req, req.id != lastFocusReqID else { return }
            lastFocusReqID = req.id
            if isActive {
                // A session is running — never throw it away without asking.
                pendingFocusRequest = req
                showSwitchConfirm = true
            } else {
                apply(req)
            }
        }
        .confirmationDialog("A focus session is already running", isPresented: $showSwitchConfirm, titleVisibility: .visible) {
            Button(String(localized: "Switch to the new task", bundle: .appLanguage)) {
                if let req = pendingFocusRequest { apply(req) }
                pendingFocusRequest = nil
            }
            Button(String(localized: "Keep my session", bundle: .appLanguage), role: .cancel) {
                pendingFocusRequest = nil
            }
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
        .onAppear {
            restoreSessionIfNeeded()
            // The switch dialog may have been requested while this tab was
            // off-screen and dropped — raise it again now that we're visible.
            if pendingFocusRequest != nil { showSwitchConfirm = true }
        }
    }

    // MARK: - Ring View (Canvas-based, matching design spec)

    private var ringView: some View {
        ZStack {
            // Canvas for ring + ticks + knob arrow
            Canvas { context, canvasSize in
                let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

                // Base track ring
                var basePath = Path()
                basePath.addArc(center: c, radius: rRing, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
                context.stroke(basePath, with: .color(trackColor), style: StrokeStyle(lineWidth: ringW))

                // Active arc
                let frac = arcFraction
                if frac > 0 {
                    let startA = Angle.degrees(-90)
                    let endA = Angle.degrees(-90 + frac * 360)
                    var arcPath = Path()
                    arcPath.addArc(center: c, radius: rRing, startAngle: startA, endAngle: endA, clockwise: false)
                    context.stroke(
                        arcPath,
                        with: .linearGradient(
                            Gradient(colors: [Color(hex: "#FFB69A"), Color(hex: "#FF7A59")]),
                            startPoint: CGPoint(x: 0, y: c.y),
                            endPoint: CGPoint(x: canvasSize.width, y: c.y)
                        ),
                        style: StrokeStyle(lineWidth: ringW, lineCap: .round)
                    )

                    // Tick marks along active arc
                    let endDeg = frac * 360
                    let tickRO = rRing + ringW / 2 - 7
                    let tickRI = rRing - ringW / 2 + 7
                    var d: Double = 5
                    while d < endDeg - 7 {
                        let a = -.pi / 2 + d * .pi / 180
                        var tickPath = Path()
                        tickPath.move(to: CGPoint(x: c.x + tickRI * cos(a), y: c.y + tickRI * sin(a)))
                        tickPath.addLine(to: CGPoint(x: c.x + tickRO * cos(a), y: c.y + tickRO * sin(a)))
                        context.stroke(tickPath, with: .color(.black.opacity(0.42)), style: StrokeStyle(lineWidth: 1))
                        d += 2.2
                    }
                }
            }
            .frame(width: SIZE, height: SIZE)

            // Number labels outside ring (only when setting)
            if !isActive {
                ForEach([(60, "60"), (15, "15"), (30, "30"), (45, "45")], id: \.0) { n, lbl in
                    let a = -.pi / 2 + (Double(n) / 60) * .pi * 2
                    Text(lbl)
                        .font(.custom(T.fontHeader, size: 15).weight(.semibold))
                        .tracking(0.3)
                        .foregroundColor(T.text.opacity(0.35))
                        .position(
                            x: SIZE / 2 + rNumber * cos(a),
                            y: SIZE / 2 + rNumber * sin(a)
                        )
                }
                .frame(width: SIZE, height: SIZE)
            }

            // Inner content
            if isActive {
                // Backdrop matching the hourglass image's own background, so its hard
                // circular edge melts into the dial (near-black in dark, cream in light).
                Circle()
                    .fill(RadialGradient(
                        colors: [imageBackdrop, imageBackdrop.opacity(0)],
                        center: .center, startRadius: 80, endRadius: 108
                    ))
                    .frame(width: 220, height: 220)

                // Hourglass floats on the dial — dark render in dark mode, daytime render in light.
                Image(colorScheme == .dark ? "focus_pic" : "focus_pic_day")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 160, height: 160)
                    .clipShape(Circle())
            } else {
                // Center readout
                VStack(spacing: 2) {
                    Text("\(selectedMinutes)")
                        .font(.custom("Charter", size: 104).weight(.regular))
                        .tracking(-2)
                        .foregroundColor(T.text)
                        .contentTransition(.numericText())

                    Text("MIN")
                        .font(.custom(T.fontHeader, size: 13).weight(.bold))
                        .tracking(3)
                        .foregroundColor(T.text.opacity(0.55))
                }
            }

            // Knob chevron at trailing edge
            let kp = knobPoint(for: arcFraction)
            let arrowDeg = (knobAngle(for: arcFraction) * 180 / .pi) + 90

            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.black.opacity(0.55))
                .rotationEffect(.degrees(arrowDeg))
                .position(kp)

            // Session finished — a checkmark pops in the dial centre.
            if showFinishCheck {
                Image(systemName: "checkmark")
                    .font(.system(size: 46, weight: .heavy))
                    .foregroundColor(T.primary)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .frame(width: SIZE, height: SIZE)
        // The whole dial "gives" slightly while grabbed — feels physical.
        .scaleEffect(isDragging ? 1.015 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isDragging)
        // Paused → the dial breathes softly so time visibly "sleeps".
        .opacity(isPaused ? 0.6 : 1)
        .animation(
            isPaused ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                     : .easeInOut(duration: 0.3),
            value: isPaused
        )
        .contentShape(Circle().size(width: SIZE, height: SIZE))
        .gesture(ringDrag)
    }

    // MARK: - Active Controls

    private var activeControls: some View {
        VStack(spacing: 0) {
            Text(countdown)
                .font(.custom("Charter", size: 56).weight(.regular))
                .tracking(-1.5)
                .foregroundColor(T.text)
                .contentTransition(.numericText())
                .padding(.top, 16)

            HStack(spacing: 14) {
                Button {
                    addOneMinute()
                } label: {
                    Text("+ 1 min")
                        .font(.custom(T.fontHeader, size: 14).weight(.bold))
                        .foregroundColor(T.text.opacity(0.55))
                }
                .buttonStyle(.plain)

                Button {
                    togglePause()
                } label: {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(darkBg)
                        .frame(width: 64, height: 42)
                        .background(Capsule().fill(T.text.opacity(0.92)))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18)
        }
    }

    // MARK: - Start Button

    private var startButton: some View {
        Button {
            startSession()
        } label: {
            HStack(spacing: 14) {
                Text("Start")
                    .font(.custom("Charter", size: 24).weight(.regular))
                    .tracking(-0.2)
                PlayTriangle()
                    .fill(.white)
                    .frame(width: 14, height: 16)
            }
            .foregroundColor(.white)
            .frame(height: 60)
            .padding(.horizontal, 44)
            .background(
                Capsule().fill(T.primary)
            )
            .shadow(color: Color(hex: "#FF7A59").opacity(0.4), radius: 14, x: 0, y: 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ring Drag Gesture

    private var ringDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                touchActive = true
                guard !dragCompleted else { return }
                let dx = value.location.x - SIZE / 2
                let dy = value.location.y - SIZE / 2
                let dist = sqrt(dx * dx + dy * dy)

                // Only respond near the ring
                let inner = rRing - ringW
                let outer = rRing + ringW + 10
                guard dist >= inner && dist <= outer else { return }

                var angle = atan2(dy, dx) + .pi / 2
                if angle < 0 { angle += .pi * 2 }
                let fraction = angle / (.pi * 2)

                if isActive {
                    handleActiveDrag(value: value, fraction: fraction)
                } else {
                    handleSettingDrag(fraction: fraction)
                }
            }
            .onEnded { _ in
                touchActive = false
                isDragging = false
                dragAnchor = nil
                lastActiveStep = -1
                dragCompleted = false
            }
    }

    private func handleSettingDrag(fraction: Double) {
        if dragAnchor == nil {
            #if os(iOS)
            dialHaptic.prepare()
            #endif
        }
        // End-stop: never wrap across the 12 o'clock dead zone (the 1↔60 boundary).
        var mins: Int
        var effFraction = fraction
        if let anchor = dragAnchor {
            if anchor >= 0.75 && fraction <= 0.25 {        // pushed past 60 → hold at 60
                mins = 60; effFraction = 1
            } else if anchor <= 0.25 && fraction >= 0.75 { // pushed below 1 → hold at 1
                mins = 1; effFraction = 0
            } else {
                mins = Int(round(fraction * 60))
            }
        } else {
            mins = Int(round(fraction * 60))               // first touch — set directly
        }
        mins = max(1, min(60, mins))
        dragAnchor = effFraction
        if mins != selectedMinutes {
            selectedMinutes = mins
            dialTick()
        }
    }

    private func handleActiveDrag(value: DragGesture.Value, fraction: Double) {
        if !isDragging {
            let kp = knobPoint(for: activeProgress)
            let kd = sqrt(
                pow(value.startLocation.x - kp.x, 2) +
                pow(value.startLocation.y - kp.y, 2)
            )
            guard kd < 55 else { return }
            isDragging = true
            dragProgress = activeProgress
            lastRawFraction = fraction              // baseline for delta tracking
            lastActiveStep = Int(activeProgress * 60)
            #if os(iOS)
            dialHaptic.prepare()
            #endif
            return
        }

        // Accumulate the *shortest-path* angular delta between samples, so the
        // rotation is tracked continuously even across the 12 o'clock seam — no
        // jumping onto a new lap, even on a fast flick.
        var delta = fraction - lastRawFraction
        if delta > 0.5 { delta -= 1 } else if delta < -0.5 { delta += 1 }
        lastRawFraction = fraction

        // Hard end-stop: progress can never leave [current, 1.0]. At 1.0 the knob
        // sits exactly on 12 o'clock and the session finishes.
        let newProgress = min(1.0, max(activeProgress, dragProgress + delta))

        if newProgress >= 0.999 {
            dragProgress = 1.0
            dragCompleted = true        // ignore the rest of this drag — don't bleed into the time dial
            completeSession()
            return
        }

        // Haptic tick once per ring-minute as you scrub toward the finish.
        let step = Int(newProgress * 60)
        if step != lastActiveStep {
            lastActiveStep = step
            dialTick()
        }

        dragProgress = newProgress

        // Sand particles at knob
        spawnParticles(at: knobPoint(for: newProgress), count: 3)
    }

    /// One crisp dial tick — shared by the time dial and the finish dial. A prepared,
    /// reused `.rigid` generator, so it's firmer and more consistent than the old
    /// fire-a-fresh-generator-each-tick selection feedback.
    private func dialTick() {
        #if os(iOS)
        dialHaptic.impactOccurred(intensity: 0.7)
        #endif
    }

    // MARK: - Session Logic

    private func apply(_ req: FocusRequest) {
        // Switching mid-session must not eat the focus already done —
        // credit it the same way a finished dial would.
        if isActive {
            let earned = Int32(min(elapsed, totalSec) / 60)
            if earned > 0 { saveFocusData(minutes: earned) }
        }
        sessionCategory = req.category
        selectedMinutes = max(5, min(60, req.minutes))
        startSession()
    }

    private func startSession() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        withAnimation(.easeInOut(duration: 0.4)) { isActive = true }
        isPaused = false
        sessionStart = Date()
        elapsed = 0
        pauseAccum = 0
        pauseStart = nil
        lastLeft = nil
        persistSession()
    }

    /// Bring back a session that was nailed down before the app got killed.
    /// The same grace rule applies: a longer absence comes back paused, frozen
    /// at the moment the user left — nothing is lost, nothing kept running.
    private func restoreSessionIfNeeded() {
        guard !isActive, var snap = FocusSessionStore.load() else { return }

        // backgroundedAt covers a clean exit; the savedAt heartbeat covers a
        // crash/reboot where the scene handler never ran — either way a long
        // absence comes back paused, not counted as focus.
        if !snap.isPaused, let left = snap.backgroundedAt ?? snap.savedAt,
           Date().timeIntervalSince(left) > FocusNudge.delay {
            snap.isPaused = true
            snap.pauseStart = left
        }

        sessionStart = snap.sessionStart
        selectedMinutes = max(1, min(120, snap.selectedMinutes))   // legacy pre-clamp sessions may exceed 60
        pauseAccum = snap.pauseAccum
        isPaused = snap.isPaused
        pauseStart = snap.pauseStart
        sessionCategory = snap.category
        // Paused → frozen at the pause moment; running → caught up to now.
        let anchor = snap.isPaused ? (snap.pauseStart ?? Date()) : Date()
        elapsed = max(0, anchor.timeIntervalSince(snap.sessionStart) - snap.pauseAccum)
        lastLeft = nil
        withAnimation(.easeInOut(duration: 0.4)) { isActive = true }
        persistSession()   // re-save with backgroundedAt cleared
    }

    /// Nail the running session down so an app kill can't lose it.
    private func persistSession(leftAt: Date? = nil) {
        guard isActive, let start = sessionStart else {
            FocusSessionStore.clear()
            return
        }
        FocusSessionStore.save(FocusSessionSnapshot(
            sessionStart: start,
            selectedMinutes: selectedMinutes,
            pauseAccum: pauseAccum,
            isPaused: isPaused,
            pauseStart: pauseStart,
            category: sessionCategory,
            backgroundedAt: leftAt,
            savedAt: Date()
        ))
    }

    /// Leaving mid-session: nail the session to disk and set one gentle reminder.
    /// Returning: short hops (≤ the 3-min grace window) count as focus and the
    /// timer just carries on; longer absences retroactively become pause time,
    /// frozen at the moment the user left. Paused sessions don't nudge —
    /// stepping away on purpose isn't a distraction.
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background, .inactive:
            guard isActive else { return }
            if lastLeft == nil { lastLeft = Date() }
            persistSession(leftAt: lastLeft)
            if phase == .background && !isPaused { FocusNudge.schedule() }
        case .active:
            FocusNudge.cancel()
            if isActive, let left = lastLeft, !isPaused,
               Date().timeIntervalSince(left) > FocusNudge.delay {
                // Away past the grace window → the absence was a pause, not focus.
                isPaused = true
                pauseStart = left
                if let start = sessionStart {
                    elapsed = max(0, left.timeIntervalSince(start) - pauseAccum)
                }
            }
            lastLeft = nil
            if isActive { persistSession() }
        default:
            break
        }
    }

    private func togglePause() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        if isPaused {
            if let ps = pauseStart { pauseAccum += Date().timeIntervalSince(ps) }
            pauseStart = nil
            isPaused = false
        } else {
            pauseStart = Date()
            isPaused = true
        }
        persistSession()
    }

    private func addOneMinute() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        selectedMinutes = min(60, selectedMinutes + 1)   // the dial's ceiling — restore clamps there too
        persistSession()
    }

    private func completeSession() {
        // Clamp to the dialed length — a short background hop can overshoot slightly.
        let focusMin = Int32(min(elapsed, totalSec) / 60)
        FocusNudge.cancel()
        FocusSessionStore.clear()
        playCompletionSound()

        // Finish flourish: checkmark pops in the dial + a burst of sand.
        withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { showFinishCheck = true }
        spawnParticles(at: CGPoint(x: SIZE / 2, y: SIZE / 2 - rRing), count: 36)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            withAnimation(.easeOut(duration: 0.4)) { showFinishCheck = false }
        }

        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif

        if focusMin > 0 { saveFocusData(minutes: focusMin) }

        // If a finger is still on the dial, the rest of that drag must not
        // bleed into the fresh idle dial as a new session length.
        if isDragging || touchActive { dragCompleted = true }

        withAnimation(.easeInOut(duration: 0.4)) { isActive = false }
        isPaused = false
        isDragging = false
        dragAnchor = nil
        lastActiveStep = -1
        elapsed = 0
        sessionStart = nil
        pauseAccum = 0
        pauseStart = nil
        sessionCategory = nil
    }

    private func saveFocusData(minutes: Int32) {
        let today = Calendar.current.startOfDay(for: Date())
        let req = NSFetchRequest<CompletionStreak>(entityName: "CompletionStreak")
        req.predicate = NSPredicate(format: "date == %@", today as NSDate)
        req.fetchLimit = 1
        do {
            let results = try viewContext.fetch(req)
            let streak = results.first ?? {
                let s = CompletionStreak(context: viewContext)
                s.date = today
                return s
            }()
            streak.focusMinutesTotal += minutes
            try viewContext.save()
        } catch {
            print("Failed to save focus session: \(error)")
        }
    }

    // MARK: - Clock

    private func tickClock() {
        guard isActive else { return }
        if isPaused {
            // The projected end line depends on wall time — nudge a render
            // about once a second so it doesn't freeze at the pause moment.
            if Date().timeIntervalSince(pauseTick) >= 1 { pauseTick = Date() }
            return
        }
        // lastLeft != nil → we're mid-transition from background; don't recompute
        // elapsed until the scene handler decides whether the absence was a pause.
        guard lastLeft == nil, let start = sessionStart else { return }
        elapsed = max(0, Date().timeIntervalSince(start) - pauseAccum)
        // Refresh the crash-recovery heartbeat about twice a minute.
        if Date().timeIntervalSince(lastHeartbeat) >= 30 {
            lastHeartbeat = Date()
            persistSession()
        }
        if elapsed >= totalSec { completeSession() }
    }

    // MARK: - Particles

    private func spawnParticles(at pos: CGPoint, count: Int) {
        for _ in 0..<count {
            particleID &+= 1
            let angle = CGFloat.random(in: 0...(.pi * 2))
            let speed = CGFloat.random(in: 30...80)
            let maxLife = CGFloat.random(in: 0.4...0.7)
            particles.append(SandParticle(
                id: particleID,
                x: pos.x + .random(in: -3...3),
                y: pos.y + .random(in: -3...3),
                vx: cos(angle) * speed,
                vy: sin(angle) * speed + 20,
                life: maxLife, maxLife: maxLife,
                size: .random(in: 2...5)
            ))
        }
        if particles.count > 200 { particles.removeFirst(particles.count - 200) }
    }

    private func tickParticles() {
        guard !particles.isEmpty else { return }
        let dt: CGFloat = 1.0 / 60.0
        particles = particles.compactMap { p in
            var p = p
            p.x += p.vx * dt
            p.y += p.vy * dt
            p.vy += 40 * dt
            p.life -= dt
            return p.life > 0 ? p : nil
        }
    }

    // MARK: - Audio

    private func playCompletionSound() {
        if let url = Bundle.main.url(forResource: "universfield-new-notification-013-363676", withExtension: "mp3") {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try AVAudioSession.sharedInstance().setActive(true)
                completionPlayer = try AVAudioPlayer(contentsOf: url)
                completionPlayer?.volume = 0.5
                completionPlayer?.play()
            } catch { print("Completion sound error: \(error)") }
        } else {
            #if os(iOS)
            AudioServicesPlaySystemSound(1007)
            #endif
        }
    }
}

// MARK: - Play Triangle Shape

struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

#Preview {
    FocusView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
