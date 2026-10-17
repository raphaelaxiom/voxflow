import Foundation
import os.log

private let transcriptionLog = OSLog(subsystem: "com.voxflow.app", category: "Transcription")

struct ValidatedAPIConfiguration: Equatable, Sendable {
    let apiKey: String
    let baseURL: String
    let transcriptionAPIURL: String
    let transcriptionAPIKey: String
}

enum APIConfigurationSaveFlow {
    static let defaultBaseURL = "https://generativelanguage.googleapis.com/v1beta/openai"

    @MainActor
    static func validateAndApply(
        apiKey: String,
        baseURL: String,
        transcriptionAPIURL: String,
        transcriptionAPIKey: String,
        validator: @escaping @Sendable (String, String) async -> Bool = { key, url in
            await TranscriptionService.validateAPIKey(key, baseURL: url)
        },
        apply: (ValidatedAPIConfiguration) -> Void
    ) async -> Bool {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBaseURL = trimmedBaseURL.isEmpty ? defaultBaseURL : trimmedBaseURL
        let trimmedTranscriptionURL = transcriptionAPIURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTranscriptionKey = transcriptionAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTranscriptionURL = trimmedTranscriptionURL.isEmpty ? resolvedBaseURL : trimmedTranscriptionURL
        let effectiveTranscriptionKey = trimmedTranscriptionKey.isEmpty ? key : trimmedTranscriptionKey
        guard await validator(key, resolvedBaseURL) else { return false }
        if effectiveTranscriptionURL != resolvedBaseURL || effectiveTranscriptionKey != key {
            guard await validator(effectiveTranscriptionKey, effectiveTranscriptionURL) else { return false }
        }
        apply(ValidatedAPIConfiguration(
            apiKey: key,
            baseURL: resolvedBaseURL,
            transcriptionAPIURL: trimmedTranscriptionURL,
            transcriptionAPIKey: trimmedTranscriptionKey
        ))
        return true
    }
}

class TranscriptionService {
    private static let modelsSupportingVerboseJSON: Set<String> = [
        // OpenAI's Whisper model supports segment metadata. The newer
        // gpt-4o-transcribe family only supports the plain JSON format.
        "whisper-1",
        // Groq's hosted Whisper models support verbose_json and expose the
        // segment metadata used by the hallucination filter below.
        "whisper-large-v3",
        "whisper-large-v3-turbo"
    ]

    private let apiKey: String
    private let baseURL: URL
    private let transcriptionModel: String
    private let language: String?
    /// Display name of the transcription language ("Hindi", "English", …),
    /// used in the Gemini prompt. Nil = auto-detect.
    private let languageName: String?
    private var transcriptionResponseFormat: String {
        Self.responseFormat(forModel: transcriptionModel)
    }
    private var transcriptionTimeoutSeconds: TimeInterval {
        let override = UserDefaults.standard.double(forKey: "transcription_timeout_seconds")
        return override > 0 ? override : 20
    }

    init(
        apiKey: String,
        baseURL: String = "https://generativelanguage.googleapis.com/v1beta/openai",
        transcriptionModel: String = "whisper-large-v3",
        language: String? = nil,
        languageName: String? = nil
    ) throws {
        self.apiKey = apiKey
        self.baseURL = try Self.normalizedBaseURL(from: baseURL)
        let trimmedModel = transcriptionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transcriptionModel = trimmedModel.isEmpty ? "whisper-large-v3" : trimmedModel
        let trimmedLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = (trimmedLanguage?.isEmpty == false) ? trimmedLanguage : nil
        let trimmedLanguageName = languageName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.languageName = (trimmedLanguageName?.isEmpty == false) ? trimmedLanguageName : nil
    }

    static func responseFormat(forModel model: String) -> String {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return modelsSupportingVerboseJSON.contains(normalizedModel) ? "verbose_json" : "json"
    }

    // Validate API key by hitting a lightweight endpoint
    static func validateAPIKey(
        _ key: String,
        baseURL: String = "https://generativelanguage.googleapis.com/v1beta/openai",
        transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await LLMAPITransport.data(for: request)
        }
    ) async -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let baseURL = try? normalizedBaseURL(from: baseURL) else { return false }

        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.timeoutInterval = 10
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await transport(request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return status == 200
        } catch {
            return false
        }
    }

    // Upload audio file, submit for transcription, poll until done, return text
    func transcribe(fileURL: URL) async throws -> String {
        guard !Task.isCancelled else {
            throw CancellationError()
        }

        let timeoutSeconds = transcriptionTimeoutSeconds
        let raceState = TranscriptionTimeoutRaceState()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                raceState.setContinuation(continuation)

                let transcriptionTask = Task { [weak self] in
                    do {
                        guard let self else {
                            throw TranscriptionError.transcriptionFailed("Transcription service deallocated")
                        }
                        let result = try await self.transcribeAudio(fileURL: fileURL)
                        raceState.finish(.success(result))
                    } catch {
                        raceState.finish(.failure(Self.transcriptionTimeoutErrorIfNeeded(
                            error,
                            timeoutSeconds: timeoutSeconds
                        )))
                    }
                }

                let timeoutTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                        raceState.finish(.failure(TranscriptionError.transcriptionTimedOut(timeoutSeconds)))
                    } catch is CancellationError {
                    } catch {
                        raceState.finish(.failure(error))
                    }
                }

                raceState.setTasks([transcriptionTask, timeoutTask])
            }
        } onCancel: {
            raceState.cancel()
        }
    }

    // Send audio file for transcription and return text
    private func transcribeAudio(fileURL: URL) async throws -> String {
        return try await transcribeAudioWithURLSession(fileURL: fileURL)
    }

    /// Gemini models do not expose an OpenAI-style `/audio/transcriptions`
    /// endpoint on the OpenAI-compatible base URL. They transcribe through
    /// `/chat/completions` with an `input_audio` content part instead, which
    /// is the documented multimodal shape for that endpoint.
    static func isGeminiModel(_ model: String) -> Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("gemini-")
    }

    /// Audio format label for a Gemini `input_audio` part. The recorder
    /// writes WAV, so that is the expected case; anything else falls back
    /// to MP3 rather than sending a label the endpoint cannot interpret.
    static func geminiAudioFormat(for fileName: String) -> String {
        let lower = fileName.lowercased()
        if lower.hasSuffix(".wav") { return "wav" }
        if lower.hasSuffix(".mp3") { return "mp3" }
        return "wav"
    }

    /// Builds the Gemini chat-completions transcription request. Pure
    /// construction so tests can assert the payload without network access.
    static func geminiTranscriptionRequest(
        baseURL: URL,
        apiKey: String,
        model: String,
        audioData: Data,
        format: String,
        languageName: String? = nil
    ) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat").appendingPathComponent("completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The language + script rules matter: without them Gemini may
        // transcribe Roman-script Hinglish into Devanagari, which the user
        // did not ask for. The Whisper multipart path already sends the
        // language code; the Gemini path previously sent nothing.
        let languageClause: String
        if let languageName, !languageName.isEmpty {
            languageClause = "Transcribe this audio verbatim in \(languageName)."
        } else {
            languageClause = "Transcribe this audio verbatim in the language the speaker uses."
        }
        let prompt = languageClause
            + " Return only the spoken words, with no commentary, no labels, and no added punctuation beyond what was spoken."
            + " Write in the SAME script the speaker uses. Never convert Roman-script Hindi/Hinglish into Devanagari script."
        let payload: [String: Any] = [
            "model": model,
            "temperature": 0.0,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": prompt
                        ],
                        [
                            "type": "input_audio",
                            "input_audio": [
                                "data": audioData.base64EncodedString(),
                                "format": format
                            ]
                        ]
                    ]
                ]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])
        return request
    }

    /// Extracts the transcript from a Gemini chat-completions response.
    /// Accepts content as a plain string OR as an array of content parts
    /// (`[{"type": "text", "text": "..."}]`), which some OpenAI-compatible
    /// endpoints return. A missing/non-string/non-array content is still
    /// an invalid response.
    static func parseGeminiChatTranscript(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw TranscriptionResponseParsingError.invalidResponse
        }
        if let content = message["content"] as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined()
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw TranscriptionResponseParsingError.invalidResponse
    }

    private func transcribeAudioViaGeminiChat(fileURL: URL) async throws -> String {
        let audioData = try Data(contentsOf: fileURL)
        // One retry on a parse failure: empty/malformed responses are often
        // transient (content filtering, truncated payload). After the second
        // failure the error message is actionable instead of a bare
        // "Invalid response" dead-end.
        for attempt in 1...2 {
            var request = Self.geminiTranscriptionRequest(
                baseURL: baseURL,
                apiKey: apiKey,
                model: transcriptionModel,
                audioData: audioData,
                format: Self.geminiAudioFormat(for: fileURL.lastPathComponent),
                languageName: languageName
            )
            request.timeoutInterval = transcriptionTimeoutSeconds
            let (data, response) = try await LLMAPITransport.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranscriptionError.submissionFailed("No response from server")
            }
            guard httpResponse.statusCode == 200 else {
                throw TranscriptionError.submissionFailed(Self.friendlyHTTPMessage(
                    status: httpResponse.statusCode,
                    host: baseURL.host
                ))
            }
            do {
                return try Self.parseGeminiChatTranscript(from: data)
            } catch {
                os_log(
                    .error,
                    log: transcriptionLog,
                    "Gemini chat transcript parse failed (attempt %{public}d/2)",
                    attempt
                )
            }
        }
        throw TranscriptionError.pollFailed("Gemini returned an unreadable response — please try again")
    }

    private func transcribeAudioWithURLSession(fileURL: URL) async throws -> String {
        if Self.isGeminiModel(transcriptionModel) {
            return try await transcribeAudioViaGeminiChat(fileURL: fileURL)
        }
        let url = baseURL
            .appendingPathComponent("audio")
            .appendingPathComponent("transcriptions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = transcriptionTimeoutSeconds
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: fileURL)
        let body = makeMultipartBody(
            audioData: audioData,
            fileName: fileURL.lastPathComponent,
            model: transcriptionModel,
            responseFormat: transcriptionResponseFormat,
            language: language,
            boundary: boundary
        )

        do {
            let (data, response) = try await LLMAPITransport.upload(for: request, from: body)
            return try validateTranscriptionResponse(data: data, response: response, fileURL: fileURL)
        } catch {
            let nsError = error as NSError
            os_log(
                .error,
                log: transcriptionLog,
                "URLSession upload failed for %{public}@ (bytes=%{public}lld): domain=%{public}@ code=%ld desc=%{public}@",
                fileURL.lastPathComponent,
                fileSizeBytes(for: fileURL),
                nsError.domain,
                nsError.code,
                error.localizedDescription
            )
            throw error
        }
    }

    private func validateTranscriptionResponse(data: Data, response: URLResponse, fileURL: URL) throws -> String {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.submissionFailed("No response from server")
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            os_log(
                .error,
                log: transcriptionLog,
                "URLSession upload returned HTTP %ld for %{public}@ (bytes=%{public}lld) body=%{public}@",
                httpResponse.statusCode,
                fileURL.lastPathComponent,
                fileSizeBytes(for: fileURL),
                responseBody
            )
            throw TranscriptionError.submissionFailed(Self.friendlyHTTPMessage(
                status: httpResponse.statusCode,
                host: baseURL.host
            ))
        }

        return try parseTranscript(from: data)
    }
    private func audioContentType(for fileName: String) -> String {
        if fileName.lowercased().hasSuffix(".wav") {
            return "audio/wav"
        }
        if fileName.lowercased().hasSuffix(".mp3") {
            return "audio/mpeg"
        }
        if fileName.lowercased().hasSuffix(".m4a") {
            return "audio/mp4"
        }
        return "audio/mp4"
    }

    private func fileSizeBytes(for fileURL: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? -1
    }

    private func makeMultipartBody(
        audioData: Data,
        fileName: String,
        model: String,
        responseFormat: String,
        language: String?,
        boundary: String
    ) -> Data {
        var body = Data()

        func append(_ value: String) {
            body.append(Data(value.utf8))
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(model)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        append("\(responseFormat)\r\n")

        if let language, !language.isEmpty {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            append("\(language)\r\n")
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(audioContentType(for: fileName))\r\n\r\n")
        body.append(audioData)
        append("\r\n")
        append("--\(boundary)--\r\n")

        return body
    }

    /// Map a non-200 HTTP status into a one-line user-readable message.
    /// Used for transcription submission failures so the menu bar shows
    /// "Invalid API key for api.openai.com" instead of raw JSON.
    static func friendlyHTTPMessage(status: Int, host: String?) -> String {
        let provider = host ?? "the provider"
        switch status {
        case 401:
            return "Invalid API key for \(provider). Open Settings to fix it."
        case 403:
            return "Key lacks permission for this endpoint at \(provider) (HTTP 403). Check the key's scopes."
        case 404:
            return "Endpoint not found at \(provider) (HTTP 404). Base URL is likely wrong for this provider."
        case 413:
            return "Audio file too large for \(provider) (HTTP 413). Try a shorter recording."
        case 400:
            return "Provider rejected the request (HTTP 400). Check your model name and Base URL in Settings."
        case 429:
            return "Rate limit reached at \(provider) (HTTP 429). Wait a moment and try again."
        case 500..<600:
            return "Provider error at \(provider) (HTTP \(status)). Try again in a moment."
        default:
            return "Request failed at \(provider) (HTTP \(status))."
        }
    }

    private static func transcriptionTimeoutErrorIfNeeded(
        _ error: Error,
        timeoutSeconds: TimeInterval
    ) -> Error {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return TranscriptionError.transcriptionTimedOut(timeoutSeconds)
        }
        return error
    }

    private static func normalizedBaseURL(from baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranscriptionError.invalidBaseURL("Provider URL is empty.")
        }

        guard var components = URLComponents(string: trimmed) else {
            throw TranscriptionError.invalidBaseURL("Provider URL is malformed.")
        }

        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw TranscriptionError.invalidBaseURL("Provider URL must use http or https.")
        }

        guard let host = components.host, !host.isEmpty else {
            throw TranscriptionError.invalidBaseURL("Provider URL must include a host.")
        }

        components.scheme = scheme
        if components.path == "/" {
            components.path = ""
        } else {
            components.path = components.path.replacingOccurrences(
                of: "/+$",
                with: "",
                options: .regularExpression
            )
        }

        guard let normalizedURL = components.url else {
            throw TranscriptionError.invalidBaseURL("Provider URL is malformed.")
        }

        return normalizedURL
    }

    private func parseTranscript(from data: Data) throws -> String {
        do {
            return try TranscriptionResponseParser.parse(data)
        } catch TranscriptionResponseParsingError.invalidResponse {
            throw TranscriptionError.pollFailed("Invalid response")
        }
    }
}

enum TranscriptionError: LocalizedError {
    case invalidBaseURL(String)
    case uploadFailed(String)
    case submissionFailed(String)
    case transcriptionFailed(String)
    case transcriptionTimedOut(TimeInterval)
    case pollFailed(String)
    case audioPreparationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let msg): return "Invalid provider URL: \(msg)"
        case .uploadFailed(let msg): return "Upload failed: \(msg)"
        case .submissionFailed(let msg): return "Submission failed: \(msg)"
        case .transcriptionTimedOut(let seconds): return "Transcription timed out after \(Int(seconds))s"
        case .transcriptionFailed(let msg): return "Transcription failed: \(msg)"
        case .pollFailed(let msg): return "Polling failed: \(msg)"
        case .audioPreparationFailed(let msg): return "Audio preparation failed: \(msg)"
        }
    }
}

private final class TranscriptionTimeoutRaceState {
    private let lock = NSLock()
    private var didFinish = false
    private var continuation: CheckedContinuation<String, Error>?
    private var tasks: [Task<Void, Never>] = []

    func setContinuation(_ continuation: CheckedContinuation<String, Error>) {
        lock.lock()
        if didFinish {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }

        self.continuation = continuation
        lock.unlock()
    }

    func setTasks(_ tasks: [Task<Void, Never>]) {
        lock.lock()
        if didFinish {
            lock.unlock()
            tasks.forEach { $0.cancel() }
            return
        }

        self.tasks = tasks
        lock.unlock()
    }

    func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }

        didFinish = true
        let continuation = self.continuation
        self.continuation = nil
        let tasks = self.tasks
        self.tasks = []
        lock.unlock()

        tasks.forEach { $0.cancel() }

        switch result {
        case .success(let value):
            continuation?.resume(returning: value)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }
}

private struct PreparedUploadAudio {
    let fileURL: URL
    let deleteOnCleanup: Bool

    func cleanup() {
        guard deleteOnCleanup else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
