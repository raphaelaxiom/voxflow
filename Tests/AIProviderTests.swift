import Foundation

enum AIProviderTests {
    static func run() {
        testGeminiDefaults()
        testGroqDefaults()
        testOllamaDefaults()
        testCustomDefaults()
        testUnknownStoredValueFallsBackToGemini()
        testThemePersistenceMapping()
    }

    private static func testGeminiDefaults() {
        let provider = AIProvider.gemini
        TestSupport.expectEqual(provider.defaultBaseURL, "https://generativelanguage.googleapis.com/v1beta/openai")
        TestSupport.expectEqual(provider.defaultTranscriptionModel, "gemini-2.5-flash")
        TestSupport.expectEqual(provider.defaultPostProcessingModel, "gemini-2.5-flash-lite")
        TestSupport.expect(provider.requiresAPIKey, "Gemini needs an API key")
        TestSupport.expectEqual(provider.keyAccount, "voxflow_api_key")
    }

    private static func testGroqDefaults() {
        let provider = AIProvider.groq
        TestSupport.expectEqual(provider.defaultBaseURL, "https://api.groq.com/openai/v1")
        TestSupport.expectEqual(provider.defaultTranscriptionModel, "whisper-large-v3-turbo")
        TestSupport.expectEqual(provider.defaultPostProcessingModel, "openai/gpt-oss-20b")
        TestSupport.expect(provider.requiresAPIKey, "Groq needs an API key")
        TestSupport.expectEqual(provider.keyAccount, "voxflow_api_key_groq")
        TestSupport.expect(provider.keyAccount != AIProvider.gemini.keyAccount, "Groq must not clobber the Gemini key")
    }

    private static func testOllamaDefaults() {
        let provider = AIProvider.ollama
        TestSupport.expectEqual(provider.defaultBaseURL, "http://localhost:11434/v1")
        TestSupport.expect(!provider.requiresAPIKey, "Ollama is local — no key")
        TestSupport.expect(provider.keyAccount == nil, "Ollama has no Keychain account")
    }

    private static func testCustomDefaults() {
        let provider = AIProvider.custom
        TestSupport.expectEqual(provider.defaultBaseURL, "")
        TestSupport.expect(!provider.requiresAPIKey, "Custom endpoints may run without a key")
        TestSupport.expectEqual(provider.keyAccount, "voxflow_api_key_custom")
    }

    private static func testUnknownStoredValueFallsBackToGemini() {
        TestSupport.expectEqual(AIProvider.from(stored: "gemini"), .gemini)
        TestSupport.expectEqual(AIProvider.from(stored: "GROQ"), .groq)
        TestSupport.expectEqual(AIProvider.from(stored: "  ollama  "), .ollama)
        TestSupport.expectEqual(AIProvider.from(stored: "nonsense"), .gemini)
        TestSupport.expectEqual(AIProvider.from(stored: ""), .gemini)
    }

    private static func testThemePersistenceMapping() {
        TestSupport.expectEqual(AppTheme.from(stored: "light"), .light)
        TestSupport.expectEqual(AppTheme.from(stored: "dark"), .dark)
        TestSupport.expectEqual(AppTheme.from(stored: "system"), .system)
        TestSupport.expectEqual(AppTheme.from(stored: "nonsense"), .light)
        TestSupport.expectEqual(AppTheme.from(stored: ""), .light)
        TestSupport.expect(AppTheme.system.forcesDark == nil, "System follows macOS")
        TestSupport.expectEqual(AppTheme.light.forcesDark, false)
        TestSupport.expectEqual(AppTheme.dark.forcesDark, true)
        TestSupport.expectEqual(AppTheme.light.storedValue, "light")
    }
}
