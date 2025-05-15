import SwiftUI

struct TagSelectionView: View {
    @Binding var selectedTagIDs: Set<String>
    @Environment(\.dismiss) var dismiss

    let allTagsManager = AllRecipeTags.shared
    // Order categories for consistent display
    let orderedCategories: [TagCategory] = TagCategory.allCases

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(orderedCategories) { category in
                        if let tagsInCategory = allTagsManager.tagsByCategory[category], !tagsInCategory.isEmpty {
                            Section {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(category.rawValue)
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                        .padding(.leading)

                                    // Using a flexible grid for tags within a category
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 10)], spacing: 10) {
                                        ForEach(tagsInCategory) { tag in
                                            Button {
                                                if selectedTagIDs.contains(tag.id) {
                                                    selectedTagIDs.remove(tag.id)
                                                } else {
                                                    selectedTagIDs.insert(tag.id)
                                                }
                                            } label: {
                                                VStack {
                                                    Image(tag.iconName)
                                                        .resizable()
                                                        .frame(width: 50, height: 50)
                                                    Text(tag.name)
                                                        .font(.caption)
                                                        .lineLimit(2)
                                                        .multilineTextAlignment(.center)
                                                }
                                                .padding(8)
                                                .frame(minHeight: 70, alignment: .center)
                                                .frame(maxWidth: .infinity)
                                                .background(selectedTagIDs.contains(tag.id) ? Color.accentColor.opacity(0.2) : Color(.systemGray6))
                                                .foregroundColor(selectedTagIDs.contains(tag.id) ? .accentColor : .primary)
                                                .cornerRadius(10)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .stroke(selectedTagIDs.contains(tag.id) ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                                )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            } header: { EmptyView() } // To get Section styling without default header
                            Divider().padding(.vertical, 10)
                        }
                    }
                }
                .padding(.vertical)
                .padding(.horizontal)
            }
            .navigationTitle("Select Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    // Create a @State var for the binding in the preview
    struct TagSelectionPreviewWrapper: View {
        @State var selectedTags: Set<String> = ["cuisine_italian", "dietary_vegan"]
        var body: some View {
            TagSelectionView(selectedTagIDs: $selectedTags)
        }
    }
    return TagSelectionPreviewWrapper()
} 
