import Combine
import Foundation

enum BriefTopic: String, CaseIterable, Identifiable {
    case today = "今日简报"
    case finance = "收支"
    case study = "学习"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .today: "text.badge.checkmark"
        case .finance: "creditcard"
        case .study: "book.closed"
        }
    }
}

enum AppNavigationAction: Equatable {
    case studyFocus
    case scheduleToday
    case newSchedule
    case financeRecords
    case assistantBrief
}

struct AppNavigationRequest: Identifiable {
    let id = UUID()
    let action: AppNavigationAction
    let studyTaskID: UUID?
    let scheduleDate: Date?
    let briefTopic: BriefTopic?
}

/// One event reaches both the tab container and the destination's existing view.
@MainActor
final class AppNavigationCenter: ObservableObject {
    static let shared = AppNavigationCenter()
    @Published private(set) var request: AppNavigationRequest?

    func open(_ action: AppNavigationAction, studyTaskID: UUID? = nil, scheduleDate: Date? = nil, briefTopic: BriefTopic? = nil) {
        request = AppNavigationRequest(action: action, studyTaskID: studyTaskID, scheduleDate: scheduleDate, briefTopic: briefTopic)
    }

    func openBrief(_ topic: BriefTopic) {
        open(.assistantBrief, briefTopic: topic)
    }
}
