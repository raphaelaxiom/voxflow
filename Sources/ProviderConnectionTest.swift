import Foundation
import os.log

private let connectionTestLog = OSLog(subsystem: "com.voxflow.app", category: "ConnectionTest")

/// "Test connection" for the selected provider (Settings → AI Provider).
/// Reports the REAL result in plain words — never a bare "404 Not Found".
enum ProviderConnectionTest {
    static func test(
        provider: AIProvider,
        baseURL: String,
        apiKey: String,
        polishModel: String,
        transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await LLMAPITransport.data(for: request)
        }
    ) async -> (ok: Bool, message: String) {
        let trimmedBase = baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        let effectiveBase = trimmedBase.isEmpty ? provider.defaultBaseURL : trimmedBase
        guard let base = URL(string: effectiveBase), base.host != nil else {
            return (false, "The Base URL is not a valid URL. Check it in Settings.")
        }
        if provider == .ollama {
            return await testOllama(base: base, polishModel: polishModel, transport: transport)
        }
        return await testKeyedProvider(
            provider: provider,
            base: base,
            apiKey: apiKey,
            transport: transport
        )
    }

    // MARK: - Ollama

    private static func testOllama(
        base: URL,
        polishModel: String,
        transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) async -> (ok: Bool, message: String) {
        // Ollama's native API lives at the server root (/api/tags), not
        // under the OpenAI-compatible /v1 prefix. Drop a trailing /v1.
        var root = base
        if root.path == "/v1" {
            root = root.deletingLastPathComponent()
        } else if root.path.hasSuffix("/v1") {
            root = URL(string: String(root.absoluteString.dropLast("/v1".count))) ?? root
        }
        let hostPort = root.host.map { host in
            root.port.map { "\(host):\($0)" } ?? host
        } ?? "localhost:11434"

        // Native API first: it lists installed models, so a missing polish
        // model becomes an exact `ollama pull <model>` instruction.
        let tagsURL = root.appendingPathComponent("api").appendingPathComponent("tags")
        var tagsRequest = URLRequest(url: tagsURL)
        tagsRequest.timeoutInterval = 10
        do {
            let (data, response) = try await transport(tagsRequest)
            guard let http = response as? HTTPURLResponse else {
                return (false, "Ollama responded, but the reply was unreadable. Is something else running on \(hostPort)?")
            }
            if http.statusCode == 200 {
                let models = parseOllamaModelNames(from: data)
                let wanted = polishModel.trimmingCharacters(in: .whitespacesAndNewlines)
                if !wanted.isEmpty, !models.contains(where: { matchesOllamaModel($0, wanted: wanted) }) {
                    return (false, "Ollama is running, but model '\(wanted)' is not pulled — run `ollama pull \(wanted)`.")
                }
                return (true, "Connected — Ollama is running (\(models.count) model\(models.count == 1 ? "" : "s") available).")
            }
            // Non-200 from the native API: fall through to the
            // OpenAI-compatible check before giving up.
            os_log(.info, log: connectionTestLog, "/api/tags returned HTTP %ld; trying /v1/models", http.statusCode)
        } catch {
            return (false, "Ollama is not running on \(hostPort) — start it with `ollama serve`.")
        }

        let modelsURL = root.appendingPathComponent("v1").appendingPathComponent("models")
        var modelsRequest = URLRequest(url: modelsURL)
        modelsRequest.timeoutInterval = 10
        do {
            let (_, response) = try await transport(modelsRequest)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return (true, "Connected — server responded at /v1/models (not Ollama's native API).")
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (false, "Server responded with HTTP \(status) — is this really Ollama on \(hostPort)?")
        } catch {
            return (false, "Ollama is not running on \(hostPort) — start it with `ollama serve`.")
        }
    }

    private static func parseOllamaModelNames(from data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return []
        }
        return models.compactMap { $0["name"] as? String }
    }

    /// Ollama model names carry a tag ("llama3.2:latest"). A wanted model
    /// matches when the full names match OR the base names (before ":")
    /// match — so "llama3.2" matches "llama3.2:latest" and vice versa.
    private static func matchesOllamaModel(_ listed: String, wanted: String) -> Bool {
        if listed == wanted { return true }
        let listedBase = listed.split(separator: ":").first.map(String.init) ?? listed
        let wantedBase = wanted.split(separator: ":").first.map(String.init) ?? wanted
        return listedBase == wantedBase
    }

    // MARK: - Keyed providers (Gemini / Groq / Custom)

    private static func testKeyedProvider(
        provider: AIProvider,
        base: URL,
        apiKey: String,
        transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) async -> (ok: Bool, message: String) {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = base.host ?? "the provider"
        if key.isEmpty {
            // A local custom endpoint may run without a key — probe
            // reachability instead of demanding one.
            let isLocal = host == "localhost" || host == "127.0.0.1" || host == "::1"
            if isLocal {
                var request = URLRequest(url: base.appendingPathComponent("models"))
                request.timeoutInterval = 10
                do {
                    let (_, response) = try await transport(request)
                    if response is HTTPURLResponse {
                        return (true, "Connected — local server responded.")
                    }
                    return (false, "Local server responded, but the reply was unreadable.")
                } catch {
                    return (false, "Could not reach \(host) — check the Base URL and that the server is running.")
                }
            }
            return (false, "Enter an API key first.")
        }

        var request = URLRequest(url: base.appendingPathComponent("models"))
        request.timeoutInterval = 10
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await transport(request)
            guard let http = response as? HTTPURLResponse else {
                return (false, "Server responded, but the reply was unreadable.")
            }
            switch http.statusCode {
            case 200:
                return (true, "Connected — \(provider.shortTitle) responded.")
            case 401:
                return (false, "Invalid API key — check the key in Settings.")
            case 404:
                return (false, "Endpoint not found (404) — check the Base URL in Settings.")
            default:
                return (false, "Server returned HTTP \(http.statusCode).")
            }
        } catch {
            return (false, "Could not reach \(host) — check the Base URL / network.")
        }
    }
}
