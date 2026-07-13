import SwiftUI
import StoreKit

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

    // Bright coral in light mode; a deeper, calmer coral in dark mode (the bright
    // one glares on a dark screen). White cards/button read well on both.
    private let coral = Color(lightHex: "#FF7A59", darkHex: "#B5503A")
    private let cardInk = Color(hex: "#2E2A26")   // dark text on the selected white card
    private let cardSub = Color(hex: "#8A837C")   // muted subtitle on the white card
    private let teal = Color(hex: "#3FC09A")      // BEST VALUE badge

    var body: some View {
        ZStack {
            coral.ignoresSafeArea()

            // One faint, perfectly round circle whose centre orbits along a lightly
            // flattened (oblate) path — the oval orbit makes the motion clearly visible.
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 0.05)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate * 0.6   // ≈10s per orbit
                    let a = 55.0, b = 38.0                                        // lightly flattened orbit
                    Circle()
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 380)
                        .position(x: geo.size.width - 40 + a * cos(t),
                                  y: geo.size.height - 70 + b * sin(t))
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: 0) {
                    Text("TEMPA PRO")
                        .font(.custom("Nunito-ExtraBold", size: 13).weight(.heavy))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.72))
                        .padding(.bottom, 14)

                    Text("Less noise.\nMore you.")
                        .font(.custom("Nunito-ExtraBold", size: 40).weight(.heavy))
                        .tracking(-0.8)
                        .foregroundColor(.white)
                        .lineSpacing(0)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Unlock all of Tempa free for 3 days. Keep it for less than a coffee a month.")
                        .font(.custom("Inter-Medium", size: 16).weight(.medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineSpacing(4)
                        .padding(.top, 16)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 18)

                Spacer(minLength: 24)

                planCards
                    .padding(.horizontal, 18)

                ctaButton
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .staggerIn(2, baseDelay: 0.1)

                footer
            }
        }
        .alert("Error", isPresented: $showError) { Button("OK") {} } message: { Text(errorMessage) }
        .task {
            // Retry StoreKit when the paywall appears — recovers from a failed
            // cold-start load and swaps simulated plans for real products.
            await subs.ensureProductsLoaded()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            if allowDismiss {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.18)))
                }
            }
            Spacer()
            Button { restore() } label: {
                Text("Restore")
                    .font(.custom("Nunito-ExtraBold", size: 14).weight(.bold))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 22)
    }

    // MARK: - Plan cards

    private var planCards: some View {
        VStack(spacing: 12) {
            if subs.isSimulating {
                ForEach(Array(subs.simPlans.filter { $0.id != "tempa_weekly" }.enumerated()), id: \.element.id) { i, plan in
                    planCard(
                        id: plan.id,
                        title: plan.name,
                        isYearly: plan.id == "tempa_yearly",
                        price: plan.price,
                        sub: plan.monthlyPrice.map { "\($0)/mo" } ?? "per \(plan.periodLabel)",
                        detail: plan.id == "tempa_yearly" ? "3 days free, then billed yearly" : nil
                    )
                    .staggerIn(i, baseDelay: 0.1)
                }
            } else {
                ForEach(Array(subs.products.filter { $0.id != "tempa_weekly" }.enumerated()), id: \.element.id) { i, product in
                    let yearly = product.id == "tempa_yearly"
                    planCard(
                        id: product.id,
                        title: product.displayName,
                        isYearly: yearly,
                        price: product.displayPrice,
                        sub: yearly ? (monthlyEquivalent(product).map { "\($0)/mo" } ?? "per year") : "per \(periodLabel(product))",
                        detail: yearly ? "3 days free, then billed yearly" : nil
                    )
                    .staggerIn(i, baseDelay: 0.1)
                }
            }
        }
    }

    private func planCard(id: String, title: String, isYearly: Bool, price: String, sub: String, detail: String?) -> some View {
        let picked = selectedProductID == id
        return Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            selectedProductID = id
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(picked ? coral : .clear).frame(width: 26, height: 26)
                    Circle().stroke(picked ? .clear : Color.white.opacity(0.65), lineWidth: 2).frame(width: 26, height: 26)
                    if picked {
                        Circle().fill(.white).frame(width: 10, height: 10)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.6), value: picked)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.custom("Nunito-ExtraBold", size: 17).weight(.heavy))
                            .foregroundColor(picked ? cardInk : .white)
                        if isYearly { bestValueBadge }
                    }
                    if let detail {
                        Text(detail)
                            .font(.custom("Inter-Medium", size: 12).weight(.medium))
                            .foregroundColor(picked ? cardSub : .white.opacity(0.8))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(price)
                        .font(.custom("Nunito-ExtraBold", size: 17).weight(.heavy))
                        .foregroundColor(picked ? cardInk : .white)
                    Text(sub)
                        .font(.custom("Inter-Medium", size: 11).weight(.semibold))
                        .foregroundColor(picked ? cardSub : .white.opacity(0.8))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(picked ? Color.white : Color.white.opacity(0.16))
            )
            .shadow(color: .black.opacity(picked ? 0.12 : 0), radius: 14, x: 0, y: 8)
            .scaleEffect(picked ? 1.02 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: picked)
        }
        .buttonStyle(SpringPressStyle(scale: 0.98))
    }

    private var bestValueBadge: some View {
        Text("BEST VALUE")
            .font(.custom("Nunito-ExtraBold", size: 10).weight(.heavy))
            .tracking(0.6)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(teal))
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
                    ProgressView().tint(coral)
                        .transition(.opacity)
                case .idle:
                    Text(hasIntroOffer ? "Start 3-day free trial" : "Continue")
                        .font(.custom("Nunito-ExtraBold", size: 17).weight(.heavy))
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: purchasePhase)
            .foregroundColor(coral)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(Capsule().fill(.white))
            .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(SpringPressStyle(scale: 0.97))
        .disabled(isPurchasing)
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
        .foregroundColor(.white.opacity(0.6))
        .padding(.top, 14)
        .padding(.bottom, 30)
        .sheet(isPresented: $showTermsDoc) { TermsSheet() }
        .sheet(isPresented: $showPrivacyDoc) { PrivacyPolicySheet() }
    }

    // MARK: - Logic

    private func restore() {
        Task {
            try? await subs.restorePurchases()
            if subs.isPro { onPurchaseComplete(); dismiss() }
        }
    }

    private var selectedProduct: Product? {
        subs.products.first { $0.id == selectedProductID }
    }

    private var hasIntroOffer: Bool {
        subs.hasIntroOfferEligibility[selectedProductID] ?? false
    }

    private func periodLabel(_ product: Product) -> String {
        guard let p = product.subscription?.subscriptionPeriod else { return "" }
        switch p.unit {
        case .year: return "year"
        case .month: return "month"
        case .week: return "week"
        case .day: return "day"
        @unknown default: return ""
        }
    }

    private func monthlyEquivalent(_ product: Product) -> String? {
        guard let p = product.subscription?.subscriptionPeriod, p.unit == .year else { return nil }
        let mo = product.price / 12
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.locale = product.priceFormatStyle.locale
        return fmt.string(from: mo as NSDecimalNumber)
    }

    private func purchaseSelected() async {
        isPurchasing = true
        withAnimation { purchasePhase = .working }

        if subs.isSimulating {
            try? await Task.sleep(for: .seconds(1))
            subs.simulatePurchase()
            await finishPurchaseCelebration()
            return
        }

        guard let product = selectedProduct else {
            // Don't die silently — say why no sheet appeared.
            errorMessage = "The store isn't reachable yet. Give it a second and try again."
            showError = true
            resetPurchaseUI()
            return
        }
        do {
            let tx = try await subs.purchase(product)
            if tx != nil {
                await finishPurchaseCelebration()
                return
            }
            resetPurchaseUI()   // user cancelled the sheet
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            resetPurchaseUI()
        }
    }

    /// Morph the CTA into a checkmark with a success haptic, then close.
    private func finishPurchaseCelebration() async {
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

    private func resetPurchaseUI() {
        withAnimation { purchasePhase = .idle }
        isPurchasing = false
    }
}

#Preview {
    PaywallView(allowDismiss: true, onPurchaseComplete: {})
        .environment(SubscriptionManager.shared)
}
