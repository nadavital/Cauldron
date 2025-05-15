import SwiftUI
import PhotosUI

struct ImagePickerView: View {
    let label: String
    @Binding var selectedPhoto: PhotosPickerItem?
    @Binding var selectedImageData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            if let currentImageData = selectedImageData, let uiImage = UIImage(data: currentImageData) {
                // Image is selected
                HStack(alignment: .top, spacing: 16) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100) // Slightly larger preview
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    VStack(alignment: .leading, spacing: 12) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                            Label("Change Image", systemImage: "photo.on.rectangle.angled")
                        }
                        Button(role: .destructive) {
                            selectedPhoto = nil
                            selectedImageData = nil
                        } label: {
                            Label("Remove Image", systemImage: "trash")
                        }
                        Spacer()
                    }
                }
            } else {
                // No image selected - placeholder is the picker
                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus.fill") // Changed to filled icon
                            .font(.system(size: 50))
                            .foregroundColor(.accentColor)
                        Text("Add Image")
                            .font(.callout)
                            .foregroundColor(.accentColor)
                    }
                    .frame(width: 120, height: 120) // Larger tap target
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
                }
            }
        }
        .onChange(of: selectedPhoto) {
            Task {
                if Task.isCancelled { return }
                if let data = try? await selectedPhoto?.loadTransferable(type: Data.self) {
                    if Task.isCancelled { return }
                    selectedImageData = data
                }
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var photoItem: PhotosPickerItem? = nil
        @State var imageData: Data? = nil
        @State var imageDataWithValue: Data? = UIImage(systemName: "star.fill")?.pngData() // Example with data

        var body: some View {
            Form {
                ImagePickerView(label: "Recipe Photo (Empty)", selectedPhoto: $photoItem, selectedImageData: $imageData)
                Divider()
                ImagePickerView(label: "Recipe Photo (With Image)", selectedPhoto: $photoItem, selectedImageData: $imageDataWithValue)
            }
        }
    }
    return PreviewWrapper()
} 
