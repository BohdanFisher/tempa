import SwiftUI
import StoreKit
import UserNotifications

struct PaywallView: View {
    @Environment(SubscriptionManager.self) private var subs
    @Environment(\.dismiss) private var dismiss

    let allowDismiss: Bool
    let onPurchaseComplete: () -> Void

    @State private var selectedProductID = "tempa_yearly"
    @State private var isPurchasing = false
    /// CTA morph: text → spinner → checkmark (button shape stays, content flows).
    private enum PurchasePhase { case idle, working, success }
    @State private var purchasePhase: PurchasePhase = .idle
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showTermsDoc = false
    @State private var showPrivacyDoc = false
    /// "Remind me before trial ends" — a real local notification on day 2,
    /// scheduled at purchase. Trust beats a dark pattern every time.
    @AppStorage("trialReminderWanted") private var trialReminderOn = true
    @State private var pendingTrialReminder = false

    // Bright coral in light mode; a deeper, calmer coral in dark mode.
    private let coral = Color(lightHex: "#FF7A59", darkHex: "#D06A4B")
    private let teal = Color(hex: "#3FC09A")

    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 10)

                // Flexible middle — everything fits without scrolling on modern
                // phones; on small ones this scrolls while plans + CTA stay put.
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.top, 6)

                        benefitRail
                            .padding(.top, 16)

                        if hasIntroOffer {
                            trialCard
                                .padding(.top, 16)
                                .staggerIn(1, baseDelay: 0.08)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 10)
                }

                planCards
                    .padding(.horizontal, 18)
                    .padding(.top, 4)

                ctaButton
                    .padding(.horizontal, 18)
                    .padding(.top, 14)

                transparencyLine
                    .padding(.top, 10)

                footer
            }
        }
        .alert("Error", isPresented: $showError) { Button("OK") {} } message: { Text(errorMessage) }
        .task {
            AnalyticsService.shared.track(.paywallShown,
                                          properties: ["trial_ui": hasIntroOffer])
            // Retry StoreKit when the paywall appears — recovers from a failed
            // cold-start load and swaps simulated plans for real products.
            await subs.ensureProductsLoaded()
            reconcileSelection()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            if allowDismiss {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(T.textSec)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(T.surface))
                        .tempaShadowSm()
                }
            }
            Spacer()
            Button { restore() } label: {
                Text("Restore")
                    .font(.custom("Nunito-ExtraBold", size: 14).weight(.bold))
                    .foregroundColor(T.textSec)
            }
        }
        .padding(.horizontal, 22)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TEMPA PRO")
                .font(.custom("Nunito-ExtraBold", size: 12).weight(.heavy))
                .tracking(2.4)
                .foregroundColor(coral)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(coral.opacity(0.12)))
                .staggerIn(0)

            Text("Less noise. More you.")
                .font(.custom("Nunito-ExtraBold", size: 25).weight(.heavy))
                .tracking(-0.5)
                .foregroundColor(T.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .staggerIn(1)
        }
    }

    // MARK: - Benefits

    private var benefitRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            benefit("mic.fill", coral, "Speak your day — AI turns it into a plan")
            benefit("rectangle.stack.fill", teal, "One thing at a time, never a wall of tasks")
            benefit("timer", Cat.routine.ink, "Focus sessions with gentle comeback nudges")
        }
        .staggerIn(2)
    }

    private func benefit(_ icon: String, _ tint: Color, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint.opacity(0.14)))
            Text(text)
                .font(.custom("Inter-Medium", size: 13).weight(.medium))
                .foregroundColor(T.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Trial timeline card

    /// The single highest-trust element on a trial paywall: what happens on
    /// which day, plus a reminder toggle that schedules a REAL notification.
    private var trialCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How your free trial works")
                .font(.custom("Nunito-ExtraBold", size: 15).weight(.heavy))
                .foregroundColor(T.text)
                .padding(.bottom, 10)

            timelineStep(icon: "lock.open.fill",
                         day: String(localized: "Today", bundle: .appLanguage),
                         text: "Full access to everything", filled: true, last: false)
            if trialDays >= 2 {
                timelineStep(icon: "bell.fill",
                             day: String(localized: "Day \(trialDays - 1)", bundle: .appLanguage),
                             text: "A reminder before anything is charged", filled: false, last: false)
            }
            timelineStep(icon: "checkmark.seal.fill",
                         day: String(localized: "Day \(trialDays)", bundle: .appLanguage),
                         text: "Yearly starts — cancel anytime before", filled: false, last: true)

            Divider()
                .padding(.vertical, 8)

            HStack {
                Text("Remind me before trial ends")
                    .font(.custom("Inter-Medium", size: 13).weight(.semibold))
                    .foregroundColor(T.text)
                Spacer()
                Toggle("", isOn: $trialReminderOn)
                    .labelsHidden()
                    .tint(teal)
                    .scaleEffect(0.85, anchor: .trailing)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.surface))
        .tempaShadowSm()
    }

    private func timelineStep(icon: String, day: String, text: LocalizedStringKey,
                              filled: Bool, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(filled ? coral : coral.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(filled ? .white : coral)
                }
                if !last {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(coral.opacity(0.18))
                        .frame(width: 3)
                        .frame(minHeight: 10)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(day)
                    .font(.custom("Nunito-ExtraBold", size: 14).weight(.heavy))
                    .foregroundColor(T.text)
                Text(text)
                    .font(.custom("Inter-Medium", size: 12).weight(.medium))
                    .foregroundColor(T.textSec)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, last ? 0 : 6)

            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Plan cards

    private var planCards: some View {
        VStack(spacing: 10) {
            if subs.isSimulating {
                ForEach(Array(subs.simPlans.filter { $0.id != "tempa_weekly" }.enumerated()), id: \.element.id) { i, plan in
                    planCard(
                        id: plan.id,
                        title: planTitle(id: plan.id, fallback: plan.name),
                        isYearly: plan.id == "tempa_yearly",
                        price: plan.price,
                        sub: plan.monthlyPrice.map { String(localized: "\($0)/mo", bundle: .appLanguage) } ?? String(localized: "per \(plan.periodLabel)", bundle: .appLanguage),
                        detail: plan.id == "tempa_yearly" ? String(localized: "\(trialLengthText) free, then billed yearly", bundle: .appLanguage) : nil
                    )
                    .staggerIn(i, baseDelay: 0.1)
                }
            } else if subs.products.isEmpty {
                // Store unreachable in Release (simulation is DEBUG-only): an
                // honest state with a retry — never a silent dead end.
                storeUnreachableCard
            } else {
                ForEach(Array(subs.products.filter { $0.id != "tempa_weekly" }.enumerated()), id: \.element.id) { i, product in
                    let yearly = product.id == "tempa_yearly"
                    planCard(
                        id: product.id,
                        title: planTitle(id: product.id, fallback: product.displayName),
                        isYearly: yearly,
                        price: product.displayPrice,
                        sub: yearly ? (monthlyEquivalent(product).map { String(localized: "\($0)/mo", bundle: .appLanguage) } ?? String(localized: "per year", bundle: .appLanguage)) : String(localized: "per \(periodLabel(product))", bundle: .appLanguage),
                        detail: yearly && (subs.hasIntroOfferEligibility["tempa_yearly"] ?? false)
                            ? String(localized: "\(trialLengthText) free, then billed yearly", bundle: .appLanguage) : nil
                    )
                    .staggerIn(i, baseDelay: 0.1)
                }
            }
        }
    }

    private var storeUnreachableCard: some View {
        VStack(spacing: 10) {
            Text("Couldn't reach the App Store")
                .font(.custom("Nunito-ExtraBold", size: 15).weight(.heavy))
                .foregroundColor(T.text)
            Text("Check your connection and try again.")
                .font(.custom("Inter-Medium", size: 13).weight(.medium))
                .foregroundColor(T.textSec)
            Button {
                Task {
                    await subs.ensureProductsLoaded()
                    reconcileSelection()
                }
            } label: {
                Text("Try again")
                    .font(.custom("Nunito-ExtraBold", size: 14).weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(coral))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(T.surface))
        .tempaShadowSm()
    }

    private func planCard(id: String, title: String, isYearly: Bool, price: String, sub: String, detail: String?) -> some View {
        let picked = selectedProductID == id
        return Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selectedProductID = id
            }
            AnalyticsService.shared.track(.paywallProductSelected, properties: ["product": id])
        } label: {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .stroke(picked ? coral : T.textTer.opacity(0.5), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if picked {
                        Circle().fill(coral).frame(width: 14, height: 14)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.6), value: picked)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.custom("Nunito-ExtraBold", size: 16).weight(.heavy))
                            .foregroundColor(T.text)
                        if isYearly { savingsBadge }
                    }
                    if let detail {
                        Text(detail)
                            .font(.custom("Inter-Medium", size: 12).weight(.medium))
                            .foregroundColor(T.textSec)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(price)
                        .font(.custom("Nunito-ExtraBold", size: 16).weight(.heavy))
                        .foregroundColor(T.text)
                    Text(sub)
                        .font(.custom("Inter-Medium", size: 11).weight(.semibold))
                        .foregroundColor(T.textSec)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(picked ? coral.opacity(0.07) : T.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(picked ? coral : T.textTer.opacity(0.18), lineWidth: picked ? 1.8 : 1)
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: picked)
        }
        .buttonStyle(SpringPressStyle(scale: 0.98))
    }

    /// Real savings, computed from the store's own prices — falls back to
    /// BEST VALUE when the monthly price isn't loaded to divide by.
    private var savingsBadge: some View {
        Group {
            if let pct = savingsPercent {
                badgeText(String(localized: "SAVE \(pct)%", bundle: .appLanguage))
            } else {
                badgeText(String(localized: "BEST VALUE", bundle: .appLanguage))
            }
        }
    }

    private func badgeText(_ s: String) -> some View {
        Text(s)
            .font(.custom("Nunito-ExtraBold", size: 10).weight(.heavy))
            .tracking(0.5)
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(teal))
    }

    private var savingsPercent: Int? {
        guard let y = subs.products.first(where: { $0.id == "tempa_yearly" }),
              let m = subs.products.first(where: { $0.id == "tempa_monthly" }),
              m.price > 0 else { return nil }
        let ratio = NSDecimalNumber(decimal: y.price / (m.price * 12)).doubleValue
        let pct = Int(((1 - ratio) * 100).rounded())
        return pct >= 5 ? pct : nil
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button {
            Task { await purchaseSelected() }
        } label: {
            Group {
                switch purchasePhase {
                case .success:
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .heavy))
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                case .working:
                    ProgressView().tint(.white)
                        .transition(.opacity)
                case .idle:
                    Text(hasIntroOffer ? "Start your free trial" : "Continue")
                        .font(.custom("Nunito-ExtraBold", size: 17).weight(.heavy))
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: purchasePhase)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [Color(lightHex: "#FF9273", darkHex: "#D06A4B"),
                                 Color(lightHex: "#FF7A59", darkHex: "#B5503A")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            )
            .shadow(color: coral.opacity(0.35), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(SpringPressStyle(scale: 0.97))
        .disabled(isPurchasing)
    }

    /// The exact deal, in one quiet line right under the button.
    private var transparencyLine: some View {
        Group {
            if hasIntroOffer, let price = yearlyPriceString {
                Text("\(trialLengthText) free, then \(price)/year · cancel anytime")
            } else {
                Text("Cancel anytime")
            }
        }
        .font(.custom("Inter-Medium", size: 12).weight(.medium))
        .foregroundColor(T.textSec)
    }

    private var yearlyPriceString: String? {
        if let p = subs.products.first(where: { $0.id == "tempa_yearly" }) { return p.displayPrice }
        if let s = subs.simPlans.first(where: { $0.id == "tempa_yearly" }) { return s.price }
        return nil
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Restore") { restore() }
            Text("·")
            Button("Terms") { showTermsDoc = true }
            Text("·")
            Button("Privacy") { showPrivacyDoc = true }
        }
        .font(.custom("Inter-Medium", size: 12).weight(.semibold))
        .foregroundColor(T.textTer)
        .padding(.top, 12)
        .padding(.bottom, 26)
        .sheet(isPresented: $showTermsDoc) { TermsSheet() }
        .sheet(isPresented: $showPrivacyDoc) { PrivacyPolicySheet() }
    }

    // MARK: - Logic

    private func restore() {
        Task {
            do {
                try await subs.restorePurchases()
                if subs.isPro {
                    onPurchaseComplete()
                    dismiss()
                } else {
                    errorMessage = String(localized: "Nothing to restore — no purchases found on this Apple ID.", bundle: .appLanguage)
                    showError = true
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private var selectedProduct: Product? {
        subs.products.first { $0.id == selectedProductID }
    }

    /// If the pinned default didn't load, select the first plan that did —
    /// otherwise the CTA errors while a perfectly buyable card sits there.
    private func reconcileSelection() {
        guard !subs.isSimulating, !subs.products.isEmpty,
              !subs.products.contains(where: { $0.id == selectedProductID }) else { return }
        selectedProductID = subs.products.first(where: { $0.id != "tempa_weekly" })?.id ?? selectedProductID
    }

    private var hasIntroOffer: Bool {
        // "-force-trial YES": show the trial timeline regardless of what
        // StoreKit says, for reviewing the screen itself. Owner only.
        if OwnerMode.isActive && UserDefaults.standard.bool(forKey: "force-trial") { return true }
        // The owner's test cycle plays a brand-new user until the funnel is
        // completed once on this install (see RootView) — and a new user IS
        // trial-eligible, even though the owner's test Apple ID used the
        // intro offer up long ago. Only for plans that truly carry one.
        if OwnerMode.playingNewUser,
           selectedProduct?.subscription?.introductoryOffer != nil {
            return true
        }
        return subs.hasIntroOfferEligibility[selectedProductID] ?? false
    }

    /// Short card titles — the ASC display names ("Tempa Pro Yearly") are too
    /// wordy for the paywall, the whole screen already says it's Tempa Pro.
    private func planTitle(id: String, fallback: String) -> String {
        switch id {
        case "tempa_yearly": return String(localized: "Yearly", bundle: .appLanguage)
        case "tempa_monthly": return String(localized: "Monthly", bundle: .appLanguage)
        case "tempa_weekly": return String(localized: "Weekly", bundle: .appLanguage)
        default: return fallback
        }
    }

    private func periodLabel(_ product: Product) -> String {
        guard let p = product.subscription?.subscriptionPeriod else { return "" }
        switch p.unit {
        case .year: return String(localized: "year", bundle: .appLanguage)
        case .month: return String(localized: "month", bundle: .appLanguage)
        case .week: return String(localized: "week", bundle: .appLanguage)
        case .day: return String(localized: "day", bundle: .appLanguage)
        @unknown default: return ""
        }
    }

    /// The only figure on this screen we derive rather than read — and it is
    /// formatted by StoreKit's own style, so the currency and layout match the
    /// App Store exactly. A NumberFormatter would take the currency from the
    /// locale instead of from the buyer's storefront and could print the wrong
    /// symbol where the two disagree.
    private func monthlyEquivalent(_ product: Product) -> String? {
        guard let p = product.subscription?.subscriptionPeriod, p.unit == .year else { return nil }
        return (product.price / 12).formatted(product.priceFormatStyle)
    }

    // MARK: - Trial length (read from the App Store offer, never assumed)

    /// The introductory offer as configured in App Store Connect. Falls back to
    /// the yearly plan's offer so the timeline still reads correctly while a
    /// different card is selected.
    private var introOffer: Product.SubscriptionOffer? {
        selectedProduct?.subscription?.introductoryOffer
            ?? subs.products.first(where: { $0.id == "tempa_yearly" })?.subscription?.introductoryOffer
    }

    /// Trial length in days — drives the timeline and the reminder, so neither
    /// can drift from what Apple actually grants.
    private var trialDays: Int {
        guard let period = introOffer?.period else { return 3 }
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return period.value
        }
    }

    /// "3 days", "1 week" — the offer's own length, worded by the system in the
    /// app's language instead of hardcoded in nine translations.
    private var trialLengthText: String {
        var comps = DateComponents()
        if let period = introOffer?.period {
            switch period.unit {
            case .day: comps.day = period.value
            case .week: comps.weekOfMonth = period.value
            case .month: comps.month = period.value
            case .year: comps.year = period.value
            @unknown default: comps.day = period.value
            }
        } else {
            comps.day = 3   // no product loaded (dev simulation only)
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .weekOfMonth, .month, .year]
        var calendar = Calendar.current
        calendar.locale = AppLanguage.current.locale
        formatter.calendar = calendar
        return formatter.string(from: comps) ?? "\(comps.day ?? 3)"
    }

    private func purchaseSelected() async {
        AnalyticsService.shared.track(.paywallCTATapped,
                                      properties: ["product": selectedProductID,
                                                   "trial_ui": hasIntroOffer])
        isPurchasing = true
        withAnimation { purchasePhase = .working }
        // Capture NOW — a successful purchase flips eligibility off before the
        // celebration runs. wasTrial must not depend on the reminder toggle.
        pendingTrialReminder = hasIntroOffer && trialReminderOn
        let wasTrial = hasIntroOffer

        if subs.isSimulating {
            try? await Task.sleep(for: .seconds(1))
            subs.simulatePurchase()
            await finishPurchaseCelebration(wasTrial: wasTrial)
            return
        }

        guard let product = selectedProduct else {
            // Don't die silently — say why no sheet appeared, and kick another
            // load attempt so "try again" can actually succeed.
            errorMessage = String(localized: "The store isn't reachable yet. Give it a second and try again.", bundle: .appLanguage)
            showError = true
            resetPurchaseUI()
            Task { await subs.ensureProductsLoaded() }
            return
        }
        do {
            let tx = try await subs.purchase(product)
            #if DEBUG
            print("[Tempa] paywall purchase → \(tx != nil ? "new transaction" : "nil (cancelled / pending / already owned)"), isPro=\(subs.isPro)")
            #endif
            if tx != nil {
                await finishPurchaseCelebration(wasTrial: wasTrial)
                return
            }
            // No new transaction, but the Apple ID may already OWN an active
            // subscription — StoreKit shows "already subscribed" and reports
            // it as a cancellation. Real users never see a paywall while
            // subscribed; the owner's forced funnel does (god mode routes by
            // funnel state, not entitlements), and without this the funnel's
            // paywall is a dead end on a subscribed Apple ID.
            await subs.updatePurchasedProducts()
            if subs.isPro {
                await finishPurchaseCelebration(wasTrial: wasTrial, isNewPurchase: false)
                return
            }
            resetPurchaseUI()   // user cancelled the sheet
        } catch {
            #if DEBUG
            print("[Tempa] paywall purchase threw:", error)
            #endif
            errorMessage = error.localizedDescription
            showError = true
            resetPurchaseUI()
        }
    }

    /// Morph the CTA into a checkmark with a success haptic, then close.
    /// wasTrial is captured at CTA time — after the purchase StoreKit flips
    /// intro-offer eligibility off, so reading hasIntroOffer here would file
    /// a $0 trial as a paid Subscribe.
    /// isNewPurchase is false on the already-subscribed recovery path:
    /// routing back into the app is right, but reporting a conversion for a
    /// purchase made weeks ago would hand the ad platforms a fake sale.
    private func finishPurchaseCelebration(wasTrial: Bool, isNewPurchase: Bool = true) async {
        if isNewPurchase {
            var purchaseProps: [String: Any] = ["product": selectedProductID]
            if let product = selectedProduct {
                purchaseProps["price"] = NSDecimalNumber(decimal: product.price).doubleValue
                purchaseProps["currency"] = product.priceFormatStyle.currencyCode
            }
            AnalyticsService.shared.track(wasTrial ? .trialStarted : .subscriptionPurchased,
                                          properties: purchaseProps)
            if pendingTrialReminder { scheduleTrialReminder() }
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { purchasePhase = .success }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        try? await Task.sleep(for: .milliseconds(750))
        onPurchaseComplete()
        dismiss()
        isPurchasing = false
        purchasePhase = .idle
    }

    /// Day 2 of the 3-day trial — a real, gentle heads-up we promised on the
    /// toggle. Requires (or asks for) notification permission.
    private func scheduleTrialReminder() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Your free trial ends tomorrow", bundle: .appLanguage)
            content.body = String(localized: "If Tempa isn't for you, cancel in the App Store — no hard feelings.", bundle: .appLanguage)
            content.sound = .default
            let reminderDay = max(1, trialDays - 1)
            let fire = Calendar.current.date(byAdding: .day, value: reminderDay, to: Date())
                ?? Date().addingTimeInterval(TimeInterval(reminderDay) * 86_400)
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let request = UNNotificationRequest(
                identifier: "trial-ending-reminder",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            )
            center.add(request)
        }
    }

    private func resetPurchaseUI() {
        withAnimation { purchasePhase = .idle }
        isPurchasing = false
    }
}

#Preview {
    PaywallView(allowDismiss: true, onPurchaseComplete: {})
        .environment(SubscriptionManager.shared)
}
