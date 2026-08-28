import SwiftUI

struct RapidReaderView: View {
    let text: String
    let title: String
    private let progressStore: RapidReaderProgressStore

    @Environment(\.dismiss) private var dismiss
    @State private var words: [String]
    @State private var wordIndex: Int
    @State private var wpm: Int
    @State private var chunkSize: Int
    @State private var isPlaying: Bool
    @State private var lastSavedWordIndex: Int
    @State private var hasCompleted = false

    init(
        text: String,
        title: String = AccelerandoBook.title,
        progressStore: RapidReaderProgressStore = RapidReaderProgressStore()
    ) {
        self.text = text
        self.title = title
        self.progressStore = progressStore
        let words = RapidReaderProgressStore.words(in: text)
        let saved = progressStore.read(text: text)
        _words = State(initialValue: words)
        _wordIndex = State(initialValue: min(saved?.wordIndex ?? 0, max(0, words.count - 1)))
        _wpm = State(initialValue: saved?.wpm ?? 350)
        _chunkSize = State(initialValue: saved?.chunkSize ?? 1)
        _isPlaying = State(initialValue: false)
        _lastSavedWordIndex = State(initialValue: saved?.wordIndex ?? 0)
    }

    private var currentWordCount: Int {
        guard wordIndex < words.count else { return 0 }
        return min(chunkSize, words.count - wordIndex)
    }

    private var currentChunk: String {
        words[wordIndex..<min(words.count, wordIndex + max(1, chunkSize))].joined(separator: " ")
    }

    private var progress: Double {
        guard !words.isEmpty else { return 0 }
        return Double(min(words.count, wordIndex + currentWordCount)) / Double(words.count)
    }

    private var remainingSeconds: TimeInterval {
        RapidReaderProgressStore.remainingSeconds(
            wordIndex: wordIndex,
            wordCount: words.count,
            currentWordCount: currentWordCount,
            wpm: wpm
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if words.isEmpty {
                ContentUnavailableView("No text to read", systemImage: "text.book.closed")
            } else {
                readerDisplay
                controls
            }
        }
        .background(BookLoomStyle.ink.opacity(0.04))
        .navigationTitle("Rapid Reader")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    saveProgress()
                    dismiss()
                }
            }
        }
        .task(id: playbackTaskID) {
            guard isPlaying, !words.isEmpty, !hasCompleted else { return }
            let delay = delayForCurrentChunk
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled, isPlaying else { return }
            advance()
        }
        .onDisappear {
            saveProgress()
        }
    }

    private var playbackTaskID: String {
        "\(wordIndex)-\(wpm)-\(chunkSize)-\(isPlaying)-\(hasCompleted)"
    }

    private var delayForCurrentChunk: TimeInterval {
        let base = 60.0 / Double(max(60, wpm))
        var multiplier = 1.0
        if endsSentence(currentChunk) {
            multiplier = 1.8
        } else if endsClause(currentChunk) {
            multiplier = 1.3
        }
        if currentChunk.count > 8 {
            multiplier *= 1.15
        }
        return base * Double(max(1, currentWordCount)) * multiplier
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(BookLoomStyle.plum)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(BookLoomStyle.ink)
                Text("RSVP speed reading · \(wpm) words per minute")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private var readerDisplay: some View {
        VStack(spacing: 14) {
            GeometryReader { proxy in
                ZStack {
                    Rectangle()
                        .fill(BookLoomStyle.ink.opacity(0.035))
                    Rectangle()
                        .fill(BookLoomStyle.plum.opacity(0.35))
                        .frame(width: 1)
                    FocalWordView(chunk: currentChunk)
                        .frame(maxWidth: proxy.size.width - 32)
                }
            }
            .frame(minHeight: 190, idealHeight: 240, maxHeight: 300)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            ProgressView(value: progress)
                .tint(BookLoomStyle.plum)
                .padding(.horizontal, 16)
                .accessibilityLabel("Reading progress")
                .accessibilityValue("\(Int(progress * 100)) percent")
        }
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    readerButton("Back 5", systemImage: "backward.fill", accessibility: "Back 5 words") {
                        pauseAndMove(by: -5)
                    }
                    readerButton(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill", accessibility: isPlaying ? "Pause reading" : "Play reading") {
                        togglePlaying()
                    }
                    readerButton("Forward 5", systemImage: "forward.fill", accessibility: "Forward 5 words") {
                        pauseAndMove(by: 5)
                    }
                    readerButton("Restart", systemImage: "arrow.counterclockwise", accessibility: "Restart reading") {
                        restart()
                    }
                    readerButton("Bookmark", systemImage: "bookmark.fill", accessibility: "Save reading bookmark") {
                        saveProgress(force: true)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Reading speed")
                        Spacer()
                        Text("\(wpm) WPM")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(wpm) },
                        set: { wpm = Int($0.rounded()) }
                    ), in: 100...1_000, step: 25)
                    .tint(BookLoomStyle.plum)
                    .accessibilityLabel("Reading speed")
                }

                Picker("Words per beat", selection: $chunkSize) {
                    Text("1 word").tag(1)
                    Text("2 words").tag(2)
                }
                .pickerStyle(.segmented)
                .onChange(of: chunkSize) { _, _ in saveProgress() }

                HStack(alignment: .firstTextBaseline) {
                    Text("\(min(words.count, wordIndex + 1)) / \(words.count) words")
                        .monospacedDigit()
                    Spacer()
                    Label("\(RapidReaderProgressStore.formatRemainingTime(remainingSeconds)) left", systemImage: "clock")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.medium))

                if hasCompleted {
                    Label("Finished — play to start again", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(BookLoomStyle.sage)
                        .font(.subheadline.weight(.medium))
                } else {
                    Text("Space: play/pause · ←/→: move · B: bookmark · R: restart")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if title.caseInsensitiveCompare(AccelerandoBook.title) == .orderedSame {
                    HStack(spacing: 12) {
                        Label("Charles Stross · free edition", systemImage: "text.book.closed")
                        Link("Author's page", destination: AccelerandoBook.sourcePageURL)
                        Link(AccelerandoBook.licenseName, destination: AccelerandoBook.licenseURL)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .tint(BookLoomStyle.plum)
                }
            }
            .padding(16)
        }
        .background(.regularMaterial)
    }

    private func readerButton(_ title: String, systemImage: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(minWidth: 30, minHeight: 30)
        }
        .buttonStyle(.bordered)
        .tint(BookLoomStyle.plum)
        .accessibilityLabel(accessibility)
        .help(title)
    }

    private func togglePlaying() {
        if hasCompleted {
            restart()
        } else {
            isPlaying.toggle()
        }
    }

    private func advance() {
        let nextIndex = wordIndex + max(1, currentWordCount)
        guard nextIndex < words.count else {
            isPlaying = false
            hasCompleted = true
            progressStore.clear(text: text)
            lastSavedWordIndex = 0
            return
        }
        wordIndex = nextIndex
        saveProgressIfNeeded()
    }

    private func pauseAndMove(by offset: Int) {
        isPlaying = false
        wordIndex = min(max(0, wordIndex + offset), max(0, words.count - 1))
        hasCompleted = false
        saveProgress()
    }

    private func restart() {
        isPlaying = true
        wordIndex = 0
        hasCompleted = false
        progressStore.clear(text: text)
        lastSavedWordIndex = 0
    }

    private func saveProgressIfNeeded() {
        guard wordIndex > 0, wordIndex - lastSavedWordIndex >= 10 else { return }
        saveProgress()
    }

    private func saveProgress(force: Bool = false) {
        guard force || wordIndex > 0 else { return }
        if let _ = progressStore.write(text: text, wordIndex: wordIndex, wpm: wpm, chunkSize: chunkSize) {
            lastSavedWordIndex = wordIndex
        }
    }

    private func endsSentence(_ word: String) -> Bool {
        word.range(of: #"[.!?…]\"?$"#, options: .regularExpression) != nil
    }

    private func endsClause(_ word: String) -> Bool {
        word.range(of: #"[,;:)]\"?$"#, options: .regularExpression) != nil
    }
}

private struct FocalWordView: View {
    let chunk: String

    var body: some View {
        let parts = chunk.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let focalPart = parts.count == 2 && parts[1].count > parts[0].count ? 1 : 0
        let word = parts[safe: focalPart] ?? ""
        let focalIndex = focalIndex(for: word)
        let left = String(word.prefix(focalIndex))
        let focal = String(word.dropFirst(focalIndex).prefix(1))
        let right = String(word.dropFirst(min(word.count, focalIndex + 1)))
        let leftText = parts.count == 2 && focalPart == 1 ? "\(parts[0]) \(left)" : left
        let rightText = parts.count == 2 && focalPart == 0 ? "\(right) \(parts[1])" : right

        return HStack(spacing: 0) {
            Text(leftText)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(focal)
                .foregroundStyle(BookLoomStyle.coral)
            Text(rightText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 42, weight: .medium, design: .monospaced))
        .minimumScaleFactor(0.45)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .accessibilityLabel(chunk)
    }

    private func focalIndex(for word: String) -> Int {
        switch word.count {
        case ...1: return 0
        case 2...5: return 1
        case 6...9: return 2
        case 10...13: return 3
        default: return 4
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
