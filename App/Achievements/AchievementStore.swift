import Foundation
import SwiftData

@available(iOS 18, *)
@Model
final class AchievementRecord {
    #Unique<AchievementRecord>([\.achievementId])

    var achievementId: String
    var unlockedAt: Date

    init(achievementId: AchievementId, unlockedAt: Date = .now) {
        self.achievementId = achievementId.rawValue
        self.unlockedAt = unlockedAt
    }
}
