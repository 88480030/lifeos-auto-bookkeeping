import Foundation

/// Offline protocol checks. All responses and account data below are synthetic.
private actor SyntheticTransport {
    enum Mode { case permitted, forbidden, malformed, repeated, unauthorized, oversizedReasoning, settings, failsAfterTool, plan, history, direct, deletion, planAfterReads, studyEdits, topicReplacement, topicRead }
    let mode: Mode
    private(set) var requests: [Data] = []

    init(_ mode: Mode) { self.mode = mode }

    func send(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request.httpBody ?? Data())
        let status = mode == .unauthorized || (mode == .failsAfterTool && requests.count > 1) ? 401 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        if status == 401 { return (Data("sensitive fake server body".utf8), response) }
        let first = requests.count == 1 || mode == .repeated || (mode == .planAfterReads && requests.count <= 4)
        let payload: [String: Any]
        if mode == .topicRead && first {
            let args = #"{"category":"study","start_date":"2031-04-01","end_date":"2031-04-24","title_contains":"写作练习","limit":100}"#
            payload = ["choices": [["message": ["content": NSNull(), "tool_calls": [["id":"read-topic", "type":"function", "function":["name":"read_lifeos_records", "arguments":args]]]]]]]
        } else if mode == .topicReplacement && first {
            let args = #"{"start_date":"2031-04-01","end_date":"2031-04-03","title_contains":"写作练习","daily_count":1,"items":[{"title":"写作练习：景点一整篇","subject":"写作练习","date":"2031-04-01","minutes":30},{"title":"写作练习：景点二整篇","subject":"写作练习","date":"2031-04-02","minutes":30}]}"#
            payload = ["choices": [["message": ["content": NSNull(), "tool_calls": [["id":"replace-1", "type":"function", "function":["name":"replace_lifeos_study_topic", "arguments": args]]]]]]]
        } else if mode == .studyEdits && first {
            payload = ["choices": [["message": ["content": NSNull(), "tool_calls": [["id":"edit-1", "type":"function", "function":["name":"edit_lifeos_study_tasks", "arguments": #"{"items":[{"date":"2026-11-21","old_title":"错误第18章","new_title":"第2—12章复盘"}]}"#]]]]]]]
        } else if mode == .deletion && first {
            payload = ["choices": [["message": ["content": NSNull(), "tool_calls": [["id":"delete-1", "type":"function", "function":["name":"request_lifeos_day_deletion", "arguments": #"{"date":"2026-10-28","categories":["finance","study","schedule"]}"#]]]]]]]
        } else if mode == .direct {
            payload = ["choices": [["message": ["content": "测试回复"]]]]
        } else if mode == .history && first {
            payload = ["choices": [["message": ["content": NSNull(), "tool_calls": [["id":"history-1", "type":"function", "function":["name":"search_lifeos_conversation", "arguments": #"{"query":"英语","offset":0}"#]]]]]]]
        } else if mode == .plan || (mode == .planAfterReads && requests.count == 5) {
            let arguments = #"{"items":[{"kind":"study","title":"单词","subject":"英语","date":"2031-04-03","minutes":25},{"kind":"schedule","title":"英语角","date":"2031-04-03","time":"19:00","minutes":60}]}"#
            payload = ["choices": [["message": ["content": NSNull(), "tool_calls": [["id":"plan-1", "type":"function", "function":["name":"propose_lifeos_plan", "arguments":arguments]]]]]]]
        } else if first {
            let category = mode == .forbidden ? "schedule" : mode == .settings ? "settings" : "finance"
            let limit = mode == .malformed ? 999 : 2
            let arguments = "{\"category\":\"\(category)\",\"start_date\":\"2026-01-01\",\"end_date\":\"2026-02-01\",\"limit\":\(limit),\"offset\":1}"
            let reasoning = mode == .oversizedReasoning ? String(repeating: "x", count: 100_001) : "synthetic reasoning for current tool round"
            payload = ["choices": [["message": ["content": NSNull(), "reasoning_content": reasoning, "tool_calls": [["id": "test-\(requests.count)", "type": "function", "function": ["name": "read_lifeos_records", "arguments": arguments]]]]]]]
        } else {
            payload = ["choices": [["message": ["content": "测试回复"]]]]
        }
        return (try JSONSerialization.data(withJSONObject: payload), response)
    }
}

@MainActor private final class ReadRecorder {
    var calls: [AIReadToolRequest] = []
    var events: [AIReadToolEvent] = []
    func read(_ request: AIReadToolRequest) async throws -> String {
        calls.append(request)
        return "{\"records\":[{\"title\":\"合成测试\"}]}"
    }
}

@main struct AIServiceQA {
    @MainActor static func main() async throws {
        let good = try AIConnectionStore.completionsURL(from: "https://example.invalid/v1/")
        precondition(good.absoluteString == "https://example.invalid/v1/chat/completions")
        let complete = try AIConnectionStore.completionsURL(from: "https://example.invalid/v1/chat/completions")
        precondition(complete == good)
        for input in ["http://example.invalid/v1", "https://user:pass@example.invalid/v1", "https://example.invalid/v1?token=fake", "https://example.invalid/v1#frag"] {
            do { _ = try AIConnectionStore.completionsURL(from: input); fatalError("invalid URL accepted") }
            catch is AIConnectionError {}
        }
        let recallFixture: [AIServiceMessage] = [
            .init(role: .user, content: "我的英语每天晚上学25分钟，周末不用安排"),
            .init(role: .assistant, content: "好的，我会按这个要求安排"),
            .init(role: .user, content: "今天午饭吃什么")
        ]
        precondition(AIHistoryRetrieval.search("我之前说的英文学习安排是什么？", in: recallFixture).contains { $0.content.contains("周末") }, "Natural-language recall failed")

        precondition(AIHistoryRetrieval.search("量子物理", in: recallFixture).isEmpty)
        precondition(AIHistoryRetrieval.search("", in: recallFixture).count == 3)
        let recalledPage = try JSONSerialization.jsonObject(with: Data(AIHistoryRetrieval.payload("英语", history: recallFixture).utf8)) as! [String: Any]
        let recalledRows = recalledPage["matches"] as! [[String: String]]
        precondition(recalledRows.first?["adjacentContext"]?.contains("按这个要求") == true)
        let beyond = try AIHistoryRetrieval.payload("", history: recallFixture, offset: Int.max)
        let beyondJSON = try JSONSerialization.jsonObject(with: Data(beyond.utf8)) as! [String: Any]
        precondition(beyondJSON["hasMore"] as? Bool == false)

        let credentials = AIServiceCredentials(endpoint: good, model: "synthetic-model", apiKey: "synthetic-key")
        let messages = [AIServiceMessage(role: .user, content: "查询测试账目")]

        do {
            let transport = SyntheticTransport(.direct)
            let service = OpenAICompatibleService(transport: { try await transport.send($0) })
            _ = try await service.respondWithTools(messages: [.init(role: .user, content: "我之前说的英文学习安排是什么？")], credentials: credentials,
                allowedCategories: [], conversationHistory: recallFixture, toolHandler: nil)
            let captured = await transport.requests
            precondition(captured.count == 1)
            let body = try JSONSerialization.jsonObject(with: captured[0]) as! [String: Any]
            let wire = body["messages"] as! [[String: Any]]
            precondition(wire.contains { ($0["content"] as? String)?.contains("周末不用安排") == true }, "Recall must work even without a model tool call")
        }

        // Automatic recall must not depend on a special "before / remember"
        // phrase, and must retrieve the user's source rather than invent a fact.
        do {
            let transport = SyntheticTransport(.direct)
            let service = OpenAICompatibleService(transport: { try await transport.send($0) })
            _ = try await service.respondWithTools(messages: [.init(role: .user, content: "睡眠安排")], credentials: credentials,
                allowedCategories: [], conversationHistory: [
                    .init(role: .user, content: "[2026-10-29T07:00:00+08:00] 我每天23:20睡觉"),
                    .init(role: .assistant, content: "今天午饭可以吃面条")
                ], toolHandler: nil)
            let captured = await transport.requests
            precondition(captured.count == 1)
            let body = try JSONSerialization.jsonObject(with: captured[0]) as! [String: Any]
            let wire = body["messages"] as! [[String: Any]]
            precondition(wire.contains { row in
                guard let content = row["content"] as? String else { return false }
                return content.contains("history-0") && content.contains("23:20睡觉")
            }, "Automatic topic recall must include its real source without a history trigger or model tool call")
        }

        do {
            let transport = SyntheticTransport(.direct)
            let service = OpenAICompatibleService(transport: { try await transport.send($0) })
            _ = try await service.respondWithTools(messages: [.init(role: .user, content: "4月1日到4月23日只替换写作练习，每天一篇")],
                credentials: credentials, allowedCategories: [.study], allowStudyEdits: true, toolHandler: { _ in "{}" })
            let request = await transport.requests[0]
            let body = try JSONSerialization.jsonObject(with: request) as! [String: Any]
            let tools = body["tools"] as! [[String: Any]]
            let names = tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
            precondition(names.contains("replace_lifeos_study_topic"), "AI cannot selectively replace one study topic: required tool is missing")
        }

        do {
            let transport = SyntheticTransport(.topicReplacement)
            let service = OpenAICompatibleService(transport: { try await transport.send($0) })
            let reply = try await service.respondWithTools(messages: [.init(role: .user, content: "把写作练习改成每天一篇")],
                credentials: credentials, allowedCategories: [.study], allowStudyEdits: true, toolHandler: { _ in "{}" })
            precondition(reply.topicReplacement?.items.count == 2 && reply.topicReplacement?.titleContains == "写作练习")
            do {
                let wrongRange = SyntheticTransport(.topicReplacement)
                let wrongService = OpenAICompatibleService(transport: { try await wrongRange.send($0) })
                _ = try await wrongService.respondWithTools(messages: [.init(role: .user, content: "把4.1到4.23的写作练习换成每天一篇")],
                    credentials: credentials, allowedCategories: [.study], allowStudyEdits: true, toolHandler: { _ in "{}" })
                fatalError("partial date range must not replace a larger user-requested range")
            } catch AIServiceError.invalidResponse {}
            do {
                let other = SyntheticTransport(.topicReplacement)
                let otherService = OpenAICompatibleService(transport: { try await other.send($0) })
                _ = try await otherService.respondWithTools(messages: [.init(role: .user, content: "修改英语")],
                    credentials: credentials, allowedCategories: [.study], allowStudyEdits: true, toolHandler: { _ in "{}" })
                fatalError("model-proposed topic not explicitly named by user must be rejected")
            } catch AIServiceError.invalidResponse {}
        }

        do {
            let transport = SyntheticTransport(.topicRead)
            let recorder = ReadRecorder()
            let service = OpenAICompatibleService(transport: { try await transport.send($0) })
            _ = try await service.respondWithTools(messages: [.init(role: .user, content: "查看写作练习计划")],
                credentials: credentials, allowedCategories: [.study], toolHandler: { try await recorder.read($0) })
            precondition(recorder.calls.first?.titleContains == "写作练习", "topic filter must reach the real read handler")
        }
        for enabled in [false, true] {
            let transport = SyntheticTransport(.deletion)
            let service = OpenAICompatibleService(transport: { try await transport.send($0) })
            let reply = try await service.respondWithTools(messages: [.init(role: .user, content: "删除10月28日的记录")], credentials: credentials,
                allowedCategories: [.finance], allowDayDeletion: enabled, toolHandler: { _ in fatalError("Deletion must never use read handler") })
            precondition((reply.deletion != nil) == enabled)
            if enabled { precondition(reply.deletion?.date == "2026-10-28" && reply.proposal == nil && reply.text.contains("尚未删除")) }
        }

        do {
            let transport = SyntheticTransport(.planAfterReads)
            let service = OpenAICompatibleService(transport: { try await transport.send($0) })
            let reply = try await service.respondWithTools(messages: messages, credentials: credentials, allowedCategories: [.finance], allowPlanProposal: true) { _ in "{\"records\":[]}" }
            precondition(reply.proposal?.items.count == 2 && reply.events.count == 4, "Final planning round must still allow the write proposal after four reads")
        }

        for enabled in [false, true] {
            let transport = SyntheticTransport(.studyEdits)
            let service = OpenAICompatibleService(transport: { try await transport.send($0) })
            let result = try await service.respondWithTools(messages: messages, credentials: credentials,
                allowedCategories: [.study], allowStudyEdits: enabled, toolHandler: { _ in "{}" })
            precondition((result.studyEdits != nil) == enabled)
            precondition(result.deletion == nil && result.proposal == nil)
        }

        for mode in [SyntheticTransport.Mode.permitted, .forbidden, .malformed] {
            let transport = SyntheticTransport(mode)
            let service = OpenAICompatibleService(transport: { request in try await transport.send(request) })
            let recorder = ReadRecorder()
            let reply = try await service.respondWithTools(messages: messages, credentials: credentials, allowedCategories: [.finance]) { request in
                try await recorder.read(request)
            }
            precondition(reply.text == "测试回复" && reply.events.count == 1)
            if mode == .permitted {
                precondition(recorder.calls.count == 1 && reply.events[0].succeeded)
                precondition(recorder.calls[0].category == .finance && recorder.calls[0].limit == 2 && recorder.calls[0].offset == 1)
                precondition(recorder.calls[0].start != nil && recorder.calls[0].end != nil)
            } else {
                precondition(recorder.calls.isEmpty && !reply.events[0].succeeded)
            }
            let captured = await transport.requests
            precondition(captured.count == 2)
            let second = try JSONSerialization.jsonObject(with: captured[1]) as! [String: Any]
            let wire = second["messages"] as! [[String: Any]]
            precondition(wire.contains { ($0["role"] as? String) == "tool" && ($0["tool_call_id"] as? String) == "test-1" })
            let callMessage = wire.first { ($0["role"] as? String) == "assistant" && $0["tool_calls"] != nil }!
            precondition(callMessage["content"] is NSNull)
            precondition(callMessage["reasoning_content"] as? String == "synthetic reasoning for current tool round")
            precondition(second["thinking"] == nil)
        }

        do {
            let transport = SyntheticTransport(.history)
            let service = OpenAICompatibleService(transport: { try await transport.send($0) })
            let reply = try await service.respondWithTools(messages: messages, credentials: credentials,
                allowedCategories: [], conversationHistory: [.init(role: .user, content: "我想学英语"), .init(role: .user, content: "无关内容")], toolHandler: nil)
            precondition(reply.events.count == 1 && reply.events[0].succeeded)
            let requests = await transport.requests
            precondition(requests.count == 2)
            let second = try JSONSerialization.jsonObject(with: requests[1]) as! [String: Any]
            let wire = second["messages"] as! [[String: Any]]
            let text = wire.first { $0["role"] as? String == "tool" }!["content"] as! String
            precondition(text.contains("我想学英语") && !text.contains("无关内容"))
            let tools = second["tools"] as! [[String: Any]]
            precondition(tools.count == 1)
        }

        // The same request must retain all ten photos in their selected order.
        do {
            let transport = SyntheticTransport(.direct)
            let service = OpenAICompatibleService(transport: { try await transport.send($0) })
            let images = (0..<10).map { "data:image/jpeg;base64," + Data("photo-\($0)".utf8).base64EncodedString() }
            _ = try await service.respondWithTools(messages: [.init(role: .user, content: "比较这十张照片", imageDataURLs: images)], credentials: credentials,
                allowedCategories: [], toolHandler: nil)
            let captured = await transport.requests
            let body = try JSONSerialization.jsonObject(with: captured[0]) as! [String: Any]
            let wire = body["messages"] as! [[String: Any]]
            let parts = wire[0]["content"] as! [[String: Any]]
            let sent = parts.compactMap { ($0["image_url"] as? [String: String])?["url"] }
            precondition(sent == images && parts.count == 11)
        }

        // A photo message uses the provider's content-part format and survives
        // a tool round trip; no real photo or network request is used here.
        do {
            let transport = SyntheticTransport(.permitted)
            let service = OpenAICompatibleService(transport: { request in try await transport.send(request) })
            let recorder = ReadRecorder()
            let image = "data:image/jpeg;base64,YQ=="
            let multimodal = [AIServiceMessage(role: .user, content: "看图", imageDataURLs: [image])]
            let result = try await service.respondWithTools(messages: multimodal, credentials: credentials,
                allowedCategories: [.finance]) { request in try await recorder.read(request) }
            precondition(result.text == "测试回复")
            for request in await transport.requests {
                let json = try JSONSerialization.jsonObject(with: request) as! [String: Any]
                let wire = json["messages"] as! [[String: Any]]
                let user = wire.first { $0["role"] as? String == "user" }!
                let parts = user["content"] as! [[String: Any]]
                precondition(parts.count == 2 && parts[0]["text"] as? String == "看图")
                precondition(parts[1]["type"] as? String == "image_url")
                precondition((parts[1]["image_url"] as? [String: String])?["url"] == image)
            }
            do {
                _ = try await service.respond(messages: [.init(role: .system, content: "bad", imageDataURLs: [image]), .init(role: .user, content: "hello")], credentials: credentials)
                fatalError("image in non-user message accepted")
            } catch AIServiceError.tooMuchData {}
            do {
                _ = try await service.respond(messages: [.init(role: .user, content: "x", imageDataURLs: ["https://example.invalid/private.jpg"])], credentials: credentials)
                fatalError("remote image unexpectedly accepted")
            } catch AIServiceError.tooMuchData {}
        }

        // The provider may request settings even when that category was not offered.
        // The execution-side guard must still deny it before the handler runs.
        for allowed in [false, true] {
            let transport = SyntheticTransport(.settings)
            let service = OpenAICompatibleService(transport: { request in try await transport.send(request) })
            let recorder = ReadRecorder()
            let categories: Set<AIReadCategory> = allowed ? [.settings] : [.finance]
            let reply = try await service.respondWithTools(messages: messages, credentials: credentials, allowedCategories: categories) { request in
                try await recorder.read(request)
            }
            precondition(reply.events.count == 1 && reply.events[0].category == .settings)
            if allowed {
                precondition(recorder.calls.count == 1 && recorder.calls[0].category == .settings && reply.events[0].succeeded)
            } else {
                precondition(recorder.calls.isEmpty && !reply.events[0].succeeded)
            }
            let captured = await transport.requests
            let second = try JSONSerialization.jsonObject(with: captured[1]) as! [String: Any]
            let wire = second["messages"] as! [[String: Any]]
            let toolResult = wire.first { ($0["role"] as? String) == "tool" }?["content"] as? String
            precondition(allowed ? toolResult?.contains("合成测试") == true : toolResult?.contains("未获用户授权") == true)
        }

        // Reporting must survive a later provider failure: the first request asks
        // for finance, the local tool runs, and the second request returns 401.
        do {
            let transport = SyntheticTransport(.failsAfterTool)
            let service = OpenAICompatibleService(transport: { request in try await transport.send(request) })
            let recorder = ReadRecorder()
            do {
                _ = try await service.respondWithTools(messages: messages, credentials: credentials,
                    allowedCategories: [.finance], onToolEvent: { recorder.events.append($0) }) { request in
                        try await recorder.read(request)
                    }
                fatalError("subsequent HTTP 401 accepted")
            } catch AIServiceError.serverStatus(let status) {
                precondition(status == 401)
            }
            precondition(recorder.calls.count == 1 && recorder.events.count == 1)
            precondition(recorder.events[0].category == .finance && recorder.events[0].succeeded)
        }

        do {
            let transport = SyntheticTransport(.permitted)
            let service = OpenAICompatibleService(transport: { request in try await transport.send(request) })
            let recorder = ReadRecorder()
            let reply = try await service.respondWithTools(messages: messages, credentials: credentials,
                allowedCategories: [.finance], onToolEvent: { recorder.events.append($0) }) { request in
                    try await recorder.read(request)
                }
            precondition(reply.events.count == 1 && recorder.events.count == 1)
            precondition(reply.events[0].category == recorder.events[0].category && reply.events[0].succeeded == recorder.events[0].succeeded)
        }

        do {
            let transport = SyntheticTransport(.permitted)
            let service = OpenAICompatibleService(transport: { request in try await transport.send(request) })
            let recorder = ReadRecorder()
            let task = Task {
                try await service.respondWithTools(messages: messages, credentials: credentials,
                    allowedCategories: [.finance], onToolEvent: {
                        recorder.events.append($0)
                        withUnsafeCurrentTask { $0?.cancel() }
                    }) { request in
                        try await recorder.read(request)
                    }
            }
            do {
                _ = try await task.value
                fatalError("cancelled request unexpectedly completed")
            } catch is CancellationError {}
            precondition(recorder.calls.count == 1 && recorder.events.count == 1 && recorder.events[0].category == .finance)
        }

        do {
            let transport = SyntheticTransport(.repeated)
            let service = OpenAICompatibleService(transport: { request in try await transport.send(request) })
            let recorder = ReadRecorder()
            _ = try await service.respondWithTools(messages: messages, credentials: credentials, allowedCategories: [.finance]) { request in
                try await recorder.read(request)
            }
            fatalError("unbounded tool loop")
        } catch AIServiceError.toolLimit {}

        do {
            let transport = SyntheticTransport(.unauthorized)
            let service = OpenAICompatibleService(transport: { request in try await transport.send(request) })
            _ = try await service.respond(messages: messages, credentials: credentials)
            fatalError("HTTP 401 accepted")
        } catch AIServiceError.serverStatus(let status) { precondition(status == 401) }

        do {
            let transport = SyntheticTransport(.oversizedReasoning)
            let service = OpenAICompatibleService(transport: { request in try await transport.send(request) })
            let recorder = ReadRecorder()
            _ = try await service.respondWithTools(messages: messages, credentials: credentials, allowedCategories: [.finance]) { request in
                try await recorder.read(request)
            }
            fatalError("oversized reasoning accepted")
        } catch AIServiceError.invalidResponse {}

        let deepseek = AIServiceCredentials(endpoint: URL(string: "https://api.deepseek.com/chat/completions")!, model: "synthetic-model", apiKey: "synthetic-key")
        let deepseekTransport = SyntheticTransport(.permitted)
        let deepseekService = OpenAICompatibleService(transport: { request in try await deepseekTransport.send(request) })
        let recorder = ReadRecorder()
        let deepseekReply = try await deepseekService.respondWithTools(messages: messages, credentials: deepseek, allowedCategories: [.finance]) { request in
            try await recorder.read(request)
        }
        precondition(deepseekReply.text == "测试回复" && deepseekReply.events.count == 1)
        let deepseekRequests = await deepseekTransport.requests
        for request in deepseekRequests {
            let json = try JSONSerialization.jsonObject(with: request) as! [String: Any]
            precondition((json["thinking"] as? [String: String])?["type"] == "disabled")
        }
        do {
            let planTransport = SyntheticTransport(.plan)
            let service = OpenAICompatibleService(transport: { request in try await planTransport.send(request) })
            let reply = try await service.respondWithTools(messages: messages, credentials: credentials, allowedCategories: [], allowPlanProposal: true, toolHandler: nil)
            precondition(reply.proposal?.items.count == 2 && reply.proposal?.items[1].kind == .schedule)
            let stored = try JSONEncoder().encode(reply.proposal!)
            let restored = try JSONDecoder().decode(AIPlanProposal.self, from: stored)
            precondition(restored.items.map(\.id) == reply.proposal!.items.map(\.id))
            let requests = await planTransport.requests
            let body = try JSONSerialization.jsonObject(with: requests[0]) as! [String: Any]
            let tools = body["tools"] as! [[String: Any]]
            precondition((tools[0]["function"] as? [String: Any])?["name"] as? String == "propose_lifeos_plan")
            for invalid in [#"{"items":[]}"#, #"{"items":[{"kind":"schedule","title":"x","minutes":30}]}"#, #"{"items":[{"kind":"study","title":"x","date":"2026-02-30","minutes":30}]}"#, #"{"items":[{"kind":"study","title":"x","minutes":9999}]}"#, #"{"items":[{"kind":"delete","title":"x","minutes":30}]}"#] {
                precondition(AIPlanProposal.parse(invalid) == nil)
            }
        }
        print("AI service offline checks passed: URL validation, tool round trip, permission denial including settings, event retained after HTTP failure and cancellation, invalid arguments, loop limit, HTTP status, reasoning handling and DeepSeek compatibility.")
    }
}
