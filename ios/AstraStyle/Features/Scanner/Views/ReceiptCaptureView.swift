import PhotosUI
import SwiftUI

struct ReceiptCaptureView: View {
    var onItemSaved: ((ClosetItem) -> Void)?
    @State var viewModel: ReceiptCaptureViewModel
    @State private var photo: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var loadError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                Text("Scan a receipt or label").astraText(.title2)
                Text("Read text on your device, then review the item details. A receipt total may include several items. Check the price for this garment before saving.")
                    .astraText(.body)
                Text("Label text stays visible for you to copy; brand and size are not guessed.")
                    .astraText(.body)
                PhotosPicker(selection: $photo, matching: .images) {
                    Text("Choose photo")
                }
                .buttonStyle(.astraPrimary)
                .disabled(viewModel.isRecognizing)
                Button("Take photo") { showsCamera = true }
                    .buttonStyle(.astraSecondary)
                    .disabled(viewModel.isRecognizing)
                if viewModel.isRecognizing { ProgressView("Reading text…") }
                if let error = loadError ?? viewModel.error { Text(error).astraText(.callout) }
                if let suggestions = viewModel.suggestions, !suggestions.text.isEmpty {
                    DisclosureGroup("Recognized text") {
                        Text(suggestions.text).astraText(.body).textSelection(.enabled)
                    }
                }
                if let saved = viewModel.savedItem {
                    Text("Saved \(saved.name) to your closet.").astraText(.headline)
                    Button("Done") { dismiss() }.buttonStyle(.astraPrimary)
                } else if let form = viewModel.form {
                    ClosetItemFormView(viewModel: form)
                }
            }
            .padding(AstraSpacing.pagePadding)
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Receipt / label")
        .onChange(of: viewModel.savedItem?.id) { _, _ in
            if let item = viewModel.savedItem { onItemSaved?(item) }
        }
        .sheet(isPresented: $showsCamera) {
            ReferenceCameraPicker { data in
                showsCamera = false
                Task { await viewModel.recognize(data) }
            } onCancel: { showsCamera = false }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                loadError = nil
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw AstraError.validation("That photo couldn't be loaded. Choose another.")
                    }
                    await viewModel.recognize(data)
                } catch { loadError = "That photo couldn't be loaded. Choose another." }
                photo = nil
            }
        }
    }
}
