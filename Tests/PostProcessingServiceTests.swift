import Foundation

enum PostProcessingServiceTests {
    static func run() {
        testAutoDetectAndEnglishLeavePromptUnchanged()
        testSelectedLanguageIsNamed()
        testOutputLanguageTakesPrecedence()
        testCustomPromptKeepsDirective()
        testFallbackModelReceivesSameDirective()
        testEnglishRequestIsUnchanged()
        testPolishModelMapping()
        testDevanagariDetection()
        testHindiDictationLanguageUsesRomanScript()
        testWrongScriptRetriesOnceWithStricterPrompt()
        testWrongScriptSurfacesWhenStrictRetryAlsoFails()
        testDevanagariAllowedWhenOutputLanguageIsHindi()
    }

    private static let directive = "The dictation is primarily in Russian"

    private static func testAutoDetectAndEnglishLeavePromptUnchanged() {
        for language in ["", "  ", "English"] {
            TestSupport.expectEqual(
                PostProcessingService.cleanupSystemPrompt(
                    customSystemPrompt: "",
                    outputLanguage: "",
                    dictationLanguage: language
                ),
                PostProcessingService.defaultSystemPrompt
            )
        }
    }

    private static func testSelectedLanguageIsNamed() {
        let prompt = PostProcessingService.cleanupSystemPrompt(
            customSystemPrompt: "",
            outputLanguage: "",
            dictationLanguage: "Russian"
        )
        TestSupport.expect(prompt.hasPrefix(PostProcessingService.defaultSystemPrompt), "Directive must only append")
        TestSupport.expect(prompt.contains(directive), "Selected language must be named")
        TestSupport.expect(prompt.contains("Write the cleaned text in Russian"), "Output language must be named")
        TestSupport.expect(
            prompt.contains("Preserve mixed-language words and spans in their original languages"),
            "Naming a language must not override mixed-language preservation"
        )
        TestSupport.expect(!prompt.contains("Translate the final cleaned text"), "Keeping a language must not translate")
    }

    private static func testOutputLanguageTakesPrecedence() {
        let prompt = PostProcessingService.cleanupSystemPrompt(
            customSystemPrompt: "",
            outputLanguage: "German",
            dictationLanguage: "Russian"
        )
        TestSupport.expectEqual(
            prompt,
            PostProcessingService.applyOutputLanguage(PostProcessingService.defaultSystemPrompt, language: "German")
        )
        TestSupport.expect(!prompt.contains(directive), "Output Language must replace the dictation directive")
    }

    private static func testCustomPromptKeepsDirective() {
        let prompt = PostProcessingService.cleanupSystemPrompt(
            customSystemPrompt: "Synthetic custom prompt.",
            outputLanguage: "",
            dictationLanguage: "Russian"
        )
        TestSupport.expect(prompt.hasPrefix("Synthetic custom prompt."), "Custom prompt must replace the default")
        TestSupport.expect(!prompt.contains(PostProcessingService.defaultSystemPrompt), "Default prompt must not leak in")
        TestSupport.expect(prompt.contains(directive), "Custom prompt must still get the directive")
    }

    private static func testFallbackModelReceivesSameDirective() {
        // The primary returns empty content, which retries once on the fallback model.
        let requests = cleanupRequests(dictationLanguage: "Russian") { model in
            model == "synthetic-primary" ? "" : "Synthetic cleaned text."
        }
        TestSupport.expectEqual(requests.map(\.model), ["synthetic-primary", "synthetic-fallback"])
        for request in requests {
            TestSupport.expect(request.systemPrompt.contains(directive), "\(request.model) must get the directive")
        }
        TestSupport.expectEqual(requests[0].systemPrompt, requests[1].systemPrompt)
    }

    private static func testEnglishRequestIsUnchanged() {
        let requests = cleanupRequests(dictationLanguage: "English") { _ in "Synthetic cleaned text." }
        TestSupport.expectEqual(requests.map(\.systemPrompt), [PostProcessingService.defaultSystemPrompt])
    }

    private static func testPolishModelMapping() {
        let geminiBase = "https://generativelanguage.googleapis.com/v1beta/openai"
        let groqBase = "https://api.groq.com/openai/v1"
        TestSupport.expectEqual(
            PostProcessingService.polishModel(for: "gemini-2.5-flash", baseURL: geminiBase, defaultModel: "openai/gpt-oss-20b"),
            "gemini-2.5-flash-lite"
        )
        TestSupport.expectEqual(
            PostProcessingService.polishModel(for: "", baseURL: geminiBase, defaultModel: "openai/gpt-oss-20b"),
            "gemini-2.5-flash-lite"
        )
        TestSupport.expectEqual(
            PostProcessingService.polishModel(for: "", baseURL: groqBase, defaultModel: "openai/gpt-oss-20b"),
            "openai/gpt-oss-20b"
        )
        TestSupport.expectEqual(
            PostProcessingService.polishModel(for: "custom-model", baseURL: geminiBase, defaultModel: "openai/gpt-oss-20b"),
            "custom-model"
        )
    }

    private static func testDevanagariDetection() {
        TestSupport.expect(!ScriptDetection.containsDevanagari("Hello world"), "Roman text has no Devanagari")
        TestSupport.expect(!ScriptDetection.containsDevanagari("Yeh Hindi hai"), "Roman-script Hindi has no Devanagari")
        TestSupport.expect(ScriptDetection.containsDevanagari("यह हिन्दी है"), "Devanagari text must be detected")
        TestSupport.expect(ScriptDetection.containsDevanagari("Hello यह"), "Mixed text with Devanagari must be detected")
        TestSupport.expect(!ScriptDetection.containsDevanagari(""), "Empty text has no Devanagari")
    }

    private static func testHindiDictationLanguageUsesRomanScript() {
        let prompt = PostProcessingService.cleanupSystemPrompt(
            customSystemPrompt: "",
            outputLanguage: "",
            dictationLanguage: "Hindi"
        )
        TestSupport.expect(prompt.contains("ROMAN script"), "Hindi dictation must request Roman script")
        TestSupport.expect(prompt.contains("never Devanagari"), "Hindi dictation must block Devanagari")
        TestSupport.expect(prompt.contains("Write the cleaned text in Hindi"), "Hindi must still be named")
    }

    /// Devanagari on attempt 1 -> ONE strict-prompt retry on the same model
    /// -> Roman on attempt 2 wins. Dictation is never lost.
    private static func testWrongScriptRetriesOnceWithStricterPrompt() {
        let outcome = postProcessWithReplies(
            replies: ["यह एक परीक्षण है", "Yeh ek pareekshan hai."],
            outputLanguage: ""
        )
        TestSupport.expectEqual(outcome.prompts.count, 2)
        TestSupport.expect(outcome.prompts[1].contains("STRICT SCRIPT RULE"), "Retry must use the stricter script prompt")
        TestSupport.expectEqual(outcome.prompts[0].split(separator: "\n").first, outcome.prompts[1].split(separator: "\n").first)
        switch outcome.result {
        case .success(let result):
            TestSupport.expectEqual(result.transcript, "Yeh ek pareekshan hai.")
        case .failure(let error):
            TestSupport.expect(false, "Strict retry should have succeeded, got \(error)")
        }
    }

    /// Devanagari on both attempts -> the error surfaces (the caller falls
    /// back to the raw transcript). Exactly 2 requests: no fallback-model
    /// attempt, no infinite retry.
    private static func testWrongScriptSurfacesWhenStrictRetryAlsoFails() {
        let outcome = postProcessWithReplies(replies: ["यह एक परीक्षण है"], outputLanguage: "")
        TestSupport.expectEqual(outcome.prompts.count, 2)
        switch outcome.result {
        case .success(let result):
            TestSupport.expect(false, "Expected wrongScript, got \(result.transcript)")
        case .failure(let error):
            if let postError = error as? PostProcessingError, case .wrongScript = postError {
                TestSupport.expect(true, "wrongScript surfaced")
            } else {
                TestSupport.expect(false, "Expected wrongScript, got \(error)")
            }
        }
    }

    /// Explicit Output Language = Hindi allows Devanagari: no retry, no error.
    private static func testDevanagariAllowedWhenOutputLanguageIsHindi() {
        let outcome = postProcessWithReplies(replies: ["यह एक परीक्षण है"], outputLanguage: "Hindi")
        TestSupport.expectEqual(outcome.prompts.count, 1)
        switch outcome.result {
        case .success(let result):
            TestSupport.expectEqual(result.transcript, "यह एक परीक्षण है")
        case .failure(let error):
            TestSupport.expect(false, "Hindi output must allow Devanagari, got \(error)")
        }
    }

    // MARK: - Wrong-script harness

    private struct WrongScriptOutcome {
        let result: Result<PostProcessingResult, Error>
        let prompts: [String]
    }

    private final class AttemptCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }
            count += 1
            return count
        }
    }

    /// Runs postProcess with a per-attempt reply. `replies[i]` is used for
    /// attempt i+1; the last reply repeats for later attempts.
    private static func postProcessWithReplies(replies: [String], outputLanguage: String) -> WrongScriptOutcome {
        let recorder = RequestRecorder()
        let counter = AttemptCounter()
        let service = PostProcessingService(
apiKey: <redacted>
            baseURL: "https://example.invalid/v1",
            preferredModel: "synthetic-primary",
            preferredFallbackModel: "synthetic-fallback",
            transport: { request in
                recorder.record(request.httpBody)
                let attempt = counter.next()
                let reply = replies[min(attempt - 1, replies.count - 1)]
                let body = try JSONSerialization.data(withJSONObject: [
                    "choices": [["message": ["content": reply]]]
                ])
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (body, response)
            }
        )
        let context = AppContext(
            appName: nil,
            bundleIdentifier: nil,
            windowTitle: nil,
            selectedText: nil,
            currentActivity: "",
            contextSystemPrompt: nil,
            contextPrompt: nil,
            screenshotDataURL: nil,
            screenshotMimeType: nil,
            screenshotError: nil
        )
        var outcome: Result<PostProcessingResult, Error>?
        let done = DispatchSemaphore(value: 0)
        Task {
            do {
                let result = try await service.postProcess(
                    transcript: "synthetic transcript",
                    context: context,
                    customVocabulary: "",
                    outputLanguage: outputLanguage
                )
                outcome = .success(result)
            } catch {
                outcome = .failure(error)
            }
            done.signal()
        }
        done.wait()
        return WrongScriptOutcome(
            result: outcome ?? .failure(PostProcessingError.invalidResponse("No result")),
            prompts: recorder.captured.map(\.systemPrompt)
        )
    }

    // MARK: - Request capture

    private struct CapturedRequest {
        let model: String
        let systemPrompt: String
    }

    private final class RequestRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var bodies: [Data] = []

        func record(_ body: Data?) {
            lock.lock()
            defer { lock.unlock() }
            bodies.append(body ?? Data())
        }

        var captured: [CapturedRequest] {
            lock.lock()
            defer { lock.unlock() }
            return bodies.map { body in
                let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
                let messages = json["messages"] as? [[String: Any]] ?? []
                let system = messages.first { $0["role"] as? String == "system" }
                return CapturedRequest(
                    model: json["model"] as? String ?? "",
                    systemPrompt: system?["content"] as? String ?? ""
                )
            }
        }
    }

    private static func cleanupRequests(
        dictationLanguage: String,
        reply: @escaping @Sendable (String) -> String
    ) -> [CapturedRequest] {
        let recorder = RequestRecorder()
        let service = PostProcessingService(
            apiKey: "synthetic-key",
            baseURL: "https://example.invalid/v1",
            preferredModel: "synthetic-primary",
            preferredFallbackModel: "synthetic-fallback",
            transport: { request in
                recorder.record(request.httpBody)
                let json = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
                let model = json?["model"] as? String ?? ""
                let body = try JSONSerialization.data(withJSONObject: [
                    "choices": [["message": ["content": reply(model)]]]
                ])
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (body, response)
            }
        )
        let context = AppContext(
            appName: nil,
            bundleIdentifier: nil,
            windowTitle: nil,
            selectedText: nil,
            currentActivity: "",
            contextSystemPrompt: nil,
            contextPrompt: nil,
            screenshotDataURL: nil,
            screenshotMimeType: nil,
            screenshotError: nil
        )

        let done = DispatchSemaphore(value: 0)
        Task {
            _ = try? await service.postProcess(
                transcript: "synthetic transcript",
                context: context,
                customVocabulary: "",
                dictationLanguage: dictationLanguage
            )
            done.signal()
        }
        done.wait()
        return recorder.captured
    }
}
