import SwiftUI
import CoreData
import UserNotifications

/// Manual light/dark override. `.system` follows the device (the default —
/// the app's adaptive colors already switch automatically).
enum ThemePreference: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: String(localized: "Auto", bundle: .appLanguage)
        case .light: String(localized: "Light", bundle: .appLanguage)
        case .dark: String(localized: "Dark", bundle: .appLanguage)
        }
    }
    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private enum TimeField: String, Identifiable {
    case wake, dip
    var id: String { rawValue }
    var title: String {
        self == .wake ? String(localized: "Wake time", bundle: .appLanguage)
                      : String(localized: "Energy dip", bundle: .appLanguage)
    }
}

struct ProfileView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.managedObjectContext) private var viewContext

    @State private var editingTime: TimeField?
    @State private var showPrivacy = false
    @State private var showTerms = false
    @State private var showCalendars = false
    @State private var confirmGoogleDisconnect = false
    @State private var googleProblem: String?
    @State private var calendarSync = CalendarSync.shared
    @State private var google = GoogleCalendar.shared
    @AppStorage("themePreference") private var theme: ThemePreference = .system
    @AppStorage("appLanguage") private var appLanguage = "system"
    @AppStorage("nudgesEnabled") private var nudges = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()
                .onAppear { refreshNudgeTruth() }
                .onChange(of: scenePhase) { _, p in
                    if p == .active { refreshNudgeTruth() }
                }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings")
                        .font(.custom(T.fontHeader, size: 32).weight(.heavy))
                        .tracking(-0.5)
                        .foregroundColor(T.text)
                        .padding(.horizontal, 22)
                        .padding(.top, 20)

                    theDaySection
                    calendarSection
                    appearanceSection
                    languageSection
                    legalSection

                    Text("Tempa 1.2 · find your tempo")
                        .font(.custom(T.fontBody, size: 12).weight(.medium))
                        .foregroundColor(T.textSec)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                        .padding(.bottom, TempaTabBar.contentClearance)
                }
            }
        }
        .navigationBarHidden(true)
        .onChange(of: settings.wakeTime) { settings.save() }
        .sheet(item: $editingTime) { field in
            timeSheet(field)
        }
        .sheet(isPresented: $showCalendars) {
            CalendarPickerSheet()
        }
        .sheet(isPresented: $showPrivacy) {
            PrivacyPolicySheet()
        }
        .sheet(isPresented: $showTerms) {
            TermsSheet()
        }
    }

    // MARK: - The day (all functional)

    private var theDaySection: some View {
        settingsGroup("The day") {
            SettingRow(icon: "sun.max.fill", iconBg: Cat.routine.bg, iconColor: Cat.routine.ink,
                       title: "Wake time", detail: String(localized: "Your day is laid out from here", bundle: .appLanguage),
                       value: settings.wakeTime.formatted(.dateTime.hour().minute())) {
                editingTime = .wake
            }
            SettingRow(icon: "flame.fill", iconBg: Cat.personal.bg, iconColor: Cat.personal.ink,
                       title: "Energy dip", detail: String(localized: "When your focus usually drops", bundle: .appLanguage),
                       value: settings.energyDipTime?.formatted(.dateTime.hour().minute()) ?? String(localized: "Off", bundle: .appLanguage)) {
                editingTime = .dip
            }
            SettingRow(icon: "bell.fill", iconBg: Cat.work.bg, iconColor: Cat.work.ink,
                       title: "Gentle nudges", detail: String(localized: "Reminder 10 min before each task", bundle: .appLanguage),
                       isOn: Binding(get: { nudges }, set: { setNudges($0) }))
        }
    }

    // MARK: - Calendar

    private var calendarSection: some View {
        settingsGroup("Calendar") {
            SettingRow(icon: "calendar", iconBg: Cat.work.bg, iconColor: Cat.work.ink,
                       title: "iPhone calendars", detail: String(localized: "Apple, Google, Outlook — whatever is on this iPhone", bundle: .appLanguage),
                       isOn: Binding(get: { calendarSync.appleActive }, set: { setAppleCalendars($0) }))
            // Shown once the option is switched on (or to let a connected
            // account be disconnected, whatever the switch says).
            if google.isAvailable || google.isConnected {
                SettingRow(icon: "g.circle.fill", iconBg: Cat.personal.bg, iconColor: Cat.personal.ink,
                           title: "Google Calendar",
                           detail: google.isConnected
                               ? (google.email ?? String(localized: "Connected", bundle: .appLanguage))
                               : String(localized: "Sign in to show your Google calendars", bundle: .appLanguage),
                           value: google.isConnected
                               ? String(localized: "Connected", bundle: .appLanguage)
                               : String(localized: "Connect", bundle: .appLanguage)) {
                    if google.isConnected { confirmGoogleDisconnect = true } else { connectGoogle() }
                }
            }
            if calendarSync.isActive {
                SettingRow(icon: "checklist", iconBg: Cat.health.bg, iconColor: Cat.health.ink,
                           title: "Which calendars", detail: String(localized: "Pick the ones that belong on your day", bundle: .appLanguage)) {
                    showCalendars = true
                }
            }
        }
        .confirmationDialog("Disconnect Google Calendar?", isPresented: $confirmGoogleDisconnect, titleVisibility: .visible) {
            Button(String(localized: "Disconnect", bundle: .appLanguage), role: .destructive) {
                Task {
                    await calendarSync.disconnectGoogle(from: viewContext)
                    reportCalendar(provider: "google", outcome: "disconnected")
                }
            }
            Button(String(localized: "Cancel", bundle: .appLanguage), role: .cancel) {}
        } message: {
            Text("Its upcoming events will leave your days. Nothing changes in Google.")
        }
        .alert("Google Calendar isn't connected yet",
               isPresented: Binding(get: { googleProblem != nil }, set: { if !$0 { googleProblem = nil } })) {
            Button(String(localized: "OK", bundle: .appLanguage), role: .cancel) {}
        } message: {
            Text(googleProblem ?? "")
        }
    }

    private func setAppleCalendars(_ on: Bool) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        guard on else {
            calendarSync.disconnectApple(from: viewContext)
            reportCalendar(provider: "apple", outcome: "disconnected")
            return
        }
        if calendarSync.isDenied {
            // iOS asks once; after a "no" the switch lives in the Settings app.
            // The wish is remembered: the toggle still reads OFF (there is no
            // access yet), and the moment access exists the mirror is on.
            calendarSync.appleEnabled = true
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            return
        }
        Task {
            let granted = await calendarSync.requestAccess()
            calendarSync.appleEnabled = granted
            if granted { calendarSync.sync(into: viewContext) }
            reportCalendar(provider: "apple", outcome: granted ? "connected" : "denied")
        }
    }

    private func connectGoogle() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        Task {
            do {
                try await google.connect()
                await calendarSync.refresh(into: viewContext)
                reportCalendar(provider: "google", outcome: "connected")
            } catch GoogleCalendarError.cancelled {
                reportCalendar(provider: "google", outcome: "skipped")
            } catch GoogleCalendarError.calendarNotGranted {
                reportCalendar(provider: "google", outcome: "not_granted")
                googleProblem = String(localized: "On Google's page, the calendar box has to stay ticked — without it Tempa can't show your events. Try again whenever you like.", bundle: .appLanguage)
            } catch {
                reportCalendar(provider: "google", outcome: "failed")
                googleProblem = String(localized: "Couldn't reach Google just now. Try again in a moment.", bundle: .appLanguage)
            }
        }
    }

    /// Counts only — what is IN a calendar is never an analytics property.
    private func reportCalendar(provider: String, outcome: String) {
        let connected = outcome == "connected"
        AnalyticsService.shared.track(.calendarSyncResult, properties: [
            "source": "settings", "provider": provider, "outcome": outcome,
            "events_7d": connected ? calendarSync.upcomingCount() : 0,
            "calendars": calendarSync.calendars().count,
        ])
    }

    private func setNudges(_ on: Bool) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        nudges = on   // optimistic — corrected below only if iOS says no
        guard on else {
            TaskNotifications.rescheduleAll(context: viewContext)   // clears all pending reminders
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { s in
            Task { @MainActor in
                if s.authorizationStatus == .denied {
                    // iOS owns this decision now — the only way back on is the
                    // system Settings page, so take them there.
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        await UIApplication.shared.open(url)
                    }
                    nudges = false
                } else {
                    let granted = (try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound])) ?? false
                    nudges = granted
                    TaskNotifications.rescheduleAll(context: viewContext)
                }
            }
        }
    }

    /// The toggle must reflect reality: if notifications were denied in iOS
    /// Settings, showing it ON would be a lie — nothing can arrive.
    private func refreshNudgeTruth() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            Task { @MainActor in
                if s.authorizationStatus == .denied && nudges {
                    nudges = false
                    TaskNotifications.rescheduleAll(context: viewContext)
                }
            }
        }
    }

    // MARK: - Appearance (manual theme override)

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("APPEARANCE")
                .font(.custom(T.fontHeader, size: 11).weight(.heavy))
                .tracking(1.5)
                .foregroundColor(T.textSec)
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 10)

            HStack(spacing: 6) {
                ForEach(ThemePreference.allCases, id: \.self) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { theme = option }
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: option.icon)
                                .font(.system(size: 18, weight: .medium))
                            Text(option.label)
                                .font(.custom(T.fontHeader, size: 13).weight(.bold))
                        }
                        .foregroundColor(theme == option ? T.text : T.textSec)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(theme == option ? T.surface : .clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(theme == option ? T.primary.opacity(0.4) : .clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(T.bgWarm))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        settingsGroup("Language") {
            Menu {
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        lang.apply()
                        appLanguage = lang.rawValue
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                    } label: {
                        if lang.rawValue == appLanguage {
                            Label(lang.displayName, systemImage: "checkmark")
                        } else {
                            Text(lang.displayName)
                        }
                    }
                }
            } label: {
                SettingRow(icon: "globe", iconBg: Color(lightHex: "#E3F0FB", darkHex: "#16283A"), iconColor: Color(hex: "#4A90D9"),
                           title: "App language",
                           value: (AppLanguage(rawValue: appLanguage) ?? .system).displayName)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Legal

    private var legalSection: some View {
        settingsGroup("Legal") {
            SettingRow(icon: "lock.fill", iconBg: T.bgWarm, iconColor: T.textSec,
                       title: "Privacy Policy", detail: String(localized: "What stays on-device, what goes to AI", bundle: .appLanguage)) {
                showPrivacy = true
            }
            SettingRow(icon: "doc.text", iconBg: T.bgWarm, iconColor: T.textSec,
                       title: "Terms of Service", detail: String(localized: "The ground rules", bundle: .appLanguage)) {
                showTerms = true
            }
        }
    }

    // MARK: - Sheets

    private func timeSheet(_ field: TimeField) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(field.title)
                    .font(.custom(T.fontHeader, size: 20).weight(.heavy))
                    .foregroundColor(T.text)
                Spacer()
                Button {
                    editingTime = nil
                } label: {
                    Text("Done")
                        .font(.custom(T.fontHeader, size: 15).weight(.bold))
                        .foregroundColor(T.primary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 8)

            if field == .dip {
                Button {
                    settings.energyDipTime = nil
                    settings.save()
                } label: {
                    Text(settings.energyDipTime == nil ? "No energy dip ✓" : "Turn off energy dip")
                        .font(.custom(T.fontHeader, size: 14).weight(.bold))
                        .foregroundColor(settings.energyDipTime == nil ? T.textSec : T.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(T.surface))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }

            DatePicker("", selection: field == .wake ? wakeBinding : dipBinding, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()

            Spacer(minLength: 0)
        }
        .presentationDetents([.height(field == .dip ? 360 : 320)])
        .presentationDragIndicator(.visible)
        .presentationBackground(T.bg)
    }

    private var wakeBinding: Binding<Date> {
        Binding(get: { settings.wakeTime }, set: { settings.wakeTime = $0 })   // saved via onChange
    }

    private var dipBinding: Binding<Date> {
        let fallback = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date()) ?? Date()
        return Binding(
            get: { settings.energyDipTime ?? fallback },
            set: { settings.energyDipTime = $0; settings.save() }
        )
    }

    // MARK: - Settings Group

    private func settingsGroup<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .textCase(.uppercase)
                .font(.custom(T.fontHeader, size: 11).weight(.heavy))
                .tracking(1.5)
                .foregroundColor(T.textSec)
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(T.surface)
            )
            .tempaShadowSm()
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Calendar picker

/// Which of the phone's calendars belong on the day. Every change re-runs
/// the mirror, so the day behind the sheet is already right when it closes.
struct CalendarPickerSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var calendars: [CalendarSync.CalendarInfo] = []

    var body: some View {
        NavigationStack {
            ZStack {
                T.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(spacing: 0) {
                            ForEach(calendars) { info in
                                row(info)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.surface))
                        .tempaShadowSm()

                        // Only while signing in to Google right here isn't on offer.
                        if !GoogleCalendar.shared.isAvailable && !GoogleCalendar.shared.isConnected {
                            Text("Using Google Calendar? Add your Google account to this iPhone — in Settings, under the Calendar accounts — and it shows up here by itself.")
                                .font(.custom(T.fontBody, size: 12).weight(.medium))
                                .foregroundColor(T.textSec)
                                .lineSpacing(2)
                                .padding(.horizontal, 6)
                                .padding(.top, 14)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Which calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { calendars = CalendarSync.shared.calendars() }
    }

    private func row(_ info: CalendarSync.CalendarInfo) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(info.color.map { Color(cgColor: $0) } ?? T.textTer)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(info.title)
                    .font(.custom(T.fontHeader, size: 15).weight(.bold))
                    .foregroundColor(T.text)
                if !info.account.isEmpty {
                    Text(info.account)
                        .font(.custom(T.fontBody, size: 12).weight(.medium))
                        .foregroundColor(T.textSec)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { info.isIncluded },
                set: { on in
                    CalendarSync.shared.setIncluded(on, calendarID: info.id)
                    calendars = CalendarSync.shared.calendars()
                    // A Google calendar switched on has to be fetched first.
                    Task { await CalendarSync.shared.refresh(into: viewContext) }
                }
            ))
            .labelsHidden()
            .tint(T.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Setting Row

struct SettingRow: View {
    let icon: String
    let iconBg: Color
    let iconColor: Color
    let title: LocalizedStringKey
    var detail: String? = nil
    var value: String? = nil
    var isOn: Binding<Bool>? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconBg)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.custom(T.fontHeader, size: 15).weight(.bold))
                    .foregroundColor(T.text)
                if let detail {
                    Text(detail)
                        .font(.custom(T.fontBody, size: 12).weight(.medium))
                        .foregroundColor(T.textSec)
                }
            }

            Spacer()

            if let isOn {
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .tint(T.secondary)
            } else if let value {
                HStack(spacing: 6) {
                    Text(value)
                        .font(.custom(T.fontHeader, size: 14).weight(.semibold))
                        .foregroundColor(T.textSec)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(T.textTer)
                }
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(T.textTer)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 1)
                .padding(.leading, 66)
        }
    }
}

#if DEBUG
struct DebugView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(sortDescriptors: [SortDescriptor(\TaskBlock.createdAt, order: .reverse)])
    private var allTasks: FetchedResults<TaskBlock>

    var body: some View {
        List {
            Section {
                Button("Add test task") {
                    let task = TaskBlock(context: viewContext)
                    task.id = UUID()
                    task.title = "Test \(Date().formatted(date: .omitted, time: .standard))"
                    task.iconName = "hammer"
                    task.colorHex = "#E3EDFF"
                    task.category = "work"
                    task.startTime = Date()
                    task.durationMinutes = 15
                    task.createdAt = Date()
                    try? viewContext.save()
                }
            }
            Section("All Tasks (\(allTasks.count))") {
                ForEach(allTasks) { task in
                    VStack(alignment: .leading) {
                        Text(task.title ?? "Untitled").font(.headline)
                        Text("Created: \(task.createdAt?.formatted() ?? "?")").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    for i in offsets { viewContext.delete(allTasks[i]) }
                    try? viewContext.save()
                }
            }
        }
        .navigationTitle("Debug")
    }
}
#endif

#Preview {
    NavigationStack {
        ProfileView()
    }
    .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    .environment(SettingsStore(context: PersistenceController.preview.container.viewContext))
    .environment(SubscriptionManager.shared)
}
