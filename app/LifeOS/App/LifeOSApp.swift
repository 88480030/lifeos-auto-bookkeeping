import Foundation
import SwiftUI
import SwiftData
import UserNotifications

@main
struct LifeOSApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try LifeOSModelContainer.make()
        } catch {
            fatalError("LifeOS 数据库初始化失败：\(error)")
        }

        UNUserNotificationCenter.current().delegate = AppNotificationDelegate.shared

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedPreviewData") {
            PreviewDataSeeder.seedIfNeeded(in: modelContainer)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(modelContainer)
    }
}
