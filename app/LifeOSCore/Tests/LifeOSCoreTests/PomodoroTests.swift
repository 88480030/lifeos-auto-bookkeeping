import Foundation
import Testing
@testable import LifeOSCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@Test func pomodoroStartPauseResumeAndComplete() throws {
    var machine = PomodoroMachine(
        configuration: PomodoroConfiguration(
            focusMinutes: 25,
            shortBreakMinutes: 5,
            longBreakMinutes: 15,
            longBreakEvery: 4
        )
    )

    machine.startFocus(now: t0, taskTitle: "阅读", subject: "阅读")
    #expect(machine.isRunning)
    #expect(machine.remainingSeconds(now: t0) == 25 * 60)

    machine.pause(now: t0.addingTimeInterval(100))
    #expect(machine.isPaused)
    #expect(machine.remainingSeconds(now: t0.addingTimeInterval(500)) == 25 * 60 - 100)

    machine.resume(now: t0.addingTimeInterval(500))
    #expect(machine.isRunning)
    #expect(machine.remainingSeconds(now: t0.addingTimeInterval(500)) == 25 * 60 - 100)

    let focusEnd = t0.addingTimeInterval(500 + 25 * 60 - 100)
    let event = machine.tick(now: focusEnd)

    guard case .focusCompleted(let completed) = event else {
        Issue.record("应该完成一次专注")
        return
    }
    #expect(completed.focusedSeconds == 25 * 60)
    #expect(completed.taskTitle == "阅读")
    #expect(machine.completedFocusSessions == 1)
    #expect(machine.phase == .shortBreak)
    #expect(machine.isRunning)

    let breakEnd = focusEnd.addingTimeInterval(5 * 60)
    let breakEvent = machine.tick(now: breakEnd)
    guard case .breakCompleted(let wasLong) = breakEvent else {
        Issue.record("应该完成短休息")
        return
    }
    #expect(wasLong == false)
    #expect(machine.phase == .focus)
    #expect(machine.isIdle)
    #expect(machine.completedFocusSessions == 1)
}

@Test func pomodoroFourthFocusStartsLongBreakAndResetsCycle() throws {
    var machine = PomodoroMachine(
        configuration: PomodoroConfiguration(
            focusMinutes: 25,
            shortBreakMinutes: 5,
            longBreakMinutes: 15,
            longBreakEvery: 2
        )
    )

    // 第一次专注 + 短休息
    machine.startFocus(now: t0, taskTitle: "A", subject: "英语")
    _ = machine.tick(now: t0.addingTimeInterval(25 * 60))
    #expect(machine.phase == .shortBreak)
    _ = machine.tick(now: t0.addingTimeInterval(30 * 60))
    #expect(machine.phase == .focus)

    // 第二次专注 → 长休息
    let secondStart = t0.addingTimeInterval(31 * 60)
    machine.startFocus(now: secondStart, taskTitle: "B", subject: "数学")
    _ = machine.tick(now: secondStart.addingTimeInterval(25 * 60))
    #expect(machine.completedFocusSessions == 2)
    #expect(machine.phase == .longBreak)

    let longBreakEnd = secondStart.addingTimeInterval(25 * 60 + 15 * 60)
    let event = machine.tick(now: longBreakEnd)
    guard case .breakCompleted(let wasLong) = event else {
        Issue.record("应该完成长休息")
        return
    }
    #expect(wasLong == true)
    #expect(machine.completedFocusSessions == 0)
    #expect(machine.isIdle)
}

@Test func pomodoroEarlyEndRecordsPartialDuration() throws {
    var machine = PomodoroMachine(configuration: PomodoroConfiguration(focusMinutes: 25))
    machine.startFocus(now: t0, taskTitle: "写作", subject: "写作")

    let event = machine.end(now: t0.addingTimeInterval(10 * 60))
    guard case .focusEndedEarly(let completed) = event else {
        Issue.record("应该记录提前结束的有效时长")
        return
    }
    #expect(completed.focusedSeconds == 10 * 60)
    #expect(machine.isIdle)
    #expect(machine.completedFocusSessions == 0)
}

@Test func pomodoroCatchesUpAfterBackground() throws {
    var machine = PomodoroMachine(
        configuration: PomodoroConfiguration(focusMinutes: 25, shortBreakMinutes: 5, longBreakEvery: 4)
    )
    machine.startFocus(now: t0, taskTitle: "阅读", subject: "阅读")

    // 模拟 App 在后台很久后回来：专注和短休息都已结束
    let focusEvent = machine.tick(now: t0.addingTimeInterval(60 * 60))
    guard case .focusCompleted = focusEvent else {
        Issue.record("应该补记完成的专注")
        return
    }
    #expect(machine.phase == .shortBreak)
    #expect(machine.isRunning)

    let breakEvent = machine.tick(now: t0.addingTimeInterval(60 * 60))
    guard case .breakCompleted = breakEvent else {
        Issue.record("应该补记完成的休息")
        return
    }
    #expect(machine.isIdle)
}

@Test func pomodoroStateCodableRoundTrip() throws {
    var machine = PomodoroMachine(configuration: PomodoroConfiguration(focusMinutes: 20))
    machine.startFocus(now: t0, taskTitle: "阅读", subject: "阅读")

    let data = try JSONEncoder().encode(machine)
    let decoded = try JSONDecoder().decode(PomodoroMachine.self, from: data)

    #expect(decoded.phase == machine.phase)
    #expect(decoded.state == .running)
    #expect(decoded.remainingSeconds(now: t0.addingTimeInterval(60)) == 19 * 60)
    #expect(decoded.taskTitle == "阅读")
}
