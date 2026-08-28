import SwiftUI

/// A small shelf action that owns the download/cache state and presents the
/// native reader once the official Accelerando edition is available.
struct AccelerandoReaderAction: View {
    let book: LibraryBook
    let prominent: Bool

    @State private var isLoading = false
    @State private var downloadedBook: DownloadedAccelerandoBook?
    @State private var error: AccelerandoBookError?
    @State private var showingReader = false

    init(book: LibraryBook, prominent: Bool = false) {
        self.book = book
        self.prominent = prominent
    }

    var body: some View {
        Button {
            loadAndRead()
        } label: {
            Label(isLoading ? "Downloading…" : "Read with Rapid Reader", systemImage: isLoading ? "arrow.down.circle" : "bolt.fill")
        }
        .buttonStyle(prominent ? AnyButtonStyle(BookLoomProminentButtonStyle()) : AnyButtonStyle(BookLoomSecondaryButtonStyle(tint: BookLoomStyle.plum)))
        .disabled(isLoading)
        .accessibilityHint("Downloads the free author-hosted edition, then opens RSVP speed reading")
        .sheet(isPresented: $showingReader) {
            if let downloadedBook {
                NavigationStack {
                    RapidReaderView(text: downloadedBook.text, title: book.displayTitle)
                }
            }
        }
        .alert("Rapid Reader", isPresented: errorPresented) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Accelerando could not be loaded.")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )
    }

    private func loadAndRead() {
        isLoading = true
        Task { @MainActor in
            defer { isLoading = false }
            do {
                downloadedBook = try await AccelerandoBookService().load()
                showingReader = true
            } catch let downloadError as AccelerandoBookError {
                error = downloadError
            } catch _ {
                error = .unavailable
            }
        }
    }
}

/// SwiftUI's buttonStyle modifier needs one concrete style type; this small
/// eraser lets the action switch between the existing BookLoom button styles.
private struct AnyButtonStyle: ButtonStyle {
    private let makeBody: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        makeBody = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBody(configuration)
    }
}
