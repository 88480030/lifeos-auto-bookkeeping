import Foundation
import SwiftData

/// 数据模型容器工厂。App、测试与后续小组件统一从这里创建。
public enum LifeOSModelContainer {
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            MoneyTransaction.self,
            Budget.self,
            StudyTask.self,
            StudySession.self,
            ScheduleTask.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
