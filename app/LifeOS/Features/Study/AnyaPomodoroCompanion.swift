import SwiftUI

enum AnyaPomodoroMood: Hashable {
    case ready
    case focus
    case paused
    case rest

    var line: String {
        switch self {
        case .ready: "小水獭准备好了，陪你从一个小目标开始。"
        case .focus: "小水獭陪你专注，一起把这件事做好。"
        case .paused: "先喘口气，小水獭在这里等你。"
        case .rest: "小水獭陪你休息，喝口水再出发。"
        }
    }

    fileprivate var companionMood: CompanionMood {
        switch self {
        case .ready: .ready
        case .focus: .focus
        case .paused: .paused
        case .rest: .rest
        }
    }
}

/// The timer keeps its existing four-state interface. The three-part character
/// reacts to mood changes and taps without replacing or fading the whole image.
struct AnyaPomodoroCompanion: View {
    let mood: AnyaPomodoroMood
    var reactionTrigger: Int = 0
    var onReact: (() -> Void)? = nil

    var body: some View {
        LayeredCompanionView(
            character: .anya,
            mood: mood.companionMood,
            reactionTrigger: reactionTrigger,
            onReact: onReact
        )
    }
}
