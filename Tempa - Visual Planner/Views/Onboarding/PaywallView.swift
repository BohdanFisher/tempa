import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(SubscriptionManager.self) private var subs
    @Environment(\.dismiss) private var dismiss

    let allowDismiss: Bool
    let onPurchaseComplete: () -> Void

    @State private var selectedProductID = "tempa_yearly"
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(lightHex: "#FFE9E1", darkHex: "#2C1F18"), T.bg],
                startPoint: .top, endPoint: .init(x: 0.5, y: 0.38)
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    if allowDismiss {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(T.text)
                                .frame(width: 34, height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(T.surface.opacity(0.7))
                                )
                        }
                    }
                    Spacer()
                    Button {
                        Task {
                            try? await subs.restorePurchases()
                            if subs.isPro { onPurchaseComplete(); dismiss() }
                        }
                    } label: {
                        Text("Restore")
                            .font(.custom(T.fontHeader, size: 13).weight(.bold))
                            .foregroundColor(T.text)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)

                ScrollView {
                    VStack(spacing: 0) {
                        heroSection
                        valueBullets
                        planCards
                        trialTimeline
                        Spacer().frame(height: 12)
                    }
                    .padding(.horizontal, 22)
                }

                ctaSection
            }
        }
        .alert("Error", isPresented: $showError) { Button("OK") {} } message: { Text(errorMessage) }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 0) {
            SonarPulse(coreSize: 28, ringSize: 46, maxScale: 2.0, coreShadow: T.primary.opacity(0.5))
                .padding(.top, 18)
                .padding(.bottom, 18)

            Text("Your tempo\nstarts now.")
                .font(.custom(T.fontHeader, size: 38).weight(.heavy))
                .tracking(-0.8)
                .foregroundColor(T.text)
                .multilineTextAlignment(.center)
                .lineSpacing(-2)

            if hasIntroOffer {
                Text("3 days free. Then \(selectedPrice)/year. Cancel anytime.")
                    .font(.custom(T.fontBody, size: 15).weight(.medium))
                    .foregroundColor(T.textSec)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }
        }
        .padding(.bottom, 22)
    }

    // MARK: - Value Bullets

    private var valueBullets: some View {
        VStack(spacing: 14) {
            valueBullet(icon: "sparkles", cat: Cat.personal, text: "Start anything in one tap — AI breaks it down for you")
            valueBullet(icon: "clock", cat: Cat.work, text: "Never lose track of time — Now/Next keeps you oriented")
            valueBullet(icon: "heart", cat: Cat.health, text: "A plan that forgives you — no streaks, no shame")
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(T.surface.opacity(0.6))
        )
        .padding(.bottom, 20)
    }

    private func valueBullet(icon: String, cat: CatColors, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(cat.ink)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(cat.bg)
                )
            Text(text)
                .font(.custom(T.fontHeader, size: 14).weight(.semibold))
                .foregroundColor(T.text)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
    }

    // MARK: - Plan Cards

    private var planCards: some View {
        VStack(spacing: 8) {
            if subs.isSimulating {
                ForEach(subs.simPlans) { plan in
                    simPlanRow(plan)
                }
            } else {
                ForEach(subs.products) { product in
                    planRow(product)
                }
            }
        }
        .padding(.bottom, 18)
    }

    private func planRow(_ product: Product) -> some View {
        let picked = selectedProductID == product.id
        let isYearly = product.id == "tempa_yearly"

        return Button {
            selectedProductID = product.id
        } label: {
            HStack(spacing: 14) {
                radioCircle(picked: picked)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(product.displayName)
                            .font(.custom(T.fontHeader, size: 16).weight(.heavy))
                            .foregroundColor(T.text)
                        if isYearly {
                            bestValueBadge
                        }
                    }
                    if isYearly {
                        Text("3 days free, then billed yearly")
                            .font(.custom(T.fontBody, size: 12).weight(.medium))
                            .foregroundColor(T.textSec)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(product.displayPrice)
                        .font(.custom(T.fontHeader, size: 17).weight(.heavy))
                        .foregroundColor(T.text)
                    if isYearly, let mo = monthlyEquivalent(product) {
                        Text("\(mo)/mo")
                            .font(.custom(T.fontBody, size: 11).weight(.semibold))
                            .foregroundColor(T.textSec)
                    } else {
                        Text("per \(periodLabel(product))")
                            .font(.custom(T.fontBody, size: 11).weight(.semibold))
                            .foregroundColor(T.textSec)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(picked ? T.surface : T.surface.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(picked ? T.primary : .clear, lineWidth: 2)
            )
            .shadow(
                color: picked ? Color(hex: "#FF7A59").opacity(0.18) : .clear,
                radius: 14, x: 0, y: 12
            )
        }
        .buttonStyle(.plain)
    }

    private func simPlanRow(_ plan: SubscriptionManager.SimPlan) -> some View {
        let picked = selectedProductID == plan.id
        let isYearly = plan.id == "tempa_yearly"

        return Button {
            selectedProductID = plan.id
        } label: {
            HStack(spacing: 14) {
                radioCircle(picked: picked)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(plan.name)
                            .font(.custom(T.fontHeader, size: 16).weight(.heavy))
                            .foregroundColor(T.text)
                        if isYearly {
                            bestValueBadge
                        }
                    }
                    if isYearly {
                        Text("3 days free, then billed yearly")
                            .font(.custom(T.fontBody, size: 12).weight(.medium))
                            .foregroundColor(T.textSec)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(plan.price)
                        .font(.custom(T.fontHeader, size: 17).weight(.heavy))
                        .foregroundColor(T.text)
                    if let mo = plan.monthlyPrice {
                        Text("\(mo)/mo")
                            .font(.custom(T.fontBody, size: 11).weight(.semibold))
                            .foregroundColor(T.textSec)
                    } else {
                        Text("per \(plan.periodLabel)")
                            .font(.custom(T.fontBody, size: 11).weight(.semibold))
                            .foregroundColor(T.textSec)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(picked ? T.surface : T.surface.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(picked ? T.primary : .clear, lineWidth: 2)
            )
            .shadow(
                color: picked ? Color(hex: "#FF7A59").opacity(0.18) : .clear,
                radius: 14, x: 0, y: 12
            )
        }
        .buttonStyle(.plain)
    }

    private func radioCircle(picked: Bool) -> some View {
        ZStack {
            Circle()
                .fill(picked ? T.primary : .clear)
                .frame(width: 24, height: 24)
            if !picked {
                Circle()
                    .stroke(T.textTer, lineWidth: 2)
                    .frame(width: 24, height: 24)
            }
            if picked {
                Circle()
                    .fill(.white)
                    .frame(width: 10, height: 10)
            }
        }
    }

    private var bestValueBadge: some View {
        Text("BEST VALUE")
            .font(.custom(T.fontHeader, size: 10).weight(.heavy))
            .tracking(0.6)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(T.secondary)
            )
    }

    // MARK: - Trial Timeline

    private var trialTimeline: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Circle().fill(T.secondary).frame(width: 12, height: 12)
                Rectangle().fill(T.secondary.opacity(0.4)).frame(width: 2, height: 20)
                Circle().fill(T.warning).frame(width: 12, height: 12)
                Rectangle().fill(T.textTer.opacity(0.4)).frame(width: 2, height: 20)
                Circle().stroke(T.textTer, lineWidth: 2).frame(width: 12, height: 12)
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 12) {
                trialStep(day: "Today", text: "Full access to Tempa.")
                trialStep(day: "Day 2", text: "We email a reminder so you don't forget.")
                trialStep(day: "Day 3", text: "Trial ends. Cancel anytime before.")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(T.surface.opacity(0.55))
        )
    }

    private func trialStep(day: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(day)
                .font(.custom(T.fontHeader, size: 13).weight(.heavy))
                .foregroundColor(T.text)
            Text(text)
                .font(.custom(T.fontBody, size: 12).weight(.medium))
                .foregroundColor(T.textSec)
        }
    }

    // MARK: - Sticky CTA

    private var ctaSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await purchaseSelected() }
            } label: {
                Group {
                    if isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text(hasIntroOffer ? "Start 3-Day Free Trial" : "Continue")
                            .font(.custom(T.fontHeader, size: 18).weight(.heavy))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(T.primary)
                )
                .shadow(color: Color(hex: "#FF7A59").opacity(0.4), radius: 15, x: 0, y: 14)
            }
            .disabled(isPurchasing)

            HStack(spacing: 14) {
                Button("Restore") {
                    Task {
                        try? await subs.restorePurchases()
                        if subs.isPro { onPurchaseComplete(); dismiss() }
                    }
                }
                Text("·").foregroundColor(T.textSec)
                Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Text("·").foregroundColor(T.textSec)
                Link("Privacy", destination: URL(string: "https://www.apple.com/privacy/")!)
            }
            .font(.custom(T.fontBody, size: 11).weight(.semibold))
            .foregroundColor(T.textSec)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 50)
        .background(
            LinearGradient(
                colors: [T.bg.opacity(0), T.bg.opacity(0.95)],
                startPoint: .top, endPoint: .init(x: 0.5, y: 0.3)
            )
        )
    }

    // MARK: - Helpers

    private var selectedProduct: Product? {
        subs.products.first { $0.id == selectedProductID }
    }

    private var hasIntroOffer: Bool {
        subs.hasIntroOfferEligibility[selectedProductID] ?? false
    }

    private var selectedPrice: String {
        if subs.isSimulating {
            return subs.simPlans.first { $0.id == selectedProductID }?.price ?? "€29.99"
        }
        return selectedProduct?.displayPrice ?? ""
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

        if subs.isSimulating {
            try? await Task.sleep(for: .seconds(1))
            subs.simulatePurchase()
            onPurchaseComplete()
            dismiss()
            isPurchasing = false
            return
        }

        guard let product = selectedProduct else {
            isPurchasing = false
            return
        }
        do {
            let tx = try await subs.purchase(product)
            if tx != nil { onPurchaseComplete(); dismiss() }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isPurchasing = false
    }
}

#Preview {
    PaywallView(allowDismiss: true, onPurchaseComplete: {})
        .environment(SubscriptionManager.shared)
}
