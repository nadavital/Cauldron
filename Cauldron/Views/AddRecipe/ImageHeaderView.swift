import SwiftUI
import PhotosUI

struct ImageHeaderView: View {
    @Binding var name: String
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var selectedImageData: Data?

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let data = selectedImageData,
                   let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 200)
                        .clipped()
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
                        .frame(height: 200)
                }
            }

            HStack {
                TextField("Recipe Name", text: $name)
                    .font(.title.bold())
                    .foregroundColor(selectedImageData != nil ? .white : .primary)
                    .padding(.vertical, 8)

                Spacer()

                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: selectedImageData != nil ? "photo.fill.on.rectangle.fill" : "plus.viewfinder")
                        .font(.title2)
                        .foregroundColor(selectedImageData != nil ? .white : .accentColor)
                        .padding(8)
                        .background(
                            Circle().fill(selectedImageData != nil ? .black.opacity(0.5) : .accentColor.opacity(0.1))
                        )
                }
                .onChange(of: selectedPhoto) { _ in
                    Task {
                        if let data = try? await selectedPhoto?.loadTransferable(type: Data.self) {
                            selectedImageData = data
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}