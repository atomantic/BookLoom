import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

/// Cross-platform "Upload Cover" / "Reset Cover" controls for a book entry
/// whose cover URL is editable. Uses PhotosPicker on iOS (no Files-app
/// detour, no photos-library permission required) and a `fileImporter`
/// sheet on macOS.
struct ManualCoverPicker: View {
    let identifier: String
    /// Current cover URL string on the entry, used to detect whether a
    /// manual cover is already in place so we can offer "Reset" instead of
    /// just "Upload".
    let currentCoverURL: String
    let onCoverChange: (String) -> Void

    @State private var isProcessing = false
    @State private var errorMessage: String?
    #if os(iOS)
    @State private var photoSelection: PhotosPickerItem?
    #else
    @State private var showingFilePicker = false
    #endif

    private var hasManualCover: Bool {
        guard let url = URL(string: currentCoverURL.trimmed) else { return false }
        return BookCoverCache.isManualCoverURL(url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                uploadButton
                if hasManualCover {
                    resetButton
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(BookLoomStyle.coral)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        #if os(iOS)
        .onChange(of: photoSelection) { _, newItem in
            guard let newItem else { return }
            handlePhotoPick(newItem)
        }
        #else
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        #endif
    }

    @ViewBuilder
    private var uploadButton: some View {
        #if os(iOS)
        PhotosPicker(
            selection: $photoSelection,
            matching: .images,
            photoLibrary: .shared()
        ) {
            uploadLabel
        }
        .buttonStyle(.bordered)
        .disabled(isProcessing)
        #else
        Button {
            showingFilePicker = true
        } label: {
            uploadLabel
        }
        .buttonStyle(.bordered)
        .disabled(isProcessing)
        #endif
    }

    private var uploadLabel: some View {
        Label(uploadTitle, systemImage: isProcessing ? "hourglass" : (hasManualCover ? "photo.on.rectangle" : "photo.badge.plus"))
            .font(.caption.weight(.semibold))
    }

    private var uploadTitle: String {
        if isProcessing {
            return "Saving..."
        }
        return hasManualCover ? "Replace Cover" : "Upload Cover"
    }

    private var resetButton: some View {
        Button(role: .destructive) {
            resetManualCover()
        } label: {
            Label("Reset Cover", systemImage: "arrow.uturn.backward.circle")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .disabled(isProcessing)
    }

    #if os(iOS)
    private func handlePhotoPick(_ item: PhotosPickerItem) {
        isProcessing = true
        errorMessage = nil
        Task {
            let bytes = try? await item.loadTransferable(type: Data.self)
            await applyPickedBytes(bytes)
            await MainActor.run {
                photoSelection = nil
            }
        }
    }
    #else
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let pickedURL = urls.first else { return }
            isProcessing = true
            errorMessage = nil
            Task {
                let bytes = readSecurityScoped(pickedURL)
                await applyPickedBytes(bytes)
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func readSecurityScoped(_ url: URL) -> Data? {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }
        return try? Data(contentsOf: url)
    }
    #endif

    private func applyPickedBytes(_ bytes: Data?) async {
        guard let raw = bytes else {
            await MainActor.run {
                errorMessage = "Couldn't read that image. Try a different file."
                isProcessing = false
            }
            return
        }
        guard let processed = ManualCoverProcessing.compress(raw) else {
            await MainActor.run {
                errorMessage = "Image is too large or unsupported. Pick a smaller image."
                isProcessing = false
            }
            return
        }
        let stored = await BookCoverCache.shared.storeManual(data: processed, identifier: identifier)
        await MainActor.run {
            isProcessing = false
            guard let stored else {
                errorMessage = "Couldn't save the cover. Free up some storage and try again."
                return
            }
            onCoverChange(stored.absoluteString)
        }
    }

    private func resetManualCover() {
        Task {
            await BookCoverCache.shared.removeManual(identifier: identifier)
            await MainActor.run {
                onCoverChange("")
                errorMessage = nil
            }
        }
    }
}
