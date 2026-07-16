import SwiftUI
import CoreData
import StoreKit
import UserNotifications

/// Manual light/dark override. `.system` follows the device (the default —
/// the app's adaptive colors already switch automatically).
enum ThemePreference: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: String(localized: "Auto")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
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
    var title: String { self == .wake ? "Wake time" : "Energy dip" }
}

struct ProfileView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SubscriptionManager.self) private var subs
    @Environment(\.managedObjectContext) private var viewContext

    @State private var showPaywall = false
    @State private var editingTime: TimeField?
    @State private var showPrivacy = false
    @State private var showTerms = false
    @AppStorage("themePreference") private var theme: ThemePreference = .system
    @AppStorage("appLanguage") private var appLanguage = "system"
    @State private var showLanguageAlert = false
    @AppStorage("nudgesEnabled") private var nudges = true

    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings")
                        .font(.custom(T.fontHeader, size: 32).weight(.heavy))
                        .tracking(-0.5)
                        .foregroundColor(T.text)
                        .padding(.horizontal, 22)
                        .padding(.top, 20)

                    subscriptionCard
                        .padding(.top, 20)

                    theDaySection
                    appearanceSection
                    languageSection
                    aiSection
                    legalSection

                    Text("Tempa 1.2 · find your tempo")
                        .font(.custom(T.fontBody, size: 12).weight(.medium))
                        .foregroundColor(T.textSec)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                        .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .onChange(of: settings.wakeTime) { settings.save() }
        .sheet(isPresented: $showPaywall) {
            PaywallView(allowDismiss: true, onPurchaseComplete: {})
        }
        .sheet(item: $editingTime) { field in
            timeSheet(field)
        }
        .sheet(isPresented: $showPrivacy) {
            PrivacyPolicySheet()
        }
        .sheet(isPresented: $showTerms) {
            TermsSheet()
        }
    }

    // MARK: - Subscription (plan only, no name)

    private var subscriptionCard: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            showPaywall = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(T.primary)
                        .frame(width: 50, height: 50)
                    Image(systemName: subs.isPro ? "crown.fill" : "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(subs.isPro ? "Tempa Plus" : "Free plan")
                        .font(.custom(T.fontHeader, size: 17).weight(.heavy))
                        .foregroundColor(T.text)
                    Text(planSubtitle)
                        .font(.custom(T.fontBody, size: 13).weight(.medium))
                        .foregroundColor(T.textSec)
                }

                Spacer()

                Text(subs.isPro ? "Change" : "Upgrade")
                    .font(.custom(T.fontHeader, size: 12).weight(.bold))
                    .foregroundColor(subs.isPro ? T.text : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(subs.isPro ? T.surface : T.primary)
                    )
                    .tempaShadowSm()
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(lightHex: "#FFE9E1", darkHex: "#2C1F18"), Color(lightHex: "#FFFDF8", darkHex: "#241D18")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            )
            .tempaShadowSm()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private var planSubtitle: String {
        guard let id = subs.purchasedProductIDs.first else {
            return String(localized: "Unlock AI planning & breakdowns")
        }
        let name = planName(id)
        if let price = price(for: id) { return "\(name) · \(price)" }
        return name
    }

    private func planName(_ id: String) -> String {
        switch id {
        case "tempa_yearly": "Yearly"
        case "tempa_monthly": "Monthly"
        case "tempa_weekly": "Weekly"
        default: "Active"
        }
    }

    private func price(for id: String) -> String? {
        if let p = subs.products.first(where: { $0.id == id }) { return p.displayPrice }
        if let s = subs.simPlans.first(where: { $0.id == id }) { return s.price }
        return nil
    }

    // MARK: - The day (all functional)

    private var theDaySection: some View {
        settingsGroup("The day") {
            SettingRow(icon: "sun.max.fill", iconBg: Cat.routine.bg, iconColor: Cat.routine.ink,
                       title: "Wake time", detail: String(localized: "Anchors your day battery"),
                       value: settings.wakeTime.formatted(.dateTime.hour().minute())) {
                editingTime = .wake
            }
            SettingRow(icon: "flame.fill", iconBg: Cat.personal.bg, iconColor: Cat.personal.ink,
                       title: "Energy dip", detail: String(localized: "When your focus usually drops"),
                       value: settings.energyDipTime?.formatted(.dateTime.hour().minute()) ?? String(localized: "Off")) {
                editingTime = .dip
            }
            SettingRow(icon: "bell.fill", iconBg: Cat.work.bg, iconColor: Cat.work.ink,
                       title: "Gentle nudges", detail: String(localized: "Reminder 10 min before each task"),
                       isOn: Binding(get: { nudges }, set: { setNudges($0) }))
        }
    }

    private func setNudges(_ on: Bool) {
        nudges = on
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        if on {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                Task { @MainActor in TaskNotifications.rescheduleAll(context: viewContext) }
            }
        } else {
            TaskNotifications.rescheduleAll(context: viewContext)   // clears all pending reminders
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
                        showLanguageAlert = true
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
        .alert("Language updated", isPresented: $showLanguageAlert) {
            Button("OK") {}
        } message: {
            Text("Close and reopen Tempa to switch the language.")
        }
    }

    // MARK: - AI (real usage)

    private var aiSection: some View {
        settingsGroup("AI") {
            SettingRow(icon: "sparkles", iconBg: Color(lightHex: "#FFE9E1", darkHex: "#2C1F18"), iconColor: T.primary,
                       title: "AI requests this month", value: "\(AIUsage.thisMonth)")
        }
    }

    // MARK: - Legal

    private var legalSection: some View {
        settingsGroup("Legal") {
            SettingRow(icon: "lock.fill", iconBg: T.bgWarm, iconColor: T.textSec,
                       title: "Privacy Policy", detail: String(localized: "What stays on-device, what goes to AI")) {
                showPrivacy = true
            }
            SettingRow(icon: "doc.text", iconBg: T.bgWarm, iconColor: T.textSec,
                       title: "Terms of Service", detail: String(localized: "The ground rules")) {
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
