//
//  EditProfileAvatarSheet.swift
//  Cauldron
//
//  Sheet for editing profile avatar (photo or emoji)
//

import SwiftUI

// MARK: - Avatar Type

enum AvatarType: String, CaseIterable {
    case emoji = "Emoji Avatar"
    case photo = "Upload Photo"
}

// MARK: - Edit Profile Avatar Sheet

struct EditProfileAvatarSheet: View {
    let currentUser: User
    @Binding var selectedAvatarType: AvatarType
    let onSave: (AvatarType, String?, String?, UIImage?) -> Void
    let dependencies: DependencyContainer

    @Environment(\.dismiss) private var dismiss

    @State private var selectedEmoji: String?
    @State private var selectedColor: String?
    @State private var profileImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingEmojiPicker = false

    init(
        currentUser: User,
        selectedAvatarType: Binding<AvatarType>,
        onSave: @escaping (AvatarType, String?, String?, UIImage?) -> Void,
        dependencies: DependencyContainer
    ) {
        self.currentUser = currentUser
        self._selectedAvatarType = selectedAvatarType
        self.onSave = onSave
        self.dependencies = dependencies

        // Initialize with current values
        _selectedEmoji = State(initialValue: currentUser.profileEmoji)
        _selectedColor = State(initialValue: currentUser.profileColor)

        // Determine initial avatar type
        if currentUser.profileImageURL != nil {
            _selectedAvatarType = Binding.constant(.photo)
        } else {
            _selectedAvatarType = Binding.constant(.emoji)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Avatar Type Selection
                Section {
                    Picker("Avatar Type", selection: $selectedAvatarType) {
                        Text("Emoji Avatar").tag(AvatarType.emoji)
                        Text("Upload Photo").tag(AvatarType.photo)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Avatar Type")
                }

                // Preview Section
                Section {
                    HStack {
                        Spacer()
                        previewAvatar
                        Spacer()
                    }
                    .padding(.vertical, 16)
                } header: {
                    Text("Preview")
                }

                // Emoji Avatar Settings
                if selectedAvatarType == .emoji {
                    Section {
                        HStack {
                            Text("Emoji")
                            Spacer()
                            Button {
                                showingEmojiPicker = true
                            } label: {
                                if let emoji = selectedEmoji {
                                    Text(emoji)
                                        .font(.title)
                                } else {
                                    Text("Choose Emoji")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        HStack {
                            Text("Color")
                            Spacer()
                            ColorPicker("", selection: Binding(
                                get: {
                                    if let colorHex = selectedColor {
                                        return Color(hex: colorHex) ?? .cauldronOrange
                                    }
                                    return .cauldronOrange
                                },
                                set: { newColor in
                                    selectedColor = newColor.toHex()
                                }
                            ))
                            .labelsHidden()
                        }
                    } header: {
                        Text("Emoji Settings")
                    }
                }

                // Photo Avatar Settings
                if selectedAvatarType == .photo {
                    Section {
                        Button {
                            showingImagePicker = true
                        } label: {
                            HStack {
                                if profileImage != nil {
                                    Text("Change Photo")
                                } else {
                                    Text("Upload Photo")
                                }
                                Spacer()
                                Image(systemName: "photo.on.rectangle.angled")
                                    .foregroundColor(.cauldronOrange)
                            }
                        }
                    } header: {
                        Text("Photo")
                    }
                }
            }
            .navigationTitle("Edit Profile Picture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        onSave(selectedAvatarType, selectedEmoji, selectedColor, profileImage)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            // Use fullScreenCover for camera to prevent white bar at bottom of viewfinder
            .fullScreenCover(isPresented: $showingImagePicker) {
                ImagePicker(image: $profileImage)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showingEmojiPicker) {
                AvatarCustomizationSheet(
                    selectedEmoji: $selectedEmoji,
                    selectedColor: $selectedColor
                )
            }
            .onChange(of: selectedAvatarType) { oldValue, newValue in
                // Clear data when switching types
                if newValue == .photo {
                    selectedEmoji = nil
                    selectedColor = nil
                } else {
                    profileImage = nil
                }
            }
            .task {
                // Load existing profile image if available
                if let userId = CurrentUserSession.shared.userId,
                   currentUser.profileImageURL != nil,
                   profileImage == nil {
                    profileImage = await dependencies.profileImageManager.loadImage(userId: userId)
                }
            }
        }
    }

    // MARK: - Preview Avatar

    @ViewBuilder
    private var previewAvatar: some View {
        ZStack {
            if selectedAvatarType == .photo {
                if let profileImage = profileImage {
                    Image(uiImage: profileImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)
                        )
                }
            } else {
                // Emoji avatar
                Circle()
                    .fill((selectedColor.flatMap { Color(hex: $0) } ?? .cauldronOrange).opacity(0.15))
                    .frame(width: 100, height: 100)
                    .overlay(
                        Group {
                            if let emoji = selectedEmoji {
                                Text(emoji)
                                    .font(.system(size: 50))
                            } else {
                                Text(currentUser.initials)
                                    .font(.title)
                                    .fontWeight(.semibold)
                                    .foregroundColor(selectedColor.flatMap { Color(hex: $0) } ?? .cauldronOrange)
                            }
                        }
                    )
            }
        }
    }

    // MARK: - Helpers

    private var canSave: Bool {
        if selectedAvatarType == .photo {
            return profileImage != nil
        } else {
            return selectedEmoji != nil && selectedColor != nil
        }
    }
}
