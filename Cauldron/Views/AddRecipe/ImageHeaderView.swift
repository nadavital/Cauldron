import SwiftUI
import PhotosUI

struct ImageHeaderView: View {
    @Binding var name: String
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var selectedImageData: Data?

    var body: some View {
        // Only handle image rendering - title and button moved to parent
        if let data = selectedImageData,
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .overlay(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        } else {
            Rectangle()
                .fill(Color.accentColor.opacity(0.1))
        }
    }
}