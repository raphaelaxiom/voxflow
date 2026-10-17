import Foundation

/// Pure statistics computed from pipeline history. No I/O, no singletons,
/// so the dashboard and the unit tests share exactly this logic.
enum DashboardStats {
    /// Words in a text: whitespace-separated tokens. Punctuation stays
    /// attached to its word, which matches how speakers count words.
    static func wordCount(of text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// The text shown for a history entry: the cleaned transcript, falling
    /// back to the raw transcript when cleanup produced nothing.
    static func displayText(for item: PipelineHistoryItem) -> String {
        let cleaned = item.postProcessedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty { return cleaned }
        return item.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Compact word-count label: 999 stays "999", 44,012 becomes "44.0K".
    static func formattedWordCount(_ count: Int) -> String {
        guard count >= 1_000 else { return "\(count)" }
        let thousands = Double(count) / 1_000.0
        if thousands >= 100 {
            return "\(Int(thousands.rounded()))K"
        }
        return String(format: "%.1fK", thousands)
    }

    struct Summary {
        let wordsToday: Int
        let totalWords: Int
        /// Words per minute of recorded dictation time. Nil when no
        /// dictation has a recorded duration yet.
        let wordsPerMinute: Double?
        let dayStreak: Int
        let dictationsToday: Int
        let totalDictations: Int
        /// Last 14 days including today, oldest first.
        let wordsPerDay: [(day: Date, words: Int, dictations: Int)]
    }

    static func compute(
        items: [PipelineHistoryItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Summary {
        let todayStart = calendar.startOfDay(for: now)
        var wordsToday = 0
        var totalWords = 0
        var dictationsToday = 0
        var timedWords = 0
        var timedSeconds: Double = 0

        // Day -> (words, dictations), for streaks and the per-day chart.
        var byDay: [Date: (words: Int, dictations: Int)] = [:]

        for item in items {
            let text = displayText(for: item)
            guard !text.isEmpty else { continue }
            let words = wordCount(of: text)
            totalWords += words
            if item.durationSeconds > 0 {
                timedWords += words
                timedSeconds += item.durationSeconds
            }
            let day = calendar.startOfDay(for: item.timestamp)
            byDay[day, default: (0, 0)].words += words
            byDay[day, default: (0, 0)].dictations += 1
            if day == todayStart {
                wordsToday += words
                dictationsToday += 1
            }
        }

        let wordsPerMinute: Double? = timedSeconds > 0
            ? Double(timedWords) / (timedSeconds / 60.0)
            : nil

        // Streak: consecutive days with at least one dictation, ending
        // today — or ending yesterday when nothing was dictated yet today,
        // so an in-progress streak still shows.
        var streak = 0
        var cursor = todayStart
        if byDay[todayStart] == nil {
            cursor = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        }
        while byDay[cursor] != nil {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        var wordsPerDay: [(day: Date, words: Int, dictations: Int)] = []
        for offset in (0..<14).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
            let entry = byDay[day] ?? (0, 0)
            wordsPerDay.append((day: day, words: entry.words, dictations: entry.dictations))
        }

        return Summary(
            wordsToday: wordsToday,
            totalWords: totalWords,
            wordsPerMinute: wordsPerMinute,
            dayStreak: streak,
            dictationsToday: dictationsToday,
            totalDictations: items.filter { !displayText(for: $0).isEmpty }.count,
            wordsPerDay: wordsPerDay
        )
    }
}
