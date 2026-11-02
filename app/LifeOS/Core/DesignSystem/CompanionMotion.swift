import Foundation

enum CompanionCharacter: String {
    case anya
    case mira

    var name: String { self == .anya ? "小水獭" : "小狐狸" }

    /// Counter-roll measured from the two iris centers in each shipped head.
    /// This levels the actual artwork, rather than assuming its canvas is level.
    var headAlignmentDegrees: Double { self == .anya ? -3.177473 : 3.821143 }
}

enum CompanionMood: String {
    case ready
    case focus
    case paused
    case rest

    var description: String {
        switch self {
        case .ready: "准备好了"
        case .focus: "专注中"
        case .paused: "已暂停，等你回来"
        case .rest: "休息中"
        }
    }
}

struct CompanionReactionDelta {
    var headAngle: Double = 0
    var headNod: CGFloat = 0
    var armAngle: Double = 0

    static let duration = 1.1

    static func sample(elapsed: TimeInterval, character: CompanionCharacter, carry: CompanionReactionDelta) -> CompanionReactionDelta {
        guard elapsed >= 0 && elapsed < duration else { return CompanionReactionDelta() }
        let progress = elapsed / duration
        let envelope = sin(.pi * progress)
        let settle = min(1, elapsed / 0.16)
        let freshWeight = settle * settle * (3 - 2 * settle)
        let carryWeight = 1 - freshWeight
        let amplitude = character == .anya ? 4.0 : 7.0
        return CompanionReactionDelta(
            headAngle: 0,
            headNod: CGFloat(envelope * envelope * 5) * CGFloat(freshWeight) + carry.headNod * CGFloat(carryWeight),
            armAngle: sin(progress * .pi * 4) * envelope * amplitude * freshWeight + carry.armAngle * carryWeight
        )
    }
}

struct CompanionPose {
    var headAngle: Double = 0
    var headNod: CGFloat = 0
    var armAngle: Double = 0
    var bodyScaleY: CGFloat = 1
    var bodyLift: CGFloat = 0

    static func settled(_ mood: CompanionMood, character: CompanionCharacter) -> CompanionPose {
        // State belongs in the hand pose and short response, not a bent neck.
        CompanionPose(headAngle: character.headAlignmentDegrees,
                      armAngle: mood == .rest ? -0.5 : 0)
    }

    static func idle(_ mood: CompanionMood, character: CompanionCharacter, time: Double) -> CompanionPose {
        var result = settled(mood, character: character)
        let breath = CGFloat((sin(time * 1.3) + 1) / 2)
        let calm: CGFloat = mood == .paused ? 0.25 : 1
        result.bodyScaleY = 1 + breath * 0.012 * calm
        result.bodyLift = -breath * 3 * calm
        switch mood {
        case .ready:
            result.headNod = CGFloat((sin(time * 1.1) + 1) / 2) * 1.5
            result.armAngle = sin(time * 1.25) * (character == .anya ? 1.8 : 2.2)
        case .focus:
            result.headNod = CGFloat((sin(time * 1.2) + 1) / 2) * 1.2
            result.armAngle = sin(time * 1.8) * (character == .anya ? 1.6 : 2)
        case .paused:
            break
        case .rest:
            result.armAngle += sin(time * 1.1) * 0.9
        }
        return result
    }

    func interpolated(to next: CompanionPose, progress: Double) -> CompanionPose {
        let fraction = CGFloat(progress)
        return CompanionPose(
            headAngle: headAngle + (next.headAngle - headAngle) * progress,
            headNod: headNod + (next.headNod - headNod) * fraction,
            armAngle: armAngle + (next.armAngle - armAngle) * progress,
            bodyScaleY: bodyScaleY + (next.bodyScaleY - bodyScaleY) * fraction,
            bodyLift: bodyLift + (next.bodyLift - bodyLift) * fraction
        )
    }
}

