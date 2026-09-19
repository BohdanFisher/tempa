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
    /// "See other options" — the monthly-plan sheet. The purchase runs from
    /// inside it (spinner on its own button, Apple's payment sheet on top);
    /// on success the sheet closes before the paywall itself does.
    @State private var showOptions = false
    /// The day-before reminder is part of the offer, not an option: promised
    /// on the timeline, scheduled at purchase as a REAL local notification.
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

                // The hero scrolls on small phones; the offer panel stays put.
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroTitle
                            .padding(.top, 22)

                        if storeUnreachable {
                            // An honest state with a retry — never a silent
                            // dead end (simulation is DEBUG-only).
                            storeUnreachableCard
                                .padding(.top, 26)
                        } else if hasIntroOffer {
                            trialTimeline
                                .padding(.top, 30)
                                .staggerIn(1, baseDelay: 0.08)
                        } else {
                            benefitRail
                                .padding(.top, 26)
                                .staggerIn(1, baseDelay: 0.08)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }

                offerPanel
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
        .sheet(isPresented: $showOptions) {
            optionsSheet
                // Scrolls and can grow to full height, so the Continue button
                // stays reachable at every Dynamic Type size.
                .presentationDetents([.height(312), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .interactiveDismissDisabled(isPurchasing)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        ZStack {
            Text("TEMPA PRO")
                .font(.custom("Nunito-ExtraBold", size: 12).weight(.heavy))
                .tracking(2.4)
                .foregroundColor(coral)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(coral.opacity(0.12)))

            if allowDismiss {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(T.textSec)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(T.surface))
                            .tempaShadowSm()
                    }
                }
            }
        }
        .padding(.horizontal, 22)
    }

    // MARK: - Hero

    /// Trial-eligible: the trial explained day by day — the single
    /// highest-trust element a trial paywall can have. Otherwise (monthly
    /// picked, or the intro offer already used): what Tempa does.
    private var heroTitle: some View {
        Group {
            if hasIntroOffer {
                Text("Here's how your free trial works")
            } else {
                Text("Everything Tempa can do")
            }
        }
        .font(.custom("Nunito-ExtraBold", size: 28).weight(.heavy))
        .tracking(-0.56)
        .foregroundColor(T.text)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 6)
        .staggerIn(0)
    }

    private var storeUnreachable: Bool {
        subs.products.isEmpty && !subs.isSimulating
    }

    // MARK: - Benefits (non-trial hero)

    private var benefitRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            benefit("mic.fill", coral, "Speak your day — AI turns it into a plan")
            benefit("rectangle.stack.fill", teal, "One thing at a time, never a wall of tasks")
            benefit("timer", Cat.routine.ink, "Focus sessions with gentle comeback nudges")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benefit(_ icon: String, _ tint: Color, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(tint.opacity(0.14)))
            Text(text)
                .font(.custom("Inter-Medium", size: 15).weight(.medium))
                .foregroundColor(T.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Trial timeline (trial hero)

    /// One coral rail, white icons on it, a fading tail after the last day —
    /// the whole trial readable at a glance.
    private var trialTimeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            timelineRow(icon: "lock.open.fill", last: false,
                        title: Text("Today: your free trial starts"),
                        text: Text("Every feature unlocked — speak your day, let AI shrink big tasks into tiny steps, run focus sessions."))
            if trialDays >= 2 {
                timelineRow(icon: "bell.fill", last: false,
                            title: Text("Day \(trialDays - 1): a gentle reminder"),
                            text: Text("We'll send a notification before anything is charged. No surprises."))
            }
            timelineRow(icon: "star.fill", last: true,
                        title: Text("Day \(trialDays): trial ends"),
                        text: Text("You'll be charged on \(chargeDateText). Cancel anytime before — it takes two taps."))
        }
        .background(alignment: .topLeading) {
            Capsule()
                .fill(coral)
                .frame(width: 40)
                .mask(
                    LinearGradient(
                        stops: [.init(color: .black, location: 0),
                                .init(color: .black, location: 0.7),
                                .init(color: .black.opacity(0.22), location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        }
    }

    private func timelineRow(icon: String, last: Bool, title: Text, text: Text) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                title
                    .font(.custom("Nunito-ExtraBold", size: 17).weight(.heavy))
                    .foregroundColor(T.text)
                    .fixedSize(horizontal: false, vertical: true)
                text
                    .font(.custom("Inter-Medium", size: 14).weight(.medium))
                    .foregroundColor(T.textSec)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
            .padding(.bottom, last ? 10 : 26)

            Spacer(minLength: 0)
        }
    }

    /// The day the trial converts, in the app's language — "6 September",
    /// "6 вересня". Read from the offer's length, never assumed.
    private var chargeDateText: String {
        let date = Calendar.current.date(byAdding: .day, value: trialDays, to: Date()) ?? Date()
        return date.formatted(.dateTime.day().month(.wide).locale(AppLanguage.current.locale))
    }

    // MARK: - Offer panel (stays put while the hero scrolls)

    private var offerPanel: some View {
        VStack(spacing: 0) {
            transparencyLine

            ctaButton
                .padding(.top, 12)

            if !storeUnreachable {
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    showOptions = true
                } label: {
                    Text("See other options")
                        .font(.custom("Nunito-ExtraBold", size: 15).weight(.bold))
                        .foregroundColor(T.textSec)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                // A purchase in flight owns the screen — no second one from here.
                .disabled(isPurchasing)
            }

            footer
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(T.surface)
                .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - "Other options" sheet — the monthly plan, nothing else

    /// The main screen sells the yearly plan with its trial. This sheet is the
    /// one alternative: month to month, no trial, no discount. It never
    /// touches the selection itself — Continue does, on the way out.
    private var optionsSheet: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Text("Prefer to pay monthly?")
                    .font(.custom("Nunito-ExtraBold", size: 21).weight(.heavy))
                    .foregroundColor(T.text)
                    .multilineTextAlignment(.center)
                    .padding(.top, 28)

                monthlyCard
                    .padding(.top, 20)

                Spacer(minLength: 28)

                Button {
                    // Bought right here, without touching the visible
                    // selection — the screen behind keeps selling the
                    // yearly trial; only Apple's payment sheet appears.
                    AnalyticsService.shared.track(.paywallProductSelected, properties: ["product": "tempa_monthly"])
                    Task { await purchase("tempa_monthly") }
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
                            Text("Continue")
                                .font(.custom("Nunito-ExtraBold", size: 17).weight(.heavy))
                                .transition(.opacity)
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: purchasePhase)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Capsule().fill(T.primaryFill))
                }
                .buttonStyle(SpringPressStyle(scale: 0.97))
                .disabled(isPurchasing)

                Group {
                    if let price = monthlyPriceString {
                        Text("\(price)/month · cancel anytime")
                    } else {
                        Text("Cancel anytime")
                    }
                }
                .font(.custom("Inter-Medium", size: 12).weight(.medium))
                .foregroundColor(T.textSec)
                .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
        }
        .background(T.bg.ignoresSafeArea())
    }

    @ViewBuilder
    private var monthlyCard: some View {
        if let plan = subs.simPlans.first(where: { $0.id == "tempa_monthly" }), subs.isSimulating {
            planCard(title: planTitle(id: plan.id, fallback: plan.name),
                     price: plan.price,
                     sub: String(localized: "per \(plan.periodLabel)", bundle: .appLanguage),
                     detail: String(localized: "No free trial · no discount", bundle: .appLanguage))
        } else if let product = subs.products.first(where: { $0.id == "tempa_monthly" }) {
            planCard(title: planTitle(id: product.id, fallback: product.displayName),
                     price: product.displayPrice,
                     sub: String(localized: "per \(periodLabel(product))", bundle: .appLanguage),
                     detail: String(localized: "No free trial · no discount", bundle: .appLanguage))
        } else {
            storeUnreachableCard
        }
    }

    private var monthlyPriceString: String? {
        if let p = subs.products.first(where: { $0.id == "tempa_monthly" }) { return p.displayPrice }
        return subs.simPlans.first(where: { $0.id == "tempa_monthly" })?.price
    }

    // MARK: - Plan card (the sheet's single, already-chosen option)

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

    /// Drawn in the "picked" state: there is nothing else to pick, Continue
    /// buys exactly this.
    private func planCard(title: String, price: String, sub: String, detail: String) -> some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .stroke(coral, lineWidth: 2)
                    .frame(width: 24, height: 24)
                Circle().fill(coral).frame(width: 14, height: 14)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.custom("Nunito-ExtraBold", size: 16).weight(.heavy))
                    .foregroundColor(T.text)
                Text(detail)
                    .font(.custom("Inter-Medium", size: 12).weight(.medium))
                    .foregroundColor(T.textSec)
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
                .fill(coral.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(coral, lineWidth: 1.8)
        )
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button {
            Task { await purchase(selectedProductID) }
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
            .background(Capsule().fill(T.primaryFill))
            .opacity(storeUnreachable ? 0.5 : 1)
        }
        .buttonStyle(SpringPressStyle(scale: 0.97))
        // No product → no payment sheet; a live button would only count
        // phantom checkouts against a dead store.
        .disabled(isPurchasing || storeUnreachable)
    }

    /// The exact deal, in one quiet line above the button — always for the
    /// plan that is actually selected.
    private var transparencyLine: some View {
        Group {
            if hasIntroOffer, let price = yearlyPriceString {
                if let monthly = yearlyMonthlyEquivalent {
                    Text("\(trialLengthText) free, then \(price)/year · \(monthly)/mo")
                } else {
                    Text("\(trialLengthText) free, then \(price)/year · cancel anytime")
                }
            } else if selectedProductID == "tempa_monthly", let price = selectedPriceString {
                Text("\(price)/month · cancel anytime")
            } else if selectedProductID == "tempa_yearly", let price = selectedPriceString {
                Text("\(price)/year · cancel anytime")
            } else {
                Text("Cancel anytime")
            }
        }
        .font(.custom("Inter-Medium", size: 12).weight(.medium))
        .foregroundColor(T.textSec)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var yearlyPriceString: String? {
        if let p = subs.products.first(where: { $0.id == "tempa_yearly" }) { return p.displayPrice }
        if let s = subs.simPlans.first(where: { $0.id == "tempa_yearly" }) { return s.price }
        return nil
    }

    private var yearlyMonthlyEquivalent: String? {
        if let p = subs.products.first(where: { $0.id == "tempa_yearly" }) { return monthlyEquivalent(p) }
        return subs.simPlans.first(where: { $0.id == "tempa_yearly" })?.monthlyPrice
    }

    private var selectedPriceString: String? {
        if let p = selectedProduct { return p.displayPrice }
        return subs.simPlans.first(where: { $0.id == selectedProductID })?.price
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

    /// Whether the screen shows the trial offer — for the selected (yearly) plan.
    private var hasIntroOffer: Bool { hasIntroOffer(for: selectedProductID) }

    private func product(for id: String) -> Product? {
        subs.products.first { $0.id == id }
    }

    private func hasIntroOffer(for productID: String) -> Bool {
        // "-force-trial YES": show the trial timeline regardless of what
        // StoreKit says, for reviewing the screen itself. Owner only.
        if OwnerMode.isActive && UserDefaults.standard.bool(forKey: "force-trial") { return true }
        // The owner's test cycle plays a brand-new user until the funnel is
        // completed once on this install (see RootView) — and a new user IS
        // trial-eligible, even though the owner's test Apple ID used the
        // intro offer up long ago. Only for plans that truly carry one.
        if OwnerMode.playingNewUser,
           product(for: productID)?.subscription?.introductoryOffer != nil {
            return true
        }
        return subs.hasIntroOfferEligibility[productID] ?? false
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

    /// Buys one specific plan. Decoupled from the visible selection on
    /// purpose: the monthly plan is bought from the options sheet while the
    /// screen keeps showing the yearly trial offer.
    private func purchase(_ productID: String) async {
        guard !isPurchasing else { return }
        // Capture NOW — a successful purchase flips eligibility off before the
        // celebration runs.
        let wasTrial = hasIntroOffer(for: productID)
        #if DEBUG
        print("[Tempa] paywall purchase(\(productID)) trial=\(wasTrial)")
        #endif
        AnalyticsService.shared.track(.paywallCTATapped,
                                      properties: ["product": productID, "trial_ui": wasTrial])
        isPurchasing = true
        withAnimation { purchasePhase = .working }
        pendingTrialReminder = wasTrial

        if subs.isSimulating {
            try? await Task.sleep(for: .seconds(1))
            subs.simulatePurchase()
            await finishPurchaseCelebration(productID: productID, wasTrial: wasTrial, transaction: nil)
            return
        }

        guard let product = product(for: productID) else {
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
            if let tx {
                await finishPurchaseCelebration(productID: productID, wasTrial: wasTrial, transaction: tx)
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
                await finishPurchaseCelebration(productID: productID, wasTrial: wasTrial,
                                                transaction: nil, isNewPurchase: false)
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
    /// `transaction` is the verified StoreKit transaction of a NEW purchase —
    /// nil only for the dev simulation. Its environment is what lets the ad
    /// platforms ignore sandbox and Xcode purchases.
    private func finishPurchaseCelebration(productID: String, wasTrial: Bool,
                                           transaction: StoreKit.Transaction?, isNewPurchase: Bool = true) async {
        if isNewPurchase {
            var purchaseProps: [String: Any]
            // The transaction knows whether it was a free trial; the UI's
            // wasTrial is an eligibility guess from before the purchase.
            var isTrial = wasTrial
            if let transaction {
                isTrial = PurchaseSignals.isIntroductory(transaction)
                purchaseProps = PurchaseSignals.properties(for: transaction, product: product(for: productID))
            } else {
                purchaseProps = ["product": productID, "environment": "simulated"]
                if let product = product(for: productID) {
                    purchaseProps["price"] = NSDecimalNumber(decimal: product.price).doubleValue
                    purchaseProps["currency"] = product.priceFormatStyle.currencyCode
                }
            }
            AnalyticsService.shared.track(isTrial ? .trialStarted : .subscriptionPurchased,
                                          properties: purchaseProps)
            if pendingTrialReminder { scheduleTrialReminder() }
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { purchasePhase = .success }
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        try? await Task.sleep(for: .milliseconds(750))
        if showOptions {
            // Let the monthly sheet fully close before the paywall goes —
            // tearing down a presentation under a live child sheet is how
            // a purchased user ends up stuck on the paywall.
            showOptions = false
            try? await Task.sleep(for: .milliseconds(500))
        }
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
