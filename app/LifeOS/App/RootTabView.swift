import Foundation
import SwiftUI
import SwiftData
import Combine

enum AppTab: String, CaseIterable, Hashable, Identifiable {
    case home
    case finance
    case study
    case assistant
    case schedule

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .finance: "记账"
        case .study: "学习"
        case .assistant: "情报"
        case .schedule: "日程"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .finance: "creditcard"
        case .study: "book"
        case .assistant: "sparkles"
        case .schedule: "calendar"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home: "house.fill"
        case .finance: "creditcard.fill"
        case .study: "book.fill"
        case .assistant: "sparkles"
        case .schedule: "calendar"
        }
    }
}

struct RootTabView: View {
    @Environment(\.modelContext) private var reminderContext
    @Environment(\.scenePhase) private var reminderScenePhase

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("lifeos.appearance") private var appearance = "system"
    @Namespace private var tabNamespace
    @State private var quickRequest: QuickCaptureRequest?
    @State private var selection: AppTab
    @State private var viewportRect: CGRect = .zero
    #if DEBUG
    @State private var didAutoPresentQuickCapture = false
    #endif

    init() {
        #if DEBUG
        // 仅用于开发期自动截图：simctl launch ... -tab finance
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-tab"),
           arguments.indices.contains(index + 1),
           let tab = AppTab(rawValue: arguments[index + 1]) {
            _selection = State(initialValue: tab)
            return
        }
        #endif
        _selection = State(initialValue: .home)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .accessibilityHidden(quickRequest != nil)
            bottomScrim
            customTabBar
                .padding(.horizontal, 18)
                .padding(.bottom, 4)
                .accessibilityHidden(quickRequest != nil)

            if let request = quickRequest {
                GeometryReader { proxy in
                    ZStack(alignment: .bottom) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { closeQuickCapture() }

                        QuickCaptureView(request: request, onClose: closeQuickCapture)
                            .accessibilityAddTraits(.isModal)
                            .accessibilityAction(.escape, closeQuickCapture)
                            .frame(height: min(720, proxy.size.height * 0.79))
                            .background(ArchiveTheme.paper)
                            .clipShape(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 22,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0,
                                    topTrailingRadius: 22,
                                    style: .continuous
                                )
                            )
                            .overlay(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 22,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: 0,
                                    topTrailingRadius: 22,
                                    style: .continuous
                                )
                                .strokeBorder(ArchiveTheme.ink, lineWidth: 2)
                            )
                            .shadow(color: Color.black.opacity(0.20), radius: 22, x: 0, y: -6)
                            .padding(.horizontal, 6)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                .zIndex(20)
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .background { WidgetSnapshotSyncView() }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: LifeOSViewportPreferenceKey.self, value: geometry.frame(in: .global))
            }
        }
        .onPreferenceChange(LifeOSViewportPreferenceKey.self) { viewportRect = $0 }
        .environment(\.lifeOSViewportRect, viewportRect)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "lifeos" else { return }
            switch url.host?.lowercased() {
            case "study": AppNavigationCenter.shared.open(.studyFocus)
            case "finance": AppNavigationCenter.shared.open(.financeRecords)
            case "schedule": AppNavigationCenter.shared.open(.scheduleToday)
            default: break
            }
        }
        .environment(\.dynamicTypeSize, verificationTypeSize)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .task {
            _ = await ScheduleNotificationManager.requestPermissionIfNeeded()
            await ScheduleNotificationManager.rescheduleAll(context: reminderContext)
        }
        .onChange(of: reminderScenePhase) { _, phase in
            // Flush before suspension as well as replenishing on return.
            Task { await ScheduleNotificationManager.rescheduleAll(context: reminderContext) }
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)
            .receive(on: RunLoop.main)) { _ in
            Task { await ScheduleNotificationManager.rescheduleAll(context: reminderContext) }
        }
        .onReceive(AppNavigationCenter.shared.$request) { request in
            guard let request else { return }
            switch request.action {
            case .studyFocus: selection = .study
            case .newSchedule, .scheduleToday: selection = .schedule
            case .financeRecords: selection = .finance
            case .assistantBrief: selection = .assistant
            }
        }
        .onReceive(QuickCaptureCenter.shared.$request) { request in
            guard let request else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                quickRequest = request
            }
            QuickCaptureCenter.shared.clear()
        }
        .onReceive(ReceiptCaptureCenter.shared.$request) { request in
            guard request != nil else { return }
            selection = .finance
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-openQuickCapture"), !didAutoPresentQuickCapture {
                didAutoPresentQuickCapture = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    QuickCaptureCenter.shared.present(amount: 28.5, note: "午餐", category: "餐饮")
                }
            }
            #endif
            if let pending = QuickCaptureCenter.shared.request {
                quickRequest = pending
                QuickCaptureCenter.shared.clear()
            }
        }
    }

    private func closeQuickCapture() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
            quickRequest = nil
        }
    }

    private var verificationTypeSize: DynamicTypeSize {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-largeText") { return .accessibility3 }
        #endif
        return dynamicTypeSize
    }

    private var scrimColor: Color {
        selection == .home ? ArchiveTheme.paper : AppTheme.background
    }

    /// 只覆盖底部悬浮栏及其下方区域，避免页面内容从胶囊四周透出来。
    private var bottomScrim: some View {
        LinearGradient(
            stops: [
                .init(color: scrimColor.opacity(0), location: 0.0),
                .init(color: scrimColor.opacity(0), location: 0.30),
                .init(color: scrimColor.opacity(0.88), location: 0.56),
                .init(color: scrimColor, location: 0.76)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity)
        .frame(height: 170)
        .allowsHitTesting(false)
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Content

    private var tabContent: some View {
        ZStack {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                HomeView(selectedTab: $selection, now: timeline.date)
                    .environment(\.lifeOSSurfaceVisible, selection == .home)
            }
                .opacity(selection == .home ? 1 : 0)
                .allowsHitTesting(selection == .home)
                .accessibilityHidden(selection != .home)

            FinanceRootView()
                .environment(\.lifeOSSurfaceVisible, selection == .finance)
                .opacity(selection == .finance ? 1 : 0)
                .allowsHitTesting(selection == .finance)
                .accessibilityHidden(selection != .finance)

            StudyRootView()
                .environment(\.lifeOSSurfaceVisible, selection == .study)
                .opacity(selection == .study ? 1 : 0)
                .allowsHitTesting(selection == .study)
                .accessibilityHidden(selection != .study)

            AssistantRootView()
                .environment(\.lifeOSSurfaceVisible, selection == .assistant)
                .opacity(selection == .assistant ? 1 : 0)
                .allowsHitTesting(selection == .assistant)
                .accessibilityHidden(selection != .assistant)

            ScheduleRootView()
                .environment(\.lifeOSSurfaceVisible, selection == .schedule)
                .opacity(selection == .schedule ? 1 : 0)
                .allowsHitTesting(selection == .schedule)
                .accessibilityHidden(selection != .schedule)
        }
    }

    // MARK: - Custom tab bar

    private var customTabBar: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                tabButton(for: tab)
            }

            Button {
                Haptics.tap()
                QuickCaptureCenter.shared.present()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(ArchiveTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(ArchiveTheme.gold))
                    .overlay(Circle().strokeBorder(ArchiveTheme.ink, lineWidth: 1.5))
                    .contentShape(Circle())
            }
            .buttonStyle(ArchivePressStyle())
            .accessibilityLabel("记一笔")
            .padding(.trailing, 2)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(ArchiveTheme.paperRaised)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(ArchiveTheme.ink, lineWidth: 1.6)
        }
        .shadow(
            color: ArchiveTheme.paperShadow(for: colorScheme),
            radius: 22,
            x: 0,
            y: 10
        )
    }

    private func tabButton(for tab: AppTab) -> some View {
        Button {
            guard selection != tab else { return }
            Haptics.select()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: selection == tab ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(height: 18)
                Text(tab.title)
                    .font(.caption2.weight(.bold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .lineLimit(1)
            }
            .foregroundStyle(
                selection == tab
                    ? ArchiveTheme.ink
                    : ArchiveTheme.inkMuted
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .padding(.vertical, 8)
            .background {
                if selection == tab {
                    Capsule(style: .continuous)
                        .fill(ArchiveTheme.mintWash)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(ArchiveTheme.ink.opacity(0.75), lineWidth: 1.1)
                        )
                        .matchedGeometryEffect(id: "tabSelection", in: tabNamespace)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
    }
}

private struct LifeOSViewportPreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
