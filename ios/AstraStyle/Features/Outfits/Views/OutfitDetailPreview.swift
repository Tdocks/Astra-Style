import SwiftUI

#Preview("Loaded") {
    NavigationStack {
        OutfitDetailView(
            viewModel: OutfitDetailViewModel(
                outfitID: SampleData.heroOutfit.id,
                outfitRepository: MockOutfitRepository(),
                closetRepository: MockClosetRepository(),
                closetImageURLResolver: MockClosetImageURLResolver(),
                profileRepository: MockProfileRepository()
            )
        )
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}

#Preview("Not found") {
    NavigationStack {
        OutfitDetailView(
            viewModel: OutfitDetailViewModel(
                outfitID: UUID(),
                outfitRepository: MockOutfitRepository(),
                closetRepository: MockClosetRepository(),
                closetImageURLResolver: MockClosetImageURLResolver(),
                profileRepository: MockProfileRepository()
            )
        )
    }
    .environment(AppRouter())
    .preferredColorScheme(.dark)
}
