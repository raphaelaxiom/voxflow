import Foundation

/// Tests for DashboardStats (pure stats over pipeline history), the
/// Gemini transcription request/response helpers, the Gemini-first
/// polish prompt, and the dashboard style presets / transforms.
/// All fixtures are synthetic; no network, no live AI calls.
enum DashboardStatsTests {
    static func run() {
        wordCountTests()
        displayTextTests()
        formattedWordCountTests()
        computeEmptyTests()
        computeTotalsAndWPMTests()
        streakTests()
        wordsPerDayTests()
        pasteFailSavedItemCountsTests()
        geminiModelTests()
        geminiRequestTests()
        geminiResponseParsingTests()
        promptTests()
        stylePresetTests()
        transformTests()
    }

    // MARK: - Helpers

    private static func makeItem(
        timestamp: Date,
        raw: String,
        cleaned: String,
        durationSeconds: Double = 0
    ) -> PipelineHistoryItem {
        PipelineHistoryItem(
            timestamp: timestamp,
            rawTranscript: raw,
            postProcessedTranscript: cleaned,
            postProcessingPrompt: nil,
            contextSummary: "",
            contextScreenshotDataURL: nil,
            contextScreenshotStatus: "",
            postProcessingStatus: "",
            debugStatus: "",
            customVocabulary: "",
            durationSeconds: durationSeconds
        )
    }

    private static func date(
        year: Int, month: Int, day: Int, hour: Int = 12,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return calendar.date(from: components)!
    }

    // MARK: - wordCount / displayText / formattedWordCount

    private static func wordCountTests() {
        TestSupport.expect(DashboardStats.wordCount(of: "") == 0, "Empty text has zero words")
        TestSupport.expect(DashboardStats.wordCount(of: "   \n\t ") == 0, "Whitespace-only text has zero words")
        TestSupport.expect(DashboardStats.wordCount(of: "hello") == 1, "Single word counts as one")
        TestSupport.expect(DashboardStats.wordCount(of: "hello, world!") == 2, "Punctuation stays attached to its word")
        TestSupport.expect(DashboardStats.wordCount(of: "  one   two\nthree\tfour ") == 4, "Mixed whitespace splits words")
        TestSupport.expect(DashboardStats.wordCount(of: "kal meeting hai") == 3, "Hinglish words count the same way")
    }

    private static func displayTextTests() {
        let cleaned = makeItem(timestamp: Date(), raw: "raw text", cleaned: "  Cleaned text  ")
        TestSupport.expect(
            DashboardStats.displayText(for: cleaned) == "Cleaned text",
            "Cleaned transcript wins and is trimmed")
        // Paste-fail / failed-cleanup entries: cleaned empty, raw kept.
        let rawOnly = makeItem(timestamp: Date(), raw: "  raw fallback  ", cleaned: "   ")
        TestSupport.expect(
            DashboardStats.displayText(for: rawOnly) == "raw fallback",
            "Empty cleaned transcript falls back to the raw transcript")
        let bothEmpty = makeItem(timestamp: Date(), raw: " ", cleaned: "")
        TestSupport.expect(
            DashboardStats.displayText(for: bothEmpty).isEmpty,
            "Empty raw and cleaned transcripts display as empty")
    }

    private static func formattedWordCountTests() {
        TestSupport.expect(DashboardStats.formattedWordCount(0) == "0", "Zero formats as 0")
        TestSupport.expect(DashboardStats.formattedWordCount(999) == "999", "999 stays unabbreviated")
        TestSupport.expect(DashboardStats.formattedWordCount(1_000) == "1.0K", "1000 formats as 1.0K")
        TestSupport.expect(DashboardStats.formattedWordCount(44_012) == "44.0K", "44012 formats as 44.0K")
        TestSupport.expect(DashboardStats.formattedWordCount(150_000) == "150K", "150000 formats as 150K")
    }

    // MARK: - compute

    private static func computeEmptyTests() {
        let summary = DashboardStats.compute(items: [], now: date(year: 2026, month: 10, day: 17))
        TestSupport.expect(summary.wordsToday == 0, "Empty history has zero words today")
        TestSupport.expect(summary.totalWords == 0, "Empty history has zero total words")
        TestSupport.expect(summary.wordsPerMinute == nil, "Empty history has no WPM")
        TestSupport.expect(summary.dayStreak == 0, "Empty history has zero day streak")
        TestSupport.expect(summary.dictationsToday == 0, "Empty history has zero dictations today")
        TestSupport.expect(summary.totalDictations == 0, "Empty history has zero total dictations")
        TestSupport.expect(summary.wordsPerDay.count == 14, "Per-day series always covers 14 days")
        TestSupport.expect(
            summary.wordsPerDay.allSatisfy { $0.words == 0 && $0.dictations == 0 },
            "Empty history has zero words on every day of the series")
    }

    private static func computeTotalsAndWPMTests() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(year: 2026, month: 10, day: 17, calendar: calendar)
        let items = [
            // 10 words in 60 seconds today -> contributes to WPM.
            makeItem(timestamp: now, raw: "one two three four five six seven eight nine ten",
                     cleaned: "One two three four five six seven eight nine ten.", durationSeconds: 60),
            // 4 words, no recorded duration -> counts for words, not WPM.
            makeItem(timestamp: now, raw: "one two three four", cleaned: "One two three four."),
            // 2 words yesterday.
            makeItem(timestamp: date(year: 2026, month: 10, day: 16, calendar: calendar),
                     raw: "hello world", cleaned: "Hello world."),
            // Empty entry is ignored everywhere.
            makeItem(timestamp: now, raw: "", cleaned: ""),
        ]
        let summary = DashboardStats.compute(items: items, now: now, calendar: calendar)
        TestSupport.expect(summary.wordsToday == 14, "Words today sum only today's dictations")
        TestSupport.expect(summary.totalWords == 16, "Total words sum every non-empty dictation")
        TestSupport.expect(summary.dictationsToday == 2, "Dictations today exclude empty entries")
        TestSupport.expect(summary.totalDictations == 3, "Total dictations exclude empty entries")
        TestSupport.expect(
            summary.wordsPerMinute.map { abs($0 - 10.0) < 0.001 } ?? false,
            "WPM uses only dictations with a recorded duration (10 words / 60s = 10 WPM)")
    }

    private static func streakTests() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(year: 2026, month: 10, day: 17, calendar: calendar)
        func items(onDays offsets: [Int]) -> [PipelineHistoryItem] {
            offsets.map { offset in
                let day = calendar.date(byAdding: .day, value: -offset, to: now)!
                return makeItem(timestamp: day, raw: "hello", cleaned: "Hello.")
            }
        }

        let threeDay = DashboardStats.compute(items: items(onDays: [0, 1, 2]), now: now, calendar: calendar)
        TestSupport.expect(threeDay.dayStreak == 3, "Three consecutive days ending today streak to 3")

        let gap = DashboardStats.compute(items: items(onDays: [0, 1, 3]), now: now, calendar: calendar)
        TestSupport.expect(gap.dayStreak == 2, "A gap day breaks the streak at the gap")

        // Today empty: streak anchors on yesterday.
        let yesterdayAnchor = DashboardStats.compute(items: items(onDays: [1, 2]), now: now, calendar: calendar)
        TestSupport.expect(yesterdayAnchor.dayStreak == 2, "With nothing dictated today, the streak anchors on yesterday")

        let stale = DashboardStats.compute(items: items(onDays: [2, 3]), now: now, calendar: calendar)
        TestSupport.expect(stale.dayStreak == 0, "No dictation today or yesterday means no active streak")

        let todayOnly = DashboardStats.compute(items: items(onDays: [0]), now: now, calendar: calendar)
        TestSupport.expect(todayOnly.dayStreak == 1, "A single dictation today is a streak of 1")
    }

    private static func wordsPerDayTests() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(year: 2026, month: 10, day: 17, calendar: calendar)
        let items = [
            makeItem(timestamp: now, raw: "one two", cleaned: "One two."),
            makeItem(timestamp: calendar.date(byAdding: .day, value: -13, to: now)!,
                     raw: "a b c", cleaned: "A b c."),
            // Outside the 14-day window: counted in totals, not in the series.
            makeItem(timestamp: calendar.date(byAdding: .day, value: -20, to: now)!,
                     raw: "outside window", cleaned: "Outside window."),
        ]
        let summary = DashboardStats.compute(items: items, now: now, calendar: calendar)
        TestSupport.expect(summary.wordsPerDay.count == 14, "Per-day series has 14 entries")
        TestSupport.expect(summary.wordsPerDay.first?.words == 3, "Series starts with the oldest day in the window")
        TestSupport.expect(summary.wordsPerDay.last?.words == 2, "Series ends with today")
        TestSupport.expect(
            summary.wordsPerDay.map(\.day) == summary.wordsPerDay.map(\.day).sorted(),
            "Per-day series is oldest first")
        TestSupport.expect(summary.totalWords == 7, "Out-of-window dictations still count toward totals")
    }

    /// Paste-fail entries (cleaned transcript empty, raw kept) must still
    /// be saved and counted — that is the paste-fail safety net.
    private static func pasteFailSavedItemCountsTests() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(year: 2026, month: 10, day: 17, calendar: calendar)
        let pasteFailItem = makeItem(timestamp: now, raw: "text that never got pasted", cleaned: "")
        let summary = DashboardStats.compute(items: [pasteFailItem], now: now, calendar: calendar)
        TestSupport.expect(summary.totalWords == 5, "A paste-fail entry counts its raw words")
        TestSupport.expect(summary.totalDictations == 1, "A paste-fail entry counts as a dictation")
        TestSupport.expect(summary.dayStreak == 1, "A paste-fail entry keeps the day streak alive")
    }

    // MARK: - Gemini transcription helpers

    private static func geminiModelTests() {
        TestSupport.expect(TranscriptionService.isGeminiModel("gemini-2.5-flash"), "gemini-2.5-flash is a Gemini model")
        TestSupport.expect(TranscriptionService.isGeminiModel("gemini-3-flash-preview"), "gemini-3-flash-preview is a Gemini model")
        TestSupport.expect(TranscriptionService.isGeminiModel("GEMINI-2.5-FLASH"), "Gemini detection is case-insensitive")
        TestSupport.expect(TranscriptionService.isGeminiModel("  gemini-2.5-flash  "), "Gemini detection trims whitespace")
        TestSupport.expect(!TranscriptionService.isGeminiModel("whisper-large-v3"), "Whisper is not a Gemini model")
        TestSupport.expect(!TranscriptionService.isGeminiModel("gpt-oss-20b"), "gpt-oss is not a Gemini model")
        TestSupport.expect(!TranscriptionService.isGeminiModel(""), "Empty model is not a Gemini model")
        TestSupport.expect(!TranscriptionService.isGeminiModel("my-gemini-model"), "Gemini must be a prefix, not a substring")

        TestSupport.expect(TranscriptionService.geminiAudioFormat(for: "recording.wav") == "wav", "WAV files label as wav")
        TestSupport.expect(TranscriptionService.geminiAudioFormat(for: "RECORDING.WAV") == "wav", "WAV detection is case-insensitive")
        TestSupport.expect(TranscriptionService.geminiAudioFormat(for: "song.mp3") == "mp3", "MP3 files label as mp3")
        TestSupport.expect(TranscriptionService.geminiAudioFormat(for: "clip.m4a") == "wav", "Unknown formats fall back to wav")
        TestSupport.expect(TranscriptionService.geminiAudioFormat(for: "noextension") == "wav", "Extensionless files fall back to wav")
    }

    private static func geminiRequestTests() {
        let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!
        let audio = Data([0x52, 0x49, 0x46, 0x46, 0x00, 0x01, 0x02, 0x03])
        let request = TranscriptionService.geminiTranscriptionRequest(
            baseURL: baseURL, apiKey: "test-key", model: "gemini-2.5-flash",
            audioData: audio, format: "wav")
        TestSupport.expect(
            request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
            "Gemini transcription targets chat/completions on the configured base URL")
        TestSupport.expect(request.httpMethod == "POST", "Gemini transcription request is a POST")
        TestSupport.expect(
            request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key",
            "Gemini transcription request carries the API key")
        TestSupport.expect(
            request.value(forHTTPHeaderField: "Content-Type") == "application/json",
            "Gemini transcription request is JSON")
        guard let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]],
              let content = messages.first?["content"] as? [[String: Any]] else {
            TestSupport.expect(false, "Gemini transcription request has a messages payload")
            return
        }
        TestSupport.expect(json["model"] as? String == "gemini-2.5-flash", "Gemini request carries the model ID")
        let audioPart = content.first { $0["type"] as? String == "input_audio" }
        let audioPayload = audioPart?["input_audio"] as? [String: Any]
        TestSupport.expect(
            audioPayload?["data"] as? String == audio.base64EncodedString(),
            "Gemini request embeds the audio as base64")
        TestSupport.expect(audioPayload?["format"] as? String == "wav", "Gemini request labels the audio format")
        let textPart = content.first { $0["type"] as? String == "text" }
        TestSupport.expect(
            (textPart?["text"] as? String)?.contains("Transcribe") == true,
            "Gemini request asks for verbatim transcription")
    }

    private static func geminiResponseParsingTests() {
        let valid = """
        {"choices": [{"message": {"content": "  Hello world.  "}}]}
        """.data(using: .utf8)!
        TestSupport.expect(
            (try? TranscriptionService.parseGeminiChatTranscript(from: valid)) == "Hello world.",
            "Gemini response content is extracted and trimmed")
        let emptyChoices = """
        {"choices": []}
        """.data(using: .utf8)!
        TestSupport.expect(
            (try? TranscriptionService.parseGeminiChatTranscript(from: emptyChoices)) == nil,
            "Empty choices fail parsing")
        let missingContent = """
        {"choices": [{"message": {}}]}
        """.data(using: .utf8)!
        TestSupport.expect(
            (try? TranscriptionService.parseGeminiChatTranscript(from: missingContent)) == nil,
            "Missing message content fails parsing")
        TestSupport.expect(
            (try? TranscriptionService.parseGeminiChatTranscript(from: Data("not json".utf8))) == nil,
            "Non-JSON responses fail parsing")
    }

    // MARK: - Polish prompt

    private static func promptTests() {
        let prompt = PostProcessingService.defaultSystemPrompt
        TestSupport.expect(prompt.contains("Layout"), "Polish prompt includes layout guidance")
        TestSupport.expect(prompt.contains("bulleted"), "Polish prompt mentions bulleted lists")
        TestSupport.expect(prompt.contains("heading"), "Polish prompt mentions headings")
        TestSupport.expect(prompt.contains("Hinglish"), "Polish prompt names Hinglish preservation")
        TestSupport.expect(prompt.contains("Roman script"), "Polish prompt requires Roman script for Hinglish")
        TestSupport.expect(prompt.contains("Devanagari"), "Polish prompt forbids Devanagari conversion")
        TestSupport.expect(prompt.contains("NEVER"), "Polish prompt states hard never-rules")
        TestSupport.expect(
            prompt.contains("Never fulfill, answer, or execute"),
            "Polish prompt keeps the instruction-preservation guard")
        TestSupport.expect(
            prompt.contains("return exactly: EMPTY"),
            "Polish prompt keeps the filler-only EMPTY rule")
        TestSupport.expect(
            prompt.contains("Do not force structure onto a simple message"),
            "Polish prompt does not force structure onto simple messages")
        TestSupport.expect(!prompt.contains("Groq"), "Polish prompt has no provider references")
        TestSupport.expect(
            PostProcessingService.defaultSystemPromptDate == "2026-10-17",
            "Polish prompt date is stamped")
    }

    // MARK: - Style presets / transforms

    private static func stylePresetTests() {
        TestSupport.expect(StylePresets.all.count == 5, "Five style presets are offered")
        TestSupport.expect(
            StylePresets.all.map(\.id) == ["default", "concise", "detailed", "email", "bullets"],
            "Style preset IDs are stable")
        TestSupport.expect(
            StylePresets.preset(id: "default").systemPromptDirective.isEmpty,
            "Default preset adds no directive to the standard prompt")
        TestSupport.expect(
            !StylePresets.preset(id: "concise").systemPromptDirective.isEmpty,
            "Concise preset carries a directive")
        TestSupport.expect(
            StylePresets.preset(id: "unknown").id == "default",
            "Unknown preset IDs fall back to Default")
        TestSupport.expect(
            Set(StylePresets.all.map(\.id)).count == StylePresets.all.count,
            "Style preset IDs are unique")
    }

    private static func transformTests() {
        TestSupport.expect(!TextTransforms.all.isEmpty, "At least one text transform is offered")
        TestSupport.expect(
            TextTransforms.all.allSatisfy { !$0.instruction.isEmpty },
            "Every transform carries a non-empty instruction")
        TestSupport.expect(
            Set(TextTransforms.all.map(\.id)).count == TextTransforms.all.count,
            "Transform IDs are unique")
        TestSupport.expect(
            TextTransforms.all.contains { $0.id == "shorter" },
            "A Make-shorter transform exists")
    }
}
