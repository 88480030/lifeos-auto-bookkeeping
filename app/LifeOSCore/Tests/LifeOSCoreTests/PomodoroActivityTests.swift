import Foundation
import Testing
@testable import LifeOSCore

private let activityStart = Date(timeIntervalSince1970: 1_800_000_000)

@Test func idleTimerHasNoLiveActivity() {
    #expect(PomodoroActivitySnapshot(machine: PomodoroMachine(), timerID: "A", now: activityStart) == nil)
}

@Test func liveActivityUsesActualDeadlineAndTask() throws {
    var machine = PomodoroMachine()
    machine.startFocus(now: activityStart, taskTitle: String(repeating: "读", count: 100))
    let state = try #require(PomodoroActivitySnapshot(machine: machine, timerID: "A", now: activityStart.addingTimeInterval(90)))
    #expect(state.remainingSeconds == 1410)
    #expect(state.endAt == activityStart.addingTimeInterval(1500))
    #expect(state.startAt == activityStart)
    #expect(state.taskTitle.count == 80)
    #expect(state.round == 1 && state.rounds == 4)
}

@Test func liveActivityPauseAndResumeKeepProgressCorrect() throws {
    var machine = PomodoroMachine()
    machine.startFocus(now: activityStart)
    machine.pause(now: activityStart.addingTimeInterval(100))
    let paused = try #require(PomodoroActivitySnapshot(machine: machine, timerID: "A", now: activityStart.addingTimeInterval(500)))
    #expect(paused.isPaused && paused.remainingSeconds == 1400)
    machine.resume(now: activityStart.addingTimeInterval(500))
    let resumed = try #require(PomodoroActivitySnapshot(machine: machine, timerID: "A", now: activityStart.addingTimeInterval(550)))
    #expect(resumed.endAt == activityStart.addingTimeInterval(1900))
    #expect(resumed.startAt == activityStart.addingTimeInterval(400))
    #expect(resumed.remainingSeconds == 1350)
}

@Test func breakActivityKeepsCompletedRoundAndClearsFocusTitle() throws {
    var machine = PomodoroMachine(configuration: .init(focusMinutes: 1, shortBreakMinutes: 1, longBreakMinutes: 2, longBreakEvery: 2))
    machine.startFocus(now: activityStart, taskTitle: "阅读")
    _ = machine.tick(now: activityStart.addingTimeInterval(60))
    let short = try #require(PomodoroActivitySnapshot(machine: machine, timerID: "A", now: activityStart.addingTimeInterval(60)))
    #expect(short.phase == "shortBreak" && short.round == 1 && short.taskTitle.isEmpty)
    _ = machine.tick(now: activityStart.addingTimeInterval(120))
    machine.startFocus(now: activityStart.addingTimeInterval(180))
    _ = machine.tick(now: activityStart.addingTimeInterval(240))
    let long = try #require(PomodoroActivitySnapshot(machine: machine, timerID: "B", now: activityStart.addingTimeInterval(240)))
    #expect(long.phase == "longBreak" && long.round == 2 && long.durationSeconds == 120)
    _ = machine.tick(now: activityStart.addingTimeInterval(360))
    #expect(PomodoroActivitySnapshot(machine: machine, timerID: "B") == nil)
}

@Test func liveActivityRejectsStaleRepeatedAndWrongPhaseActions() {
    var machine = PomodoroMachine(configuration: .init(focusMinutes: 1))
    machine.startFocus(now: activityStart)
    #expect(PomodoroActivitySnapshot.acceptsAction(machine: machine, currentTimerID: "A", requestedTimerID: "A", phase: "focus", resume: false, now: activityStart))
    #expect(!PomodoroActivitySnapshot.acceptsAction(machine: machine, currentTimerID: "B", requestedTimerID: "A", phase: "focus", resume: false, now: activityStart))
    #expect(!PomodoroActivitySnapshot.acceptsAction(machine: machine, currentTimerID: "A", requestedTimerID: "A", phase: "focus", resume: false, now: activityStart.addingTimeInterval(60)))
    machine.pause(now: activityStart.addingTimeInterval(10))
    #expect(!PomodoroActivitySnapshot.acceptsAction(machine: machine, currentTimerID: "A", requestedTimerID: "A", phase: "focus", resume: false, now: activityStart.addingTimeInterval(20)))
    #expect(PomodoroActivitySnapshot.acceptsAction(machine: machine, currentTimerID: "A", requestedTimerID: "A", phase: "focus", resume: true, now: activityStart.addingTimeInterval(20)))
    machine.resume(now: activityStart.addingTimeInterval(20))
    _ = machine.tick(now: activityStart.addingTimeInterval(70))
    #expect(!PomodoroActivitySnapshot.acceptsAction(machine: machine, currentTimerID: "A", requestedTimerID: "A", phase: "focus", resume: false, now: activityStart.addingTimeInterval(70)))
}
