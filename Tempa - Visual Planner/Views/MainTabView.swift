import SwiftUI
import CoreData
import Observation
import StoreKit   // requestReview lives here

// MARK: - 1. Таби

enum AppTab: Int, CaseIterable {
    case today = 0, ai = 1, focus = 2, settings = 3

    var title: String {
        switch self {
        case .today: String(localized: "Home", bundle: .appLanguage)
        case .ai: String(localized: "AI", bundle: .appLanguage)
        case .focus: String(localized: "Focus", bundle: .appLanguage)
        case .settings: String(localized: "Settings", bundle: .appLanguage)
        }
    }

    var icon: String {
        switch self {
        case .today: "house"
        case .ai: "sparkles"
        case .focus: "flame"
        case .settings: "gearshape"
        }
    }

    var iconSelected: String {
        switch self {
        case .today: "house.fill"
        case .ai: "sparkles"
        case .focus: "flame.fill"
        case .settings: "gearshape.fill"
        }
    }
}

// MARK: - 2. Router (deep-links, push notifications)

@MainActor @Observable
final class AppRouter {
    static let shared = AppRouter()
    var selectedTab: AppTab = .today
    /// Set to ask the Focus tab to start a session for a specific task.
    var focusRequest: FocusRequest?
    /// Set to ask the Today tab to open the add-task sheet (e.g. from Welcome Back).
    var addTaskRequest: UUID?
    /// The day Home is showing (its week strip can move off today). A task
    /// created with "+" while Home is in front is planned for that day.
    var homeDay: Date?
    private init() {}
}

/// A request to begin a focus session for a task (drives the Focus screen's
/// auto-start and its category-specific title, e.g. "Work Time").
struct FocusRequest: Equatable {
    let id = UUID()
    let category: String
    let minutes: Int
    let title: String
}

// MARK: - 3. Main Tab View

struct MainTabView: View {
    @State private var router = AppRouter.shared
    @State private var selectedTab: AppTab = AppRouter.shared.selectedTab
    @State private var review = ReviewPrompt.shared
    @State private var showingAddTask = false
    /// What the system bar itself has selected (iOS 26+). Only ever `.add`
    /// for the blink of an eye — see `glassTabs`.
    @State private var slot: TabSlot = .screen(AppRouter.shared.selectedTab)
    /// Where the system bar keeps its separate round slot, in window
    /// coordinates — the "+" is centred on it.
    @State private var addSlotFrame: CGRect?
    /// iOS supplies and localizes the whole dialog — we pass no text at all.
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                glassTabs
            } else {
                classicTabs
            }
        }
        // Sheets and pickers opened from any tab inherit the brand tint.
        .tint(T.primary)
        .fullScreenCover(isPresented: $showingAddTask) {
            AddTaskSheet()
        }
        .onChange(of: selectedTab) { old, new in
            if old != new {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            router.selectedTab = new
            if slot != .screen(new) { slot = .screen(new) }
        }
        .onChange(of: router.selectedTab) { _, new in
            if selectedTab != new { selectedTab = new }
        }
        .onChange(of: router.addTaskRequest) { _, req in
            // e.g. Welcome Back's "Plan something small" → open the add-task sheet.
            guard req != nil else { return }
            router.addTaskRequest = nil   // consume
            showingAddTask = true
        }
        // First task ever created → ask for a rating, once.
        .onChange(of: review.shouldAsk) { _, ask in
            if ask { askForReview() }
        }
        // The task may have been created just before the app was backgrounded
        // (or created while a sheet was still up) — catch it on the way back.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && review.shouldAsk { askForReview() }
        }
    }

    // MARK: Tab bars

    /// iOS 26 and later: the system's own Liquid Glass bar — see-through,
    /// with the glass lens that can be dragged from one screen to the next.
    /// What the system bar can hold: one of the screens, or the empty slot
    /// that makes room for the "+".
    private enum TabSlot: Hashable {
        case screen(AppTab)
        case add
    }

    /// The "+" stays OUR button — the same 54 pt coral round one the classic
    /// bar has, to the right of the menu. The system only makes room for it:
    /// an empty tab in the slot it keeps apart from the capsule (the one
    /// Search lives in elsewhere) shortens the menu, the slot's own glass
    /// disc is switched off (`TabBarSlotHider`), and the button sits in its
    /// place. Should the slot itself ever get chosen (VoiceOver, a keyboard),
    /// it does what the button does and hands the selection straight back.
    /// (The bar has to be TOLD to go back — it switches on its own, and a
    /// binding that merely refuses the change leaves it parked on an empty
    /// screen.)
    @available(iOS 26.0, *)
    private var glassTabs: some View {
        TabView(selection: Binding(
            get: { slot },
            set: { new in
                switch new {
                case .screen(let tab):
                    slot = new
                    selectedTab = tab
                case .add:
                    showingAddTask = true
                    slot = .add
                    DispatchQueue.main.async { slot = .screen(selectedTab) }
                }
            }
        )) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Tab(value: TabSlot.screen(tab)) {
                    screen(for: tab)
                } label: {
                    Label {
                        Text(tab.title)
                    } icon: {
                        Image(systemName: selectedTab == tab ? tab.iconSelected : tab.icon)
                    }
                }
            }
            Tab(value: TabSlot.add, role: .search) {
                T.bg.ignoresSafeArea()
            } label: {
                Label {
                    Text("New task")
                } icon: {
                    Image(uiImage: Self.emptyIcon)
                }
            }
        }
        .background(TabBarSlotHider(slotFrame: $addSlotFrame))
        .overlay {
            // A layer the size of the screen (its coordinates are the
            // window's), with the button centred on the system's slot —
            // wherever this device and this iOS put it.
            GeometryReader { geo in
                let side = Self.glassBarHeight
                let slot = addSlotFrame ?? CGRect(x: geo.size.width - Self.glassBarMargin - side,
                                                  y: geo.size.height - Self.glassBarMargin - side,
                                                  width: side, height: side)
                TempaAddButton(isAdding: showingAddTask, size: TempaTabBar.height) {
                    showingAddTask = true
                }
                .position(x: slot.midX, y: slot.midY)
            }
            .ignoresSafeArea()
        }
    }

    /// The system bar's measures on iPhone (iOS 26) — a 62 pt capsule, 21 pt
    /// in from the sides and up from the bottom of the screen. Only a
    /// fallback: the slot's real frame comes from the bar itself.
    private static let glassBarHeight: CGFloat = 62
    private static let glassBarMargin: CGFloat = 21

    /// Nothing to draw in the slot. It still has to be an image: with none,
    /// the Search role brings its magnifying glass.
    private static let emptyIcon: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        .image { _ in }
        .withRenderingMode(.alwaysOriginal)

    /// iOS 17–18 have no Liquid Glass: the system bar is hidden and our own
    /// compact capsule floats in its place. TabView stays for what it's good
    /// at — each screen keeps its state while another one is in front.
    private var classicTabs: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                screen(for: tab)
                    .toolbar(.hidden, for: .tabBar)
                    .tag(tab)
            }
        }
        .overlay(alignment: .bottom) {
            TempaTabBar(selection: $selectedTab, isAdding: showingAddTask) {
                showingAddTask = true
            }
            // The bar stays where it is when a keyboard comes up.
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    /// Let the add-task sheet finish dismissing before the system dialog
    /// appears — a prompt sliding in over a closing sheet reads as a glitch,
    /// and Apple asks that it never interrupt a flow.
    private func askForReview() {
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard review.shouldAsk, scenePhase == .active else { return }
            requestReview()
            review.markAsked()
        }
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .today:    TodayView()
        case .ai:       AIView()
        case .focus:    FocusView()
        case .settings: ProfileView()
        }
    }
}

// MARK: - 4. Tab bar

/// The bar for systems WITHOUT Liquid Glass (iOS 17–18): a compact floating
/// capsule with the four screens, and the "+" as its own round button to the
/// right of it. The page fades out under it instead of being cut off by an
/// opaque strip. iOS 26 and later use the system bar (see `glassTabs`).
struct TempaTabBar: View {
    @Binding var selection: AppTab
    let isAdding: Bool
    let onAdd: () -> Void
    @Namespace private var pillNS

    static let height: CGFloat = 54
    /// Room a scrolling screen leaves under its last row. The system bar
    /// (iOS 26+) already insets the content; our floating capsule doesn't.
    static var contentClearance: CGFloat {
        if #available(iOS 26.0, *) { return 28 }
        return 110
    }
    private static var idleInk: Color {
        if #available(iOS 26.0, *) { return T.textSec }
        return T.textTer
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, 5)
            .frame(height: Self.height)
            .modifier(TabBarSurface())

            addButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 6)
        .background { pageFade }
    }

    /// Glass needs something to show through it; a solid capsule needs the
    /// page to end softly behind it.
    @ViewBuilder
    private var pageFade: some View {
        if #available(iOS 26.0, *) {
            EmptyView()
        } else {
            LinearGradient(colors: [T.bg.opacity(0), T.bg.opacity(0.94), T.bg],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            guard !isSelected else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { selection = tab }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: isSelected ? tab.iconSelected : tab.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(height: 20)
                Text(tab.title)
                    .font(.custom(T.fontHeader, size: 10).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            // On glass the page moves behind the labels — they need more ink.
            .foregroundColor(isSelected ? T.primary : Self.idleInk)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height - 10)
            .background {
                if isSelected {
                    Capsule()
                        .fill(T.primary.opacity(0.12))
                        .matchedGeometryEffect(id: "tabPill", in: pillNS)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var addButton: some View {
        TempaAddButton(isAdding: isAdding, size: Self.height, action: onAdd)
    }
}

/// The create-task button: a plain round "+", filled like every other filled
/// button in the app. One and the same next to either bar.
struct TempaAddButton: View {
    let isAdding: Bool
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                // Quarter-turn into a "×" while the add sheet is up.
                .rotationEffect(.degrees(isAdding ? 45 : 0))
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isAdding)
                .frame(width: size, height: size)
                .background(Circle().fill(T.primaryFill))
                .tempaShadow()
        }
        .buttonStyle(SpringPressStyle(scale: 0.88))
        .accessibilityLabel(Text("New task"))
    }
}

/// The system bar draws a glass disc in the slot it keeps apart from the
/// capsule. Ours stays empty — the "+" is our own button — so the disc is
/// switched off, and its frame is reported so the button can sit exactly
/// there. No private names involved: the bar's direct children are the long
/// capsule and that one near-square view; the square one is the slot. If a
/// future iOS arranges things differently nothing breaks — the disc simply
/// stays visible as a thin glass rim around the button.
struct TabBarSlotHider: UIViewRepresentable {
    @Binding var slotFrame: CGRect?

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        probe.onFrame = { frame in
            if slotFrame != frame { slotFrame = frame }
        }
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.applySoon()
    }

    final class Probe: UIView {
        var onFrame: ((CGRect) -> Void)?
        private var observer: NSObjectProtocol?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // The bar builds itself over the first moments, and rebuilds
            // when the app comes back — look again each time.
            for delay in [0.0, 0.3, 1.0, 3.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.apply() }
            }
            if observer == nil {
                observer = NotificationCenter.default.addObserver(
                    forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.applySoon() }
                }
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        func applySoon() {
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        private func apply() {
            guard let window, let bar = Self.tabBar(in: window) else { return }
            for view in bar.subviews {
                let size = view.bounds.size
                guard size.width > 20, size.width < size.height * 1.3 else { continue }
                view.alpha = 0
                view.isUserInteractionEnabled = false
                onFrame?(view.convert(view.bounds, to: nil))
            }
        }

        private static func tabBar(in view: UIView) -> UITabBar? {
            if let bar = view as? UITabBar { return bar }
            for sub in view.subviews {
                if let bar = tabBar(in: sub) { return bar }
            }
            return nil
        }
    }
}

/// The capsule's material: Liquid Glass where the system has it.
private struct TabBarSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(Capsule().fill(T.surface))
                .overlay(Capsule().strokeBorder(Color.tempaShadowTint.opacity(0.06), lineWidth: 1))
                .tempaShadow()
        }
    }
}

#Preview {
    MainTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environment(SettingsStore(context: PersistenceController.preview.container.viewContext))
        .environment(SubscriptionManager.shared)
}
