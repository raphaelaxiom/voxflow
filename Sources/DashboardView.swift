import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers
import os.log

private let dashboardLog = OSLog(subsystem: "com.voxflow.app", category: "Dashboard")

/// Dashboard sections. The floating bottom tab bar lists these; every
/// section is backed by real data and every button does real work —
/// no placeholders. (The old left sidebar is gone; its "Voxfl ow" wrap
/// bug died with it.)
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
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var notesStore = NotesStore()
    @StateObject private var scratchpadStore = ScratchpadStore()

    @State private var selectedSection: DashboardSection = .dictation
    @State private var searchText = ""
    @State private var copiedItemID: UUID?
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
    @State private var toastMessage: String?

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

    /// Words spoken today, from the per-day breakdown.
    private var wordsToday: Int {
        let calendar = Calendar.current
        return summary.wordsPerDay.first { calendar.isDateInToday($0.day) }?.words ?? 0
    }

    /// Words-today vs yesterday as a fraction; nil when yesterday had no
    /// words (no meaningful comparison) so the delta row hides.
    private var wordsTodayDelta: Double? {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) else { return nil }
        let yesterdayWords = summary.wordsPerDay.first { calendar.isDate($0.day, inSameDayAs: yesterday) }?.words ?? 0
        guard yesterdayWords > 0 else { return nil }
        return Double(wordsToday - yesterdayWords) / Double(yesterdayWords)
    }

    private var firstName: String {
        let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !full.isEmpty else { return "there" }
        return full.split(separator: " ").first.map(String.init) ?? "there"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var tabIndex: Binding<Int> {
        Binding(
            get: { DashboardSection.allCases.firstIndex(of: selectedSection) ?? 0 },
            set: { selectedSection = DashboardSection.allCases[$0] }
        )
    }

    /// The theme picker's mapping: System = nil (follow macOS).
    private var themeColorScheme: ColorScheme? {
        switch appState.appTheme.forcesDark {
        case .some(true): return .dark
        case .some(false): return .light
        case .none: return nil
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.11, green: 0.11, blue: 0.12)
            : .voxflowPaper
    }

    private var dashboardBannerImage: NSImage? {
        if let url = Bundle.main.url(forResource: "DashboardBanner", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(named: "DashboardBanner")
    }

    var body: some View {
        // ONE scroll for the whole Dashboard (Issue 5 + history scroll):
        // a plain VStack with the tab bar pinned at the bottom. The old
        // ZStack(alignment: .bottom) let a taller-than-window content
        // VStack grow the ZStack past the window, pushing the tab bar
        // below the visible area with no way to scroll to it. Sections
        // render as plain content inside this single ScrollView — no
        // nested ScrollViews fighting each other.
        VStack(spacing: 0) {
            topBar
            statusBanner
            Group {
                if appState.showingSetupInline {
                    setupInlineSection
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        detailContent
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            CustomTabBar(
                selection: tabIndex,
                tabs: DashboardSection.allCases.map { (icon: $0.icon, label: $0.title) }
            )
            .frame(maxWidth: 800)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(backgroundColor)
        .preferredColorScheme(themeColorScheme)
        .frame(minWidth: 1080, minHeight: 680)
        .toast($toastMessage)
        .onAppear { selectedSection = appState.dashboardSection }
        .onChange(of: appState.dashboardSection) { section in
            selectedSection = section
        }
        .onChange(of: selectedSection) { section in
            appState.dashboardSection = section
        }
    }

    /// Visible status/error surface (Issue 3). The Dashboard previously
    /// NEVER displayed `appState.errorMessage` / recording state, so a
    /// failed "Start Dictating" click (permission missing, mic denied,
    /// provider error) looked identical to a dead button — the failure
    /// only showed in the menu-bar menu. Now every outcome is visible
    /// here, with a working action for permission errors and the real
    /// Copy button for paste failures.
    @ViewBuilder
    private var statusBanner: some View {
        if let error = appState.errorMessage, !error.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.subheadline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if error.localizedCaseInsensitiveContains("accessibility") {
                    Button("Open Accessibility Settings") {
                        appState.openAccessibilitySettings()
                    }
                    .buttonStyle(.voxflowGlass)
                } else if error.localizedCaseInsensitiveContains("microphone") {
                    Button("Open Microphone Settings") {
                        appState.openMicrophoneSettings()
                    }
                    .buttonStyle(.voxflowGlass)
                } else if error.localizedCaseInsensitiveContains("screen recording")
                            || error.localizedCaseInsensitiveContains("screenshot") {
                    Button("Open Screen Recording Settings") {
                        appState.openScreenCaptureSettings()
                    }
                    .buttonStyle(.voxflowGlass)
                }
                Button("Dismiss") {
                    appState.errorMessage = nil
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 24)
            .padding(.top, 8)
        } else if let pasteFailureText = appState.pasteFailureText, !pasteFailureText.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundStyle(.orange)
                Text("Text not pasted — your dictation was saved to history.")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Copy text") {
                    appState.copyPasteFailureText()
                }
                .buttonStyle(.pearl)
                Button("Dismiss") {
                    appState.dismissPasteFailure()
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 24)
            .padding(.top, 8)
        } else if appState.isRecording {
            HStack(spacing: 8) {
                Image(systemName: "record.circle")
                    .foregroundStyle(.red)
                Text("Recording… tap Stop in the menu bar or press your toggle shortcut to finish.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .padding(.horizontal, 24)
            .padding(.top, 4)
        } else if appState.isTranscribing {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Transcribing…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .padding(.horizontal, 24)
            .padding(.top, 4)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            LetterDropWordmark(
                text: "Voxflow",
                font: .system(size: 20, weight: .bold, design: .serif)
            )
            Spacer()
            Text("Voxflow \(appVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .dictation:
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

    /// Setup shown inline inside the Dashboard window (single-panel rule):
    /// no separate Setup window. The Back button returns to the section.
    private var setupInlineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Back to Dashboard") {
                    appState.showingSetupInline = false
                }
                .buttonStyle(.voxflowGlass)
                Spacer()
            }
            SetupView(onComplete: { appState.completeInlineSetup() })
        }
        .padding(24)
    }

    // MARK: - Dictation (main dashboard)

    private var dictationSection: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    StaggeredRiseText(
                        text: "Welcome back, \(firstName)",
                        font: .system(size: 30, weight: .bold, design: .serif)
                    )
                    EmergeText(
                        text: "Your dictations, stats, and tools — all in one place.",
                        font: .subheadline
                    )
                }

                heroBanner

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SkewInText(text: "TODAY", font: .caption.weight(.semibold))
                        CountBadge(count: summary.dictationsToday)
                        Spacer()
                        SearchField(query: $searchText)
                            .frame(width: 260)
                    }

                    if todayItems.isEmpty {
                        if searchText.isEmpty {
                            EmptyStateView(
                                icon: "mic",
                                title: "No dictations yet today.",
                                message: "Hold Fn and speak — your words will appear here.",
                                actionTitle: "See how it works",
                                action: { selectedSection = .help }
                            )
                        } else {
                            EmptyStateView(
                                icon: "magnifyingglass",
                                title: "No matches for your search.",
                                message: "Try different words, or clear the search."
                            )
                        }
                    } else {
                        HistoryList(items: todayItems) { item in
                            dictationRow(item)
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
    }

    private func copyHistoryItem(_ item: PipelineHistoryItem) {
        appState.copyHistoryItem(item)
        copiedItemID = item.id
        toastMessage = "Copied to clipboard"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedItemID == item.id { copiedItemID = nil }
        }
    }

    /// Hero: pastel gradient + cosmic mesh (banner only) + centered
    /// headline/subtext + two real actions + the original AI banner image
    /// in a rounded card below. Structure adapted from the 21st.dev hero;
    /// copy, imagery, and buttons are Voxflow's own.
    private var heroBanner: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient.voxflowHeroDark
            } else {
                LinearGradient.voxflowHero
            }
            CosmicGradientView()
            VStack(spacing: 12) {
                OutlinedWordmarkView(text: "VOXFLOW", fontSize: 20)
                WipeRevealText(
                    text: "Dictate. Don't type.",
                    font: .system(size: 28, weight: .bold, design: .serif),
                    color: .primary
                )
                EmergeText(
                    text: "Hold Fn and speak — Voxflow transcribes, cleans, and pastes your words anywhere.",
                    font: .subheadline
                )
                HStack(spacing: 12) {
                    Button("Start Dictating") {
                        // os_log at action entry: a tap is provable in
                        // Console even if the action then fails visibly
                        // (the failure now shows in the status banner).
                        os_log(.info, log: dashboardLog, "Start Dictating tapped")
                        appState.startDictationFromDashboard()
                    }
                    .buttonStyle(.pearl)
                    // Full-button hit-testing: the whole button rect —
                    // background and text — must fire the action.
                    .contentShape(Rectangle())
                    .allowsHitTesting(true)
                    Button("See how it works") {
                        os_log(.info, log: dashboardLog, "See how it works tapped")
                        selectedSection = .help
                    }
                    .buttonStyle(.voxflowGlass)
                    .contentShape(Rectangle())
                    .allowsHitTesting(true)
                }
                .padding(.top, 2)
                if let banner = dashboardBannerImage {
                    ImageFoldReveal {
                        Image(nsImage: banner)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 120)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                    }
                }
                FloatingIconsView()
            }
            .padding(24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
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
                    .contentShape(Rectangle())
                    .help(playingItemID == item.id ? "Stop playback" : "Play recording")
                }
                Button {
                    copyHistoryItem(item)
                } label: {
                    Image(systemName: copiedItemID == item.id ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Copy text")
                Button {
                    appState.deleteHistoryItem(item)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Delete this dictation")
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }

    private var statsColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatCard(
                label: "Words today",
                value: DashboardStats.formattedWordCount(wordsToday),
                delta: wordsTodayDelta
            )
            StatCard(
                label: "Total words",
                value: DashboardStats.formattedWordCount(summary.totalWords)
            )
            StatCard(
                label: "Words per minute",
                value: summary.wordsPerMinute.map { "\(Int($0.rounded()))" } ?? "—"
            )
            StatCard(
                label: "Day streak",
                value: "\(summary.dayStreak)"
            )
            VStack(alignment: .leading, spacing: 10) {
                SecondaryButton(title: "Export history") {
                    exportHistory()
                }
                DestructiveButton(title: "Clear history") {
                    appState.clearHistory()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
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
                    StaggeredRiseText(
                        text: "Notetaker",
                        font: .system(size: 24, weight: .bold, design: .serif)
                    )
                    Spacer()
                    Button("New note") {
                        let note = notesStore.addNote()
                        selectedNoteID = note.id
                        editingNoteBody = note.body
                    }
                    .buttonStyle(.pearl)
                }
                if notesStore.notes.isEmpty {
                    EmptyStateView(
                        icon: "note.text",
                        title: "No notes yet.",
                        message: "Create one to capture anything worth keeping.",
                        actionTitle: "New note",
                        action: {
                            let note = notesStore.addNote()
                            selectedNoteID = note.id
                            editingNoteBody = note.body
                        }
                    )
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
                        .frame(minHeight: 420)
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
        VStack(alignment: .leading, spacing: 24) {
            StaggeredRiseText(
                text: "Insights",
                font: .system(size: 24, weight: .bold, design: .serif)
            )
            HStack(spacing: 16) {
                HoverHighlightCard { StatCard(label: "Total words", value: DashboardStats.formattedWordCount(summary.totalWords)) }
                HoverHighlightCard { StatCard(label: "Words per minute", value: summary.wordsPerMinute.map { "\(Int($0.rounded()))" } ?? "—") }
                HoverHighlightCard { StatCard(label: "Day streak", value: "\(summary.dayStreak)") }
                HoverHighlightCard { StatCard(label: "Total dictations", value: "\(summary.totalDictations)") }
            }
            ContentCard(title: "Words per day — last 14 days") {
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

    // MARK: - Dictionary

    private var dictionarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            StaggeredRiseText(
                text: "Dictionary",
                font: .system(size: 24, weight: .bold, design: .serif)
            )
            Text("Words and names Voxflow spells exactly as you wrote them when cleaning dictation.")
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                StyledTextField(placeholder: "Add a word or name", text: $newTerm)
                Button("Add") { addTerm() }
                    .buttonStyle(.pearl)
                    .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            let terms = appState.customVocabulary
                .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if terms.isEmpty {
                EmptyStateView(
                    icon: "book",
                    title: "No custom words yet.",
                    message: "Add names and terms above and Voxflow will spell them exactly as you wrote them."
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
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
            StaggeredRiseText(
                text: "Snippets",
                font: .system(size: 24, weight: .bold, design: .serif)
            )
            Text("Say a trigger phrase while dictating and Voxflow pastes its snippet text.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                StyledTextField(placeholder: "Trigger phrase (what you say)", text: $macroCommand)
                StyledTextField(placeholder: "Snippet text (what gets pasted)", text: $macroPayload)
                HStack {
                    Button(editingMacro == nil ? "Add snippet" : "Save changes") {
                        saveMacro()
                    }
                    .buttonStyle(.pearl)
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
                        .buttonStyle(.voxflowGlass)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))

            if appState.voiceMacros.isEmpty {
                EmptyStateView(
                    icon: "scissors",
                    title: "No snippets yet.",
                    message: "Add a trigger phrase and its snippet text above."
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
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
                                        toastMessage = "Snippet copied"
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
            StaggeredRiseText(
                text: "Style",
                font: .system(size: 24, weight: .bold, design: .serif)
            )
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
            StaggeredRiseText(
                text: "Transforms",
                font: .system(size: 24, weight: .bold, design: .serif)
            )
            Text("Rewrite existing text with the same engine that cleans your dictation.")
                .foregroundStyle(.secondary)

            if appState.aiProvider.requiresAPIKey
                && appState.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add your \(appState.aiProvider.title) API key to use transforms.")
                        .foregroundStyle(.secondary)
                    Button("Open Setup") {
                        appState.showingSetupInline = true
                    }
                    .buttonStyle(.pearl)
                }
            } else {
                HStack(spacing: 8) {
                    Button("Use last dictation") {
                        if let latest = appState.pipelineHistory.first(where: { !DashboardStats.displayText(for: $0).isEmpty }) {
                            transformSourceText = DashboardStats.displayText(for: latest)
                        }
                    }
                    .buttonStyle(.voxflowGlass)
                    Button("Clear") {
                        transformSourceText = ""
                        transformResult = nil
                        transformError = nil
                    }
                    .buttonStyle(.voxflowGlass)
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
                .buttonStyle(.pearl)
                .disabled(isTransforming || transformSourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if isTransforming {
                    SkeletonRow()
                        .frame(maxWidth: 320, alignment: .leading)
                }
                if let transformError {
                    ErrorStateView(message: transformError, retry: runTransform)
                        .frame(maxWidth: 360, alignment: .leading)
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
                                toastMessage = "Result copied"
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    copiedTransformResult = false
                                }
                            }
                            .buttonStyle(.voxflowGlass)
                            Button("Save as note") {
                                let note = notesStore.addNote()
                                var updated = note
                                updated.body = transformResult
                                notesStore.updateNote(updated)
                                selectedNoteID = note.id
                                selectedSection = .notetaker
                            }
                            .buttonStyle(.voxflowGlass)
                        }
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
                StaggeredRiseText(
                    text: "Scratchpad",
                    font: .system(size: 24, weight: .bold, design: .serif)
                )
                Spacer()
                Text("\(DashboardStats.wordCount(of: scratchpadStore.text)) words")
                    .foregroundStyle(.secondary)
            }
            Text("Free-form notes. Saved automatically as you type.")
                .foregroundStyle(.secondary)
            TextEditor(text: $scratchpadStore.text)
                .font(.body)
                .frame(minHeight: 420)
            Spacer(minLength: 0)
        }
        .padding(24)
    }

    // MARK: - Settings (dashboard, inline — single-panel rule)

    private var dashboardSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                StaggeredRiseText(
                    text: "Settings",
                    font: .system(size: 24, weight: .bold, design: .serif)
                )
                Spacer()
                Button {
                    if let url = URL(string: "https://github.com/raphaelaxiom/voxflow") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    SettingsRow(icon: "link", tint: .blue, title: "Open Voxflow on GitHub")
                }
                .buttonStyle(.plain)
            }
            // The full Settings UI renders inline inside this Dashboard
            // window — no separate Settings window, no redirect.
            SettingsView()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Help

    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            StaggeredRiseText(
                text: "Help",
                font: .system(size: 24, weight: .bold, design: .serif)
            )
            helpParagraph(
                title: "Dictate anywhere",
                body: "Hold Fn and speak, or tap Cmd-Fn to toggle. Voxflow transcribes with \(appState.aiProvider.title), corrects the text, and pastes it where your cursor is."
            )
            helpParagraph(
                title: "Text not pasted?",
                body: "If your cursor was not in a text field, the dictation is still saved to history and a copy button appears automatically — in the menu-bar menu and in the Dashboard banner: \"Text not pasted. Click here to copy text.\" Click it to copy, then paste anywhere."
            )
            helpParagraph(
                title: "Your API key",
                body: apiKeyHelpBody
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
            .buttonStyle(.voxflowGlass)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var apiKeyHelpBody: String {
        switch appState.aiProvider {
        case .gemini:
            return "Voxflow uses your own Gemini API key. Get one free from Google AI Studio, then enter it in Setup. Your key stays in your Mac's Keychain."
        case .groq:
            return "Voxflow uses your own Groq API key. Get one from the Groq console, then enter it in Setup. Your key stays in your Mac's Keychain."
        case .ollama:
            return "Ollama runs locally on your Mac — no API key needed. Make sure Ollama is running, then pick the Ollama provider in Settings."
        case .custom:
            return "Your custom endpoint uses the API key you entered in Setup (if your endpoint needs one). Keys stay in your Mac's Keychain."
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
