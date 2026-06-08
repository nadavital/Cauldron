//
//  OnboardingView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI

/// First-run setup: a short two-step flow — a welcoming intro, then a single
/// "create profile" screen (avatar + name + optional referral) — instead of a
/// long scrolling form.
struct OnboardingView: View {
    let dependencies: DependencyContainer
    let onComplete: () -> Void

    private enum Step: Int, CaseIterable {
        case welcome, profile
    }

    @State private var step: Step = .welcome

    // MARK: - Profile state

    @State private var username = ""
    @State private var displayName = ""
    @State private var profileEmoji: String?
    @State private var profileColor: String? = Color.profileOrange.toHex()
    @State private var profileImage: UIImage?
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showingAvatarCustomization = false
    @State private var showingImagePicker = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var referralCode = ""
    @State private var didAutoApplyReferralCode = false
    @State private var showReferralField = false

    private var isValid: Bool {
        username.count >= 3 && username.count <= 20 &&
        displayName.count >= 1 &&
        username.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .welcome: welcomeStep
            case .profile: profileStep
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .sheet(isPresented: $showingAvatarCustomization) {
            AvatarCustomizationSheet(selectedEmoji: $profileEmoji, selectedColor: $profileColor)
        }
        .fullScreenCover(isPresented: $showingImagePicker) {
            ImagePicker(image: $profileImage, sourceType: imagePickerSourceType)
                .ignoresSafeArea()
        }
        .task {
            if let pendingCode = await PendingReferralManager.shared.consumePendingCode() {
                applyIncomingReferralCode(pendingCode)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openReferralInvite)) { notification in
            guard let code = notification.object as? String else { return }
            applyIncomingReferralCode(code)
            withAnimation(Theme.Animation.spring) { step = .profile }
        }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero mark
            Image("BrandMarks/CauldronIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 132)
                .shadow(color: .cauldronOrange.opacity(0.25), radius: 24, y: 10)

            VStack(spacing: Theme.Spacing.xs) {
                Text("Cauldron")
                    .font(.system(size: 40, design: .serif).weight(.bold))
                Text("Your recipes, beautifully organized\nand shared with friends.")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Theme.Spacing.lg)

            Spacer()

            // Feature highlights
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                highlight("square.and.arrow.down", "Import", "From the web, YouTube, TikTok & more")
                highlight("flame.fill", "Cook", "Hands-free, step-by-step with timers")
                highlight("person.2.fill", "Share", "Swap recipes with friends")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.xl)

            Spacer()
            Spacer()

            Button {
                Haptics.light()
                withAnimation(Theme.Animation.spring) { step = .profile }
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .tint(.cauldronOrange)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    private func highlight(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.cauldronOrange)
                .frame(width: 40, height: 40)
                .background(Color.cauldronOrange.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Create Profile

    private var profileStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    Text("Create your profile")
                        .font(.system(.largeTitle, design: .serif).weight(.bold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Theme.Spacing.lg)

                    avatarPreview

                    fieldGroup(title: "Username", caption: "3–20 characters · letters, numbers, underscores") {
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textCase(.lowercase)
                    }

                    fieldGroup(title: "Display Name", caption: "How others will see you") {
                        TextField("Your Name", text: $displayName)
                            .textInputAutocapitalization(.words)
                    }

                    if showReferralField || didAutoApplyReferralCode {
                        fieldGroup(title: "Referral Code", caption: didAutoApplyReferralCode ? "Applied from your invite link." : "Connect with a friend instantly.") {
                            TextField("Enter code", text: $referralCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        Button {
                            withAnimation(Theme.Animation.snappy) { showReferralField = true }
                        } label: {
                            Label("Add referral code", systemImage: "gift")
                                .font(.subheadline)
                                .foregroundStyle(Color.cauldronOrange)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let error = errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(Theme.Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.small))
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
            }

            footer
        }
    }

    private var avatarPreview: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image = profileImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 104, height: 104)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill((profileColor.flatMap { Color(hex: $0) } ?? .cauldronOrange).opacity(0.15))
                            .frame(width: 104, height: 104)
                            .overlay {
                                if let emoji = profileEmoji {
                                    Text(emoji).font(.system(size: 48))
                                } else {
                                    Text(initials)
                                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                                        .foregroundColor(profileColor.flatMap { Color(hex: $0) } ?? .cauldronOrange)
                                }
                            }
                    }
                }
                .animation(Theme.Animation.snappy, value: profileEmoji)
                .animation(Theme.Animation.snappy, value: profileImage)

                avatarMenu
            }

            Text(displayName.isEmpty ? "Your Name" : displayName)
                .font(.system(.title3, design: .serif).weight(.bold))
            Text("@\(username.isEmpty ? "username" : username)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var avatarMenu: some View {
        Menu {
            Button {
                showingAvatarCustomization = true
            } label: { Label("Choose Emoji", systemImage: "face.smiling") }
            Button {
                imagePickerSourceType = .photoLibrary
                showingImagePicker = true
            } label: { Label("Photo Library", systemImage: "photo.on.rectangle") }
            Button {
                imagePickerSourceType = .camera
                showingImagePicker = true
            } label: { Label("Take Photo", systemImage: "camera") }
            if profileImage != nil {
                Divider()
                Button(role: .destructive) {
                    profileImage = nil
                } label: { Label("Remove Photo", systemImage: "trash") }
            }
        } label: {
            Image(systemName: "pencil")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.cauldronOrange, in: Circle())
                .overlay(Circle().strokeBorder(Color.appBackground, lineWidth: 2))
        }
        .accessibilityLabel("Edit avatar")
    }

    private var initials: String {
        displayName.isEmpty ? "?" : String(displayName.prefix(2)).uppercased()
    }

    private func fieldGroup<Content: View>(title: String, caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            content()
                .padding()
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            Text(caption)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button {
                withAnimation(Theme.Animation.spring) { step = .welcome }
            } label: {
                Text("Back")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.extraLarge)

            Button {
                Task { await createUser() }
            } label: {
                Group {
                    if isCreating {
                        ProgressView().tint(.white)
                    } else {
                        Text("Create Profile")
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .tint(isValid ? .cauldronOrange : .gray)
            .disabled(!isValid || isCreating)
        }
        .padding(Theme.Spacing.lg)
    }

    // MARK: - Actions (unchanged logic)

    @MainActor
    private func createUser() async {
        isCreating = true
        errorMessage = nil

        do {
            let normalizedUsername = username.trimmingCharacters(in: .whitespaces).lowercased()
            let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespaces)

            try await CurrentUserSession.shared.createUser(
                username: normalizedUsername,
                displayName: normalizedDisplayName,
                profileEmoji: profileImage == nil ? profileEmoji : nil,
                profileColor: profileColor,
                profileImage: profileImage,
                dependencies: dependencies
            )

            let trimmedCode = referralCode.trimmingCharacters(in: .whitespaces)
            if !trimmedCode.isEmpty {
                await processReferralCode(trimmedCode, displayName: normalizedDisplayName)
            }

            Haptics.success()
            onComplete()
        } catch {
            errorMessage = error.localizedDescription
            isCreating = false
        }
    }

    @MainActor
    private func processReferralCode(_ code: String, displayName: String) async {
        ReferralManager.shared.configure(userCloudService: dependencies.userCloudService, connectionCloudService: dependencies.connectionCloudService)

        guard let currentUser = CurrentUserSession.shared.currentUser else {
            AppLogger.general.warning("No current user available for referral processing")
            return
        }

        _ = await ReferralManager.shared.redeemReferralCode(
            code,
            currentUser: currentUser,
            displayName: displayName
        )
    }

    @MainActor
    private func applyIncomingReferralCode(_ code: String) {
        let normalizedCode = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCode.isEmpty else { return }

        referralCode = normalizedCode
        didAutoApplyReferralCode = true
    }
}

#Preview {
    OnboardingView(dependencies: .preview()) {
        // Onboarding completed
    }
}
