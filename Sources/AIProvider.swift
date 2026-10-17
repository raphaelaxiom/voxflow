import Foundation

/// The AI provider powering transcription + polish. The picker in Settings
/// switches the whole pipeline: base URL, models, and the per-provider API
/// key (keys live in the Keychain via AppSettingsStorage, never in code).
/// The pipeline itself only ever reads `apiBaseURL` / model fields on
/// AppState, so switching the provider IS switching the pipeline — there
/// is no second, parallel provider system.
enum AIProvider: String, CaseIterable, Identifiable {
    case gemini
    case groq
    case ollama
    case custom

    var id: String { rawValue }

    /// Compact label for the segmented picker.
    var shortTitle: String {
        switch self {
        case .gemini: return "Gemini"
        case .groq: return "Groq"
        case .ollama: return "Ollama"
        case .custom: return "Custom"
        }
    }

    var title: String {
        switch self {
        case .gemini: return "Gemini"
        case .groq: return "Groq"
        case .ollama: return "Ollama (local)"
        case .custom: return "Custom endpoint"
        }
    }

    /// Short caption shown under the picker so the choice is not a mystery.
    var subtitle: String {
        switch self {
        case .gemini:
            return "Google Gemini — default. Transcription + polish over Gemini's OpenAI-compatible endpoint."
        case .groq:
            return "Groq — Whisper transcription + gpt-oss polish. Needs a Groq API key."
        case .ollama:
            return "Local Ollama server — polish + transforms run locally. Transcription needs an audio-capable OpenAI-compatible endpoint; stock Ollama serves chat models only."
        case .custom:
            return "Any OpenAI-compatible endpoint (LM Studio, vLLM, …). Enter its base URL below."
        }
    }

    /// Default base URL applied when this provider is picked.
    var defaultBaseURL: String {
        switch self {
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .groq:
            return "https://api.groq.com/openai/v1"
        case .ollama:
            return "http://localhost:11434/v1"
        case .custom:
            return ""
        }
    }

    var defaultTranscriptionModel: String {
        switch self {
        case .gemini: return "gemini-2.5-flash"
        case .groq: return "whisper-large-v3-turbo"
        case .ollama: return "whisper-large-v3"
        case .custom: return "whisper-large-v3"
        }
    }

    /// The polish (transcript cleanup) model. Gemini uses flash-lite: same
    /// quality class for short cleanup text, noticeably faster.
    var defaultPostProcessingModel: String {
        switch self {
        case .gemini: return "gemini-2.5-flash-lite"
        case .groq: return "openai/gpt-oss-20b"
        case .ollama: return "llama3.1"
        case .custom: return "openai/gpt-oss-20b"
        }
    }

    var defaultPostProcessingFallbackModel: String {
        switch self {
        case .gemini: return "gemini-3-flash-preview"
        case .groq: return "qwen/qwen3.8-27b"
        case .ollama: return "qwen3:8b"
        case .custom: return "qwen/qwen3.8-27b"
        }
    }

    var defaultContextModel: String {
        switch self {
        case .gemini: return "gemini-2.5-flash"
        case .groq: return "qwen/qwen3.8-27b"
        case .ollama: return "llama3.1"
        case .custom: return "qwen/qwen3.8-27b"
        }
    }

    /// Whether this provider needs an API key before the pipeline can run.
    /// Ollama and Custom (local servers) work without one.
    var requiresAPIKey: Bool {
        switch self {
        case .gemini, .groq: return true
        case .ollama, .custom: return false
        }
    }

    /// Keychain account holding this provider's API key. Gemini reuses the
    /// historical `voxflow_api_key` account so existing installs keep their
    /// key when the provider picker ships.
    var keyAccount: String? {
        switch self {
        case .gemini: return "voxflow_api_key"
        case .groq: return "voxflow_api_key_groq"
        case .ollama: return nil
        case .custom: return "voxflow_api_key_custom"
        }
    }

    /// UserDefaults persistence value.
    var storedValue: String { rawValue }

    /// Unknown stored values fall back to Gemini (the default) rather than
    /// crashing or picking a provider the user never chose.
    static func from(stored: String?) -> AIProvider {
        guard let stored else { return .gemini }
        return AIProvider(rawValue: stored.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .gemini
    }
}

/// Light / Dark / System appearance. Persisted in UserDefaults; applied via
/// `preferredColorScheme` on the Dashboard window's root view. `nil`
/// color-scheme mapping (System) is resolved at the call site so this type
/// stays Foundation-only and unit-testable.
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// `nil` = follow the system. Otherwise true = force dark, false = force light.
    var forcesDark: Bool? {
        switch self {
        case .system: return nil
        case .light: return false
        case .dark: return true
        }
    }

    /// UserDefaults persistence value.
    var storedValue: String { rawValue }

    static func from(stored: String?) -> AppTheme {
        guard let stored else { return .light }
        return AppTheme(rawValue: stored.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .light
    }
}
