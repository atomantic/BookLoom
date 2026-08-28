import Foundation

struct RapidReaderSection: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case part
        case chapter

        var label: String {
            rawValue.capitalized
        }
    }

    let id: String
    let title: String
    let kind: Kind
    let wordIndex: Int

    var displayTitle: String {
        "\(kind.label) · \(title)"
    }
}

struct RapidReaderProgress: Codable, Equatable {
    let wordIndex: Int
    let wordCount: Int
    let wpm: Int
    let chunkSize: Int
    let updatedAt: Date
}

/// Local-only progress for RSVP reading. It deliberately stores a fingerprint
/// and cursor, never the source text, so private pasted text cannot be recovered
/// from UserDefaults.
struct RapidReaderProgressStore {
    static let storageKey = "bookloom.rapid-reader-progress-v1"
    static let minimumWPM = 100
    static let maximumWPM = 1_500
    private static let version = 1
    private static let maxSavedDocuments = 20

    let defaults: UserDefaults
    let key: String

    init(defaults: UserDefaults = .standard, key: String = RapidReaderProgressStore.storageKey) {
        self.defaults = defaults
        self.key = key
    }

    func documentID(for text: String) -> String {
        var hash: UInt32 = 0x811C9DC5
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x01000193
        }
        return "\(text.utf8.count)-\(String(hash, radix: 36))"
    }

    func read(text: String) -> RapidReaderProgress? {
        let wordCount = Self.words(in: text).count
        guard wordCount > 0,
              let data = defaults.data(forKey: key),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == Self.version,
              let entry = envelope.entries[documentID(for: text)] else {
            return nil
        }
        return validated(entry, wordCount: wordCount)
    }

    @discardableResult
    func write(text: String, wordIndex: Int, wpm: Int, chunkSize: Int, now: Date = .now) -> RapidReaderProgress? {
        let wordCount = Self.words(in: text).count
        guard wordCount > 0 else { return nil }
        let progress = RapidReaderProgress(
            wordIndex: wordIndex,
            wordCount: wordCount,
            wpm: Self.clampWPM(wpm),
            chunkSize: chunkSize == 2 ? 2 : 1,
            updatedAt: now
        )
        guard let valid = validated(progress, wordCount: wordCount), valid.wordIndex > 0 else {
            return nil
        }

        var entries = readEnvelope()?.entries ?? [:]
        entries[documentID(for: text)] = valid
        entries = Dictionary(uniqueKeysWithValues: entries
            .sorted { $0.value.updatedAt > $1.value.updatedAt }
            .prefix(Self.maxSavedDocuments)
            .map { ($0.key, $0.value) })
        let envelope = Envelope(version: Self.version, entries: entries)
        guard let data = try? JSONEncoder().encode(envelope) else { return nil }
        defaults.set(data, forKey: key)
        return valid
    }

    func clear(text: String) {
        guard var envelope = readEnvelope() else { return }
        envelope.entries.removeValue(forKey: documentID(for: text))
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        defaults.set(data, forKey: key)
    }

    static func words(in text: String) -> [String] {
        var words: [String] = []
        var pendingPrefix = ""

        for substring in text.split(whereSeparator: \.isWhitespace) {
            let value = String(substring)
            if isPunctuationOrSymbolOnly(value) {
                if isOpeningPunctuationOnly(value) || words.isEmpty {
                    pendingPrefix += value
                } else {
                    words[words.count - 1] += value
                }
                continue
            }

            words.append(pendingPrefix + value)
            pendingPrefix = ""
        }

        if !pendingPrefix.isEmpty, !words.isEmpty {
            words[words.count - 1] += pendingPrefix
        }
        return words
    }

    static func remainingSeconds(wordIndex: Int, wordCount: Int, currentWordCount: Int = 1, wpm: Int) -> TimeInterval {
        let remainingWords = max(0, wordCount - wordIndex - currentWordCount)
        return TimeInterval(remainingWords * 60) / TimeInterval(max(60, wpm))
    }

    static func seekWordIndex(from wordIndex: Int, seconds: TimeInterval, wordCount: Int, wpm: Int) -> Int {
        guard wordCount > 0 else { return 0 }
        let wordsToSeek = Int((Double(clampWPM(wpm)) * seconds / 60).rounded())
        return min(max(0, wordIndex + wordsToSeek), wordCount - 1)
    }

    static func formatRemainingTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainder = totalSeconds % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", remainder))"
        }
        return "\(minutes):\(String(format: "%02d", remainder))"
    }

    private func readEnvelope() -> Envelope? {
        guard let data = defaults.data(forKey: key),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == Self.version else {
            return nil
        }
        return envelope
    }

    private func validated(_ entry: RapidReaderProgress, wordCount: Int) -> RapidReaderProgress? {
        guard entry.wordCount == wordCount,
              entry.wordIndex >= 0,
              entry.wordIndex < wordCount else {
            return nil
        }
        return RapidReaderProgress(
            wordIndex: entry.wordIndex,
            wordCount: wordCount,
            wpm: Self.clampWPM(entry.wpm),
            chunkSize: entry.chunkSize == 2 ? 2 : 1,
            updatedAt: entry.updatedAt
        )
    }

    static func clampWPM(_ wpm: Int) -> Int {
        min(maximumWPM, max(minimumWPM, wpm))
    }

    private static func isPunctuationOrSymbolOnly(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
        }
    }

    private static func isOpeningPunctuationOnly(_ value: String) -> Bool {
        let opening = CharacterSet(charactersIn: "([{<\"'“‘«‹「『¿¡")
        return !value.isEmpty && value.unicodeScalars.allSatisfy { opening.contains($0) }
    }

    private struct Envelope: Codable {
        let version: Int
        var entries: [String: RapidReaderProgress]
    }
}
