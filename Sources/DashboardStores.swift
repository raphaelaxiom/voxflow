import Foundation
import Combine

// MARK: - Notetaker notes

/// One saved note. The title is the first line of the body, kept in sync
/// by the dashboard editor so the list always shows a real title.
struct DashboardNote: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var body: String
    var updatedAt: Date

    var title: String {
        let firstLine = body.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled note" : trimmed
    }
}

/// Notes persisted as JSON in Application Support. No cloud, no account.
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [DashboardNote] = []

    init() {
        load()
    }

    func addNote() -> DashboardNote {
        let note = DashboardNote(body: "", updatedAt: Date())
        notes.insert(note, at: 0)
        save()
        return note
    }

    func updateNote(_ note: DashboardNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        var updated = note
        updated.updatedAt = Date()
        notes[index] = updated
        notes.sort { $0.updatedAt > $1.updatedAt }
        save()
    }

    func deleteNote(_ note: DashboardNote) {
        notes.removeAll { $0.id == note.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL()) else { return }
        guard let decoded = try? JSONDecoder().decode([DashboardNote].self, from: data) else { return }
        notes = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? FileManager.default.createDirectory(
            at: Self.fileURL().deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: Self.fileURL(), options: .atomic)
    }

    private static func fileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Voxflow"
        return appSupport
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("Notes.json")
    }
}

// MARK: - Scratchpad

/// A single free-text scratchpad, persisted to disk on every edit.
final class ScratchpadStore: ObservableObject {
    @Published var text: String = "" {
        didSet {
            guard hasLoaded else { return }
            save()
        }
    }
    private var hasLoaded = false

    init() {
        load()
        hasLoaded = true
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL()) else { return }
        text = String(data: data, encoding: .utf8) ?? ""
    }

    private func save() {
        try? FileManager.default.createDirectory(
            at: Self.fileURL().deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? text.data(using: .utf8)?.write(to: Self.fileURL(), options: .atomic)
    }

    private static func fileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Voxflow"
        return appSupport
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("Scratchpad.txt")
    }
}

// MARK: - Style presets

/// A writing style for dictation cleanup. The Default preset uses the
/// standard cleanup prompt unchanged; every other preset appends its
/// directive to that prompt.
struct StylePreset: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let systemPromptDirective: String
}

enum StylePresets {
    static let all: [StylePreset] = [
        StylePreset(
            id: "default",
            name: "Default",
            description: "Balanced cleanup with natural layout.",
            systemPromptDirective: ""
        ),
        StylePreset(
            id: "concise",
            name: "Concise",
            description: "Short, tight wording. Cut anything that does not change the meaning.",
            systemPromptDirective: "Keep the output short and to the point. Cut anything that does not change the meaning. Prefer short sentences."
        ),
        StylePreset(
            id: "detailed",
            name: "Detailed",
            description: "Keep every detail, example, and qualifier from the dictation.",
            systemPromptDirective: "Keep all substance from the dictation. Do not compress away details, examples, or qualifiers."
        ),
        StylePreset(
            id: "email",
            name: "Email",
            description: "Shape the output as an email with salutation, body, and closing.",
            systemPromptDirective: "Format the output as an email: salutation on the first line, a blank line, then the body paragraphs, and the closing on its own final paragraph when the speaker dictated one."
        ),
        StylePreset(
            id: "bullets",
            name: "Bullet points",
            description: "Present multi-point content as a bulleted list.",
            systemPromptDirective: "When the content has multiple points, present them as a bulleted list. Keep each bullet to one clear line."
        ),
    ]

    static func preset(id: String) -> StylePreset {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: - Transforms

/// A one-tap rewrite applied to existing text through the edit-mode
/// pipeline. The instruction is sent as the voice command, so the same
/// guardrails apply as spoken edit commands.
struct TextTransform: Identifiable, Equatable {
    let id: String
    let name: String
    let instruction: String
}

enum TextTransforms {
    static let all: [TextTransform] = [
        TextTransform(
            id: "shorter",
            name: "Make shorter",
            instruction: "Make this shorter while keeping all essential meaning."
        ),
        TextTransform(
            id: "bullets",
            name: "Bullet points",
            instruction: "Rewrite this as a bulleted list, one point per bullet."
        ),
        TextTransform(
            id: "grammar",
            name: "Fix grammar",
            instruction: "Fix the grammar and punctuation without changing the meaning."
        ),
        TextTransform(
            id: "formal",
            name: "Formal tone",
            instruction: "Rewrite this in a formal, professional tone."
        ),
        TextTransform(
            id: "casual",
            name: "Casual tone",
            instruction: "Rewrite this in a relaxed, casual tone."
        ),
        TextTransform(
            id: "summarize",
            name: "Summarize",
            instruction: "Summarize this in one short paragraph."
        ),
    ]
}
