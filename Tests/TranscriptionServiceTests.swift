import Foundation

private actor ValidationRequestRecorder {
    private(set) var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        requests.append(request)
    }
}

enum TranscriptionServiceTests {
    @MainActor
    static func run() async {
        let recorder = ValidationRequestRecorder()
        let savedCredential = "saved-main-credential"
        let savedBaseURL = "https://saved-provider.invalid/v1"
        let savedTranscriptionCredential = "saved-transcription-credential"
        let savedTranscriptionURL = "https://saved-transcription.invalid/v1"
        let draftTranscriptionCredential = "draft-transcription-credential"
        let draftTranscriptionURL = "https://draft-transcription.invalid/v1"
        var persistedCredential = savedCredential
        var persistedBaseURL = savedBaseURL
        var persistedTranscriptionCredential = savedTranscriptionCredential
        var persistedTranscriptionURL = savedTranscriptionURL
        var applyCount = 0
        let valid = await APIConfigurationSaveFlow.validateAndApply(
            apiKey: savedCredential,
            baseURL: savedBaseURL,
            transcriptionAPIURL: draftTranscriptionURL,
            transcriptionAPIKey: draftTranscriptionCredential,
            validator: { key, baseURL in
                await TranscriptionService.validateAPIKey(key, baseURL: baseURL) { request in
                    await recorder.append(request)
                    let status = request.url?.host == "saved-provider.invalid" ? 200 : 401
                    let response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: status,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                    return (Data(), response)
                }
            }
        ) { configuration in
            applyCount += 1
            persistedCredential = configuration.apiKey
            persistedBaseURL = configuration.baseURL
            persistedTranscriptionCredential = configuration.transcriptionAPIKey
            persistedTranscriptionURL = configuration.transcriptionAPIURL
        }
        let requests = await recorder.requests
        TestSupport.expect(!valid && requests.count == 2, "Main and effective transcription pairs are validated before persistence")
        let draftRequest = requests.first { $0.url?.host == "draft-transcription.invalid" }
        TestSupport.expect(draftRequest?.url?.absoluteString == "https://draft-transcription.invalid/v1/models", "Draft transcription endpoint is validated before it is saved")
        let authorization = draftRequest?.value(forHTTPHeaderField: "Authorization")
        TestSupport.expect(authorization == "Bearer \(draftTranscriptionCredential)", "Draft transcription endpoint receives only its paired draft credential")
        TestSupport.expect(authorization != "Bearer \(savedTranscriptionCredential)", "Saved transcription credential never reaches the draft endpoint")
        TestSupport.expect(applyCount == 0, "Failed validation does not cross the shared draft-to-persisted boundary")
        TestSupport.expect(persistedCredential == savedCredential && persistedBaseURL == savedBaseURL, "Failed transcription validation preserves the existing main API configuration")
        TestSupport.expect(persistedTranscriptionCredential == savedTranscriptionCredential && persistedTranscriptionURL == savedTranscriptionURL, "Failed transcription validation preserves the existing transcription override pair")

        var fallbackApplied: ValidatedAPIConfiguration?
        let fallbackValid = await APIConfigurationSaveFlow.validateAndApply(
            apiKey: savedCredential,
            baseURL: savedBaseURL,
            transcriptionAPIURL: "",
            transcriptionAPIKey: "",
            validator: { _, _ in true }
        ) { fallbackApplied = $0 }
        TestSupport.expect(fallbackValid && fallbackApplied?.transcriptionAPIURL.isEmpty == true && fallbackApplied?.transcriptionAPIKey.isEmpty == true, "Empty transcription overrides preserve fallback semantics without a partial override")

        // Gemini transcription request: language + script rule.
        let geminiURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!
        let hindiRequest = TranscriptionService.geminiTranscriptionRequest(
            baseURL: geminiURL,
            apiKey: "k",
            model: "gemini-2.5-flash",
            audioData: Data([0, 1, 2]),
            format: "wav",
            languageName: "Hindi"
        )
        let hindiPrompt = Self.promptText(of: hindiRequest)
        TestSupport.expect(hindiPrompt.contains("in Hindi"), "Gemini prompt must name the selected language")
        TestSupport.expect(hindiPrompt.contains("Never convert Roman-script"), "Gemini prompt must carry the script rule")
        let autoRequest = TranscriptionService.geminiTranscriptionRequest(
            baseURL: geminiURL,
            apiKey: "k",
            model: "gemini-2.5-flash",
            audioData: Data([0, 1, 2]),
            format: "wav"
        )
        TestSupport.expect(Self.promptText(of: autoRequest).contains("in the language the speaker uses"), "Auto-detect Gemini prompt must not invent a language")
        TestSupport.expect(Self.promptText(of: autoRequest).contains("Never convert Roman-script"), "Auto-detect Gemini prompt must still carry the script rule")

        // Gemini content-parts parsing: some OpenAI-compatible endpoints
        // return content as [{"type": "text", "text": "..."}].
        let partsJSON = """
        {"choices": [{"message": {"content": [{"type": "text", "text": "Hello "}, {"type": "text", "text": "world"}]}}]}
        """.data(using: .utf8)!
        TestSupport.expectEqual(try? TranscriptionService.parseGeminiChatTranscript(from: partsJSON), "Hello world")
        let stringJSON = """
        {"choices": [{"message": {"content": "  Plain transcript  "}}]}
        """.data(using: .utf8)!
        TestSupport.expectEqual(try? TranscriptionService.parseGeminiChatTranscript(from: stringJSON), "Plain transcript")
        let missingJSON = """
        {"choices": [{"message": {}}]}
        """.data(using: .utf8)!
        TestSupport.expect((try? TranscriptionService.parseGeminiChatTranscript(from: missingJSON)) == nil, "Missing content is still an invalid response")
    }

    private static func promptText(of request: URLRequest) -> String {
        guard let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]],
              let content = messages.first?["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else { return "" }
        return text
    }
}
