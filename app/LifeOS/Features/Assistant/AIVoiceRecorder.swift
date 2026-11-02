@preconcurrency import AVFoundation
import Combine
import Foundation
@preconcurrency import Speech

/// Live speech is transcribed on the device and never uploaded as audio.
@MainActor
final class AIVoiceRecorder: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var isPreparing = false
    @Published private(set) var isFinalizing = false
    @Published var error: String?

    private let engine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var sessionID = UUID()
    private var finishTask: Task<Void, Never>?

    func start() async {
        guard !isRecording, !isPreparing, !isFinalizing else { return }
        isPreparing = true
        defer { isPreparing = false }
        error = nil
        transcript = ""
        let authorization = await withCheckedContinuation { continuation in
            // Speech invokes this callback on its own queue. Do not inherit
            // the recorder's MainActor isolation into the Objective-C block.
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status)
            }
        }
        guard !Task.isCancelled else { return }
        guard authorization == .authorized else { error = "请在系统设置中允许语音识别后重试。"; return }
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "请在系统设置中允许麦克风后重试。"; return
        }
        guard !Task.isCancelled else { return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            error = "此设备暂不支持本机中文语音识别，请改用文字输入。"; return
        }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            recognitionRequest = request
            let token = UUID()
            sessionID = token
            recognitionTask = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, failure in
                let value = result?.bestTranscription.formattedString
                let final = result?.isFinal ?? false
                let hasFailure = failure != nil
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == token else { return }
                    if let value { self.transcript = value }
                    if hasFailure {
                        if self.isRecording { self.error = "语音识别中断，请检查后重试。"; self.stop() }
                        self.isFinalizing = false
                        self.finishTask?.cancel()
                    } else if final {
                        if self.isRecording { self.stop() }
                        self.isFinalizing = false
                        self.finishTask?.cancel()
                    }
                }
            }
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw AIVoiceError.noInput }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in request.append(buffer) }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            stop()
            sessionID = UUID()
            recognitionTask?.cancel()
            recognitionTask = nil
            self.error = "无法开始录音，请检查麦克风权限后重试。"
        }
    }

    func stop() {
        let wasRecording = isRecording
        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        isRecording = false
        if wasRecording {
            isFinalizing = true
            finishTask?.cancel()
            finishTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled, let self, self.isFinalizing else { return }
                self.isFinalizing = false
                self.recognitionTask?.cancel()
                self.recognitionTask = nil
                self.error = "语音识别未能完成，请检查已识别的文字。"
            }
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func cancel() {
        stop()
        sessionID = UUID()
        finishTask?.cancel()
        finishTask = nil
        isFinalizing = false
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}

private enum AIVoiceError: Error { case noInput }
