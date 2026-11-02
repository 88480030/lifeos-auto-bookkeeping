import Foundation

@main
struct MotionSamples {
    static func main() throws {
        var samples: [[String: Any]] = []
        for character in [CompanionCharacter.anya, .mira] {
            var carry = CompanionReactionDelta()
            for _ in 0..<12 {
                let resumed = CompanionReactionDelta.sample(elapsed: 0, character: character, carry: carry)
                precondition(abs(resumed.headNod - carry.headNod) < 0.0001,
                             "Repeated taps must preserve the current nod position")
                precondition(abs(resumed.armAngle - carry.armAngle) < 0.0001,
                             "Repeated taps must preserve the current arm position")
                for step in 0...110 {
                    let response = CompanionReactionDelta.sample(elapsed: Double(step) / 100, character: character, carry: carry)
                    precondition(response.headAngle == 0, "A nod must not introduce head roll")
                    precondition(response.headNod >= 0 && response.headNod <= 5.0001, "Nod must stay attached to the neck")
                    precondition(abs(response.armAngle) <= 7.0001, "Arm reaction exceeds the joint budget")
                }
                carry = CompanionReactionDelta.sample(elapsed: 0.23, character: character, carry: carry)
            }
            for mood in [CompanionMood.ready, .focus, .paused, .rest] {
                let poses = (0...600).map {
                    CompanionPose.idle(mood, character: character, time: Double($0) / 10)
                }
                samples.append([
                    "character": character.rawValue,
                    "mood": mood.rawValue,
                    "minimumAngle": poses.map(\.headAngle).min()!,
                    "maximumAngle": poses.map(\.headAngle).max()!,
                    "minimumScale": poses.map(\.bodyScaleY).min()!,
                    "maximumScale": poses.map(\.bodyScaleY).max()!
                ])
            }
        }
        let data = try JSONSerialization.data(withJSONObject: samples, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
