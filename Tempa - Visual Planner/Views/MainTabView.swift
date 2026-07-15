import SwiftUI
import CoreData
import Observation

// MARK: - 1. Таби

enum AppTab: Int, CaseIterable {
    case today = 0, calendar = 1, focus = 2, me = 3, settings = 4

    var title: String {
        switch self {
        case .today: String(localized: "Home")
        case .calendar: String(localized: "Calendar")
        case .focus: String(localized: "Focus")
        case .me: String(localized: "Me")
        case .settings: String(localized: "Settings")
        }
    }

    var icon: String {
        switch self {
        case .today: "house"
        case .calendar: "calendar"
        case .focus: "flame"
        case .me: "person"
        case .settings: "gearshape"
        }
    }

    var iconSelected: String {
        switch self {
        case .today: "house.fill"
        case .calendar: "calendar"
        case .focus: "flame.fill"
        case .me: "person.fill"
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

    init() {
        let accent   = UIColor(T.primary)
        let inactive = UIColor(T.textTer)
        let bgColor  = UIColor(T.bg)

        let font = UIFont(name: T.fontHeader, size: 10) ?? .systemFont(ofSize: 10, weight: .medium)
        let fontBold = UIFont(name: T.fontHeader, size: 10) ?? .systemFont(ofSize: 10, weight: .semibold)

        let a = UITabBarAppearance()
        a.configureWithOpaqueBackground()
        a.backgroundColor = bgColor
        a.shadowColor = UIColor.black.withAlphaComponent(0.06)

        a.stackedLayoutAppearance.normal.iconColor = inactive
        a.stackedLayoutAppearance.normal.titleTextAttributes =
            [.foregroundColor: inactive, .font: font]
        a.stackedLayoutAppearance.selected.iconColor = accent
        a.stackedLayoutAppearance.selected.titleTextAttributes =
            [.foregroundColor: accent, .font: fontBold]

        UITabBar.appearance().standardAppearance   = a
        UITabBar.appearance().scrollEdgeAppearance  = a
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                screen(for: tab)
                    .tabItem {
                        Label {
                            Text(tab.title)
                        } icon: {
                            Image(systemName: selectedTab == tab ? tab.iconSelected : tab.icon)
                        }
                    }
                    .tag(tab)
            }
        }
        .tint(T.primary)
        .onChange(of: selectedTab) { old, new in
            if old != new {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            router.selectedTab = new
        }
        .onChange(of: router.selectedTab) { _, new in
            if selectedTab != new { selectedTab = new }
        }
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .today:    TodayView()
        case .calendar: CalendarView()
        case .focus:    FocusView()
        case .me:       MeView()
        case .settings: ProfileView()
        }
    }
}

#Preview {
    MainTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environment(SettingsStore(context: PersistenceController.preview.container.viewContext))
        .environment(SubscriptionManager.shared)
}
