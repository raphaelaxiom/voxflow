import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Dashboard sections. The sidebar lists these; every section is backed
/// by real data and every button does real work — no placeholders.
enum DashboardSection: String, CaseIterable, Identifiable {
    case dictation
    case notetaker
    case insights
    case dictionary
    case snippets
    case style
    case transforms
    case scratchpad
    case settings
    case help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictation: return "Dictation"
        case .notetaker: return "Notetaker"
        case .insights: return "Insights"
        case .dictionary: return "Dictionary"
        case .snippets: return "Snippets"
        case .style: return "Style"
        case .transforms: return "Transforms"
        case .scratchpad: return "Scratchpad"
        case .settings: return "Settings"
        case .help: return "Help"
        }
    }

    var icon: String {
        switch self {
        case .dictation: return "mic"
        case .notetaker: return "note.text"
        case .insights: return "chart.bar"
        case .dictionary: return "book"
        case .snippets: return "scissors"
        case .style: return "textformat"
        case .transforms: return "wand.and.stars"
        case .scratchpad: return "square.and.pencil"
        case .settings: return "gearshape"
        case .help: return "questionmark.circle"
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var notesStore = NotesStore()
    @StateObject private var scratchpadStore = ScratchpadStore()

    @State private var selectedSection: DashboardSection? = .dictation
    @State private var searchText = ""
    @State private var copiedItemID: UUID?
    @State private var showingClearConfirm = false
    @State private var selectedNoteID: UUID?
    @State private var editingNoteBody = ""
    @State private var newTerm = ""
    @State private var editingMacro: VoiceMacro?
    @State private var macroCommand = ""
    @State private var macroPayload = ""
    @State private var transformSourceText = ""
    @State private var selectedTransform: TextTransform = TextTransforms.all[0]
    @State private var transformResult: String?
    @State private var transformError: String?
    @State private var isTransforming = false
    @State private var copiedTransformResult = false
    @State private var audioPlayer: AVAudioPlayer?
    @State private var playingItemID: UUID?

    private var summary: DashboardStats.Summary {
        DashboardStats.compute(items: appState.pipelineHistory)
    }

    private var todayItems: [PipelineHistoryItem] {
        let calendar = Calendar.current
        let items = appState.pipelineHistory.filter { calendar.isDateInToday($0.timestamp) }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter {
            DashboardStats.displayText(for: $0).localizedCaseInsensitiveContains(query)
        }
    }

    private var firstName: String {
        let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !full.isEmpty else { return "there" }
        return full.split(separator: " ").first.map(String.init) ?? "there"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .frame(minWidth: 1080, minHeight: 680)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                Text("Voxflow")
                    .font(.system(size: 20, weight: .bold, design: .serif))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            List(DashboardSection.allCases, id: \.self, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
                    .font(.system(size: 14))
            }
            .listStyle(.sidebar)

            VStack(alignment: .leading, spacing: 2) {
                Text("Voxflow \(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Created by Raphael Axiom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Developed by DKH Verse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .dictation, .none:
            dictationSection
        case .notetaker:
            notetakerSection
        case .insights:
            insightsSection
        case .dictionary:
            dictionarySection
        case .snippets:
            snippetsSection
        case .style:
            styleSection
        case .transforms:
            transformsSection
        case .scratchpad:
            scratchpadSection
        case .settings:
            dashboardSettingsSection
        case .help:
            helpSection
        }
    }

    // MARK: - Dictation (main dashboard)

    private var dictationSection: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome back, \(firstName)")
                        .font(.system(size: 30, weight: .bold, design: .serif))
                    Text("Your dictations, stats, and tools — all in one place.")
                        .foregroundStyle(.secondary)
                }

                heroBanner

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("TODAY")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search today's dictations", text: $searchText)
                                .textFieldStyle(.plain)
                                .frame(width: 220)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                    }

                    if todayItems.isEmpty {
                        VStack(spacing: 8) {
                            Text(searchText.isEmpty ? "No dictations yet today." : "No matches for your search.")
                                .foregroundStyle(.secondary)
                            if searchText.isEmpty {
                                Text("Hold Fn and speak — your words will appear here.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 32)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(todayItems) { item in
                                    dictationRow(item)
                                    if item.id != todayItems.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            statsColumn
                .frame(width: 200)
        }
        .padding(24)
        .confirmationDialog(
            "Clear all history?",
            isPresented: $showingClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear history", role: .destructive) {
                appState.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every saved dictation and its audio. This cannot be undone.")
        }
    }

    private var heroBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Make Voxflow sound like you")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                Text("Pick a writing style and Voxflow will shape every dictation to match it.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                Button("Start now") {
                    selectedSection = .style
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white))
                .foregroundStyle(.black)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(
                    colors: [Color(red: 0.08, green: 0.08, blue: 0.10), Color(red: 0.05, green: 0.35, blue: 0.34)],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
        )
    }

    private func dictationRow(_ item: PipelineHistoryItem) -> some View {
        let text = DashboardStats.displayText(for: item)
        return HStack(alignment: .top, spacing: 12) {
            Text(item.timestamp, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(text)
                .font(.body)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if item.audioFileName != nil {
                    Button {
                        togglePlayback(for: item)
                    } label: {
                        Image(systemName: playingItemID == item.id ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.plain)
                    .help(playingItemID == item.id ? "Stop playback" : "Play recording")
                }
                Button {
                    appState.copyHistoryItem(item)
                    copiedItemID = item.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if copiedItemID == item.id { copiedItemID = nil }
                    }
                } label: {
                    Image(systemName: copiedItemID == item.id ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy text")
                Button {
                    appState.deleteHistoryItem(item)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Delete this dictation")
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }

    private var statsColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                statRow(
                    value: DashboardStats.formattedWordCount(summary.totalWords),
                    label: "total words"
                )
                statRow(
                    value: summary.wordsPerMinute.map { "\(Int($0.rounded()))" } ?? "—",
                    label: "wpm"
                )
                statRow(value: "\(summary.dayStreak)", label: "day streak")
                statRow(value: "\(summary.dictationsToday)", label: "dictations today")
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05)))

            VStack(alignment: .leading, spacing: 10) {
                Button("Export history") {
                    exportHistory()
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                Button("Clear history") {
                    showingClearConfirm = true
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private func statRow(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.system(size: 26, weight: .medium, design: .serif))
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func exportHistory() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "voxflow-history.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try appState.exportHistoryJSON().write(to: url, options: .atomic)
        } catch {
            appState.errorMessage = "Could not export history: \(error.localizedDescription)"
        }
    }

    private func togglePlayback(for item: PipelineHistoryItem) {
        if playingItemID == item.id {
            audioPlayer?.stop()
            audioPlayer = nil
            playingItemID = nil
            return
        }
        guard let url = appState.audioURL(for: item) else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            playingItemID = item.id
        } catch {
            appState.errorMessage = "Could not play recording: \(error.localizedDescription)"
        }
    }

    // MARK: - Notetaker

    private var notetakerSection: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Notetaker")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                    Spacer()
                    Button("New note") {
                        let note = notesStore.addNote()
                        selectedNoteID = note.id
                        editingNoteBody = note.body
                    }
                    .buttonStyle(.borderedProminent)
                }
                if notesStore.notes.isEmpty {
                    Text("No notes yet. Create one to capture anything worth keeping.")
                        .foregroundStyle(.secondary)
                } else {
                    List(notesStore.notes, id: \.id, selection: $selectedNoteID) { note in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title)
                                .lineLimit(1)
                            Text(note.updatedAt, format: .dateTime.day().month().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 260)
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                if let selectedNoteID, let note = notesStore.notes.first(where: { $0.id == selectedNoteID }) {
                    HStack {
                        Text(note.title)
                            .font(.system(size: 18, weight: .semibold, design: .serif))
                            .lineLimit(1)
                        Spacer()
                        Button("Delete") {
                            notesStore.deleteNote(note)
                            self.selectedNoteID = nil
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                    TextEditor(text: $editingNoteBody)
                        .font(.body)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onChange(of: editingNoteBody) { body in
                            var updated = note
                            updated.body = body
                            notesStore.updateNote(updated)
                        }
                } else {
                    Text("Select a note to read or edit it.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .padding(20)
        }
        .onChange(of: selectedNoteID) { id in
            if let id, let note = notesStore.notes.first(where: { $0.id == id }) {
                editingNoteBody = note.body
            }
        }
    }

    // MARK: - Insights

    private var insightsSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Insights")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                HStack(spacing: 16) {
                    insightCard(value: DashboardStats.formattedWordCount(summary.totalWords), label: "Total words")
                    insightCard(value: summary.wordsPerMinute.map { "\(Int($0.rounded()))" } ?? "—", label: "Words per minute")
                    insightCard(value: "\(summary.dayStreak)", label: "Day streak")
                    insightCard(value: "\(summary.totalDictations)", label: "Total dictations")
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Words per day — last 14 days")
                        .font(.headline)
                    let maxWords = max(1, summary.wordsPerDay.map(\.words).max() ?? 1)
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(summary.wordsPerDay, id: \.day) { entry in
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(entry.words > 0 ? Color.accentColor : Color.primary.opacity(0.12))
                                    .frame(width: 22, height: max(4, CGFloat(entry.words) / CGFloat(maxWords) * 110))
                                Text(entry.day, format: .dateTime.day())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .help("\(DashboardStats.formattedWordCount(entry.words)) words, \(entry.dictations) dictations")
                        }
                    }
                    .frame(height: 140, alignment: .bottom)
                    Text("Hover a bar for the exact count.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func insightCard(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .serif))
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05)))
    }

    // MARK: - Dictionary

    private var dictionarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dictionary")
                .font(.system(size: 24, weight: .bold, design: .serif))
            Text("Words and names Voxflow spells exactly as you wrote them when cleaning dictation.")
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("Add a word or name", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTerm() }
                Button("Add") { addTerm() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            let terms = appState.customVocabulary
                .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if terms.isEmpty {
                Text("No custom words yet.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(terms, id: \.self) { term in
                            HStack {
                                Text(term)
                                Spacer()
                                Button {
                                    removeTerm(term)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        var terms = appState.customVocabulary
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !terms.contains(where: { $0.lowercased() == term.lowercased() }) {
            terms.append(term)
            appState.customVocabulary = terms.joined(separator: "\n")
        }
        newTerm = ""
    }

    private func removeTerm(_ term: String) {
        let terms = appState.customVocabulary
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != term }
        appState.customVocabulary = terms.joined(separator: "\n")
    }

    // MARK: - Snippets

    private var snippetsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Snippets")
                .font(.system(size: 24, weight: .bold, design: .serif))
            Text("Say a trigger phrase while dictating and Voxflow pastes its snippet text.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Trigger phrase (what you say)", text: $macroCommand)
                    .textFieldStyle(.roundedBorder)
                TextField("Snippet text (what gets pasted)", text: $macroPayload)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button(editingMacro == nil ? "Add snippet" : "Save changes") {
                        saveMacro()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        macroCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || macroPayload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    if editingMacro != nil {
                        Button("Cancel") {
                            editingMacro = nil
                            macroCommand = ""
                            macroPayload = ""
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))

            if appState.voiceMacros.isEmpty {
                Text("No snippets yet.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(appState.voiceMacros) { macro in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(macro.command)
                                        .font(.headline)
                                    Text(macro.payload)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                HStack(spacing: 8) {
                                    Button("Copy") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(macro.payload, forType: .string)
                                    }
                                    .buttonStyle(.plain)
                                    Button("Edit") {
                                        editingMacro = macro
                                        macroCommand = macro.command
                                        macroPayload = macro.payload
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        appState.voiceMacros.removeAll { $0.id == macro.id }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                }
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 10)
                            Divider()
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func saveMacro() {
        let command = macroCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = macroPayload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !payload.isEmpty else { return }
        if let editingMacro {
            if let index = appState.voiceMacros.firstIndex(where: { $0.id == editingMacro.id }) {
                appState.voiceMacros[index] = VoiceMacro(id: editingMacro.id, command: command, payload: payload)
            }
        } else {
            appState.voiceMacros.append(VoiceMacro(command: command, payload: payload))
        }
        editingMacro = nil
        macroCommand = ""
        macroPayload = ""
    }

    // MARK: - Style

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Style")
                .font(.system(size: 24, weight: .bold, design: .serif))
            Text("How Voxflow shapes your dictation. Applies to new dictations.")
                .foregroundStyle(.secondary)
            ForEach(StylePresets.all) { preset in
                Button {
                    appState.activeStylePresetID = preset.id
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: appState.activeStylePresetID == preset.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(appState.activeStylePresetID == preset.id ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                                .font(.headline)
                            Text(preset.description)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(appState.activeStylePresetID == preset.id ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Transforms

    private var transformsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transforms")
                .font(.system(size: 24, weight: .bold, design: .serif))
            Text("Rewrite existing text with the same engine that cleans your dictation.")
                .foregroundStyle(.secondary)

            if appState.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add your Gemini API key to use transforms.")
                        .foregroundStyle(.secondary)
                    Button("Open Setup") {
                        NotificationCenter.default.post(name: .showSetup, object: nil)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                HStack(spacing: 8) {
                    Button("Use last dictation") {
                        if let latest = appState.pipelineHistory.first(where: { !DashboardStats.displayText(for: $0).isEmpty }) {
                            transformSourceText = DashboardStats.displayText(for: latest)
                        }
                    }
                    Button("Clear") {
                        transformSourceText = ""
                        transformResult = nil
                        transformError = nil
                    }
                    .buttonStyle(.plain)
                }
                TextEditor(text: $transformSourceText)
                    .font(.body)
                    .frame(height: 130)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15), lineWidth: 1))

                HStack(spacing: 8) {
                    ForEach(TextTransforms.all) { transform in
                        Button(transform.name) {
                            selectedTransform = transform
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(selectedTransform.id == transform.id ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(selectedTransform.id == transform.id ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                        )
                    }
                }
                Button(isTransforming ? "Running…" : "Run transform") {
                    runTransform()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTransforming || transformSourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let transformError {
                    Text(transformError)
                        .foregroundStyle(.red)
                }
                if let transformResult {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Result")
                            .font(.headline)
                        Text(transformResult)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
                        HStack(spacing: 12) {
                            Button(copiedTransformResult ? "Copied!" : "Copy result") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(transformResult, forType: .string)
                                copiedTransformResult = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    copiedTransformResult = false
                                }
                            }
                            Button("Save as note") {
                                let note = notesStore.addNote()
                                var updated = note
                                updated.body = transformResult
                                notesStore.updateNote(updated)
                                selectedNoteID = note.id
                                selectedSection = .notetaker
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func runTransform() {
        let source = transformSourceText
        let transform = selectedTransform
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isTransforming = true
        transformError = nil
        transformResult = nil
        Task {
            do {
                let result = try await appState.runTransform(sourceText: source, instruction: transform.instruction)
                await MainActor.run {
                    transformResult = result
                    isTransforming = false
                }
            } catch {
                await MainActor.run {
                    transformError = error.localizedDescription
                    isTransforming = false
                }
            }
        }
    }

    // MARK: - Scratchpad

    private var scratchpadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Scratchpad")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                Spacer()
                Text("\(DashboardStats.wordCount(of: scratchpadStore.text)) words")
                    .foregroundStyle(.secondary)
            }
            Text("Free-form notes. Saved automatically as you type.")
                .foregroundStyle(.secondary)
            TextEditor(text: $scratchpadStore.text)
                .font(.body)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Spacer(minLength: 0)
        }
        .padding(24)
    }

    // MARK: - Settings (dashboard)

    private var dashboardSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.system(size: 24, weight: .bold, design: .serif))
            VStack(alignment: .leading, spacing: 4) {
                Text("Voxflow \(appVersion)")
                    .font(.headline)
                Text("Created by Raphael Axiom")
                    .foregroundStyle(.secondary)
                Text("Developed by DKH Verse")
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button("Open Settings") {
                NotificationCenter.default.post(name: .showSettings, object: nil)
            }
            Button("Open Setup") {
                NotificationCenter.default.post(name: .showSetup, object: nil)
            }
            Button("Open Voxflow on GitHub") {
                if let url = URL(string: "https://github.com/raphaelaxiom/voxflow") {
                    NSWorkspace.shared.open(url)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Help

    private var helpSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Help")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                helpParagraph(
                    title: "Dictate anywhere",
                    body: "Hold Fn and speak, or tap Cmd-Fn to toggle. Voxflow transcribes with Gemini, corrects the text, and pastes it where your cursor is."
                )
                helpParagraph(
                    title: "Text not pasted?",
                    body: "If your cursor was not in a text field, the dictation is still saved to history and a pill appears: \"Text not pasted. Click here to copy text.\" Click it to copy."
                )
                helpParagraph(
                    title: "Your API key",
                    body: "Voxflow uses your own Gemini API key. Get one free from Google AI Studio, then enter it in Setup. Your key stays in your Mac's Keychain."
                )
                helpParagraph(
                    title: "History and privacy",
                    body: "Dictations and audio stay on your Mac. Nothing is sent anywhere except the transcription and cleanup requests to your configured provider."
                )
                Button("Report an issue on GitHub") {
                    if let url = URL(string: "https://github.com/raphaelaxiom/voxflow/issues/new") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func helpParagraph(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(body)
                .foregroundStyle(.secondary)
        }
    }
}
