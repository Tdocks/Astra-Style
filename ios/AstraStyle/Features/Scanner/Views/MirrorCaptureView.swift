import PhotosUI
import SwiftUI

struct MirrorCaptureView: View {
    @State var viewModel: MirrorCaptureViewModel
    let onDone: () -> Void
    @State private var photo: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                Text("Save a full-look reference").astraText(.title2)
                Text("Capture or choose a mirror photo of your complete outfit. It stays private in Profile → Reference Photos, where you can remove it later.")
                    .astraText(.body)
                Text("Saving doesn't generate an image or add individual garments. Personal previews require their own Studio consent.")
                    .astraText(.caption)
                if let data = viewModel.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: AstraRadius.card))
                        .accessibilityLabel("Selected private mirror photo")
                }
                if viewModel.savedPath != nil {
                    Text("Your mirror photo is saved as a private reference.").astraText(.headline)
                    Button("Done", action: onDone).buttonStyle(.astraPrimary)
                } else {
                    PhotosPicker(selection: $photo, matching: .images) { Text("Choose photo") }
                        .buttonStyle(.astraPrimary).disabled(!viewModel.canReplacePhoto)
                    Button("Take mirror photo") { showsCamera = true }
                        .buttonStyle(.astraSecondary).disabled(!viewModel.canReplacePhoto)
                    Toggle("I have permission to save and use this photo as my personal reference.", isOn: $viewModel.hasPermission)
                        .astraText(.body).disabled(viewModel.isSaving)
                    Button(viewModel.pendingPath == nil ? "Save private reference" : "Retry saving reference") {
                        Task { await viewModel.save() }
                    }
                    .buttonStyle(.astraPrimary).disabled(!viewModel.canSave)
                    if viewModel.isSaving { ProgressView("Saving private reference…") }
                }
                if let error = loadError ?? viewModel.error { Text(error).astraText(.callout) }
            }
            .padding(AstraSpacing.pagePadding)
        }
        .background(AstraColor.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Mirror photo")
        .sheet(isPresented: $showsCamera) {
            ReferenceCameraPicker { data in
                showsCamera = false
                viewModel.choosePhoto(data)
            } onCancel: { showsCamera = false }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                loadError = nil
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw AstraError.validation("Couldn't load that photo.") }
                    viewModel.choosePhoto(data)
                } catch { loadError = "Couldn't load that photo. Choose another." }
                photo = nil
            }
        }
    }
}
