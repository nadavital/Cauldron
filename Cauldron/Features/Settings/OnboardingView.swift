//
//  OnboardingView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI

/// First-run profile setup, presented as a short guided multi-step flow
/// (welcome → identity → avatar → referral) with a progress indicator and a
/// live avatar preview, rather than one long scrolling form.
struct OnboardingView: View {
    let dependencies: DependencyContainer
    let onComplete: () -> Void

    // MARK: - Step model

    private enum Step: Int, CaseIterable {
        case welcome, identity, avatar, referral

        var title: String {
            switch self {
            case .welcome: return "Welcome to Cauldron"
            case .identity: return "Who are you?"
            case .avatar: return "Make it yours"
            case .referral: return "Almost there"
            }
        }

        var subtitle: String {
            switch self {
            case .welcome: return "Your recipes, beautifully organized — and shared with friends."
            case .identity: return "Pick a username and a name others will see."
            case .avatar: return "Choose an emoji or photo for your profile."
            case .referral: return "Got a code from a friend? Add it to connect instantly."
            }
        }
    }

    @State private var step: Step = .welcome
    @Namespace private var stepGlass

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

    private var hasPhoto: Bool { profileImage != nil }
    private var hasEmoji: Bool { profileEmoji != nil }

    /// Whether the current step's requirements are satisfied (gates Continue).
    private var canAdvance: Bool {
        switch step {
        case .welcome, .avatar, .referral:
            return true
        case .identity:
            return isValid
        }
    }

    private var isValid: Bool {
        username.count >= 3 && username.count <= 20 &&
        displayName.count >= 1 &&
        username.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private var isLastStep: Bool { step == Step.allCases.last }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            progressHeader

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    stepHeader

                    switch step {
                    case .welcome: welcomeStep
                    case .identity: identityStep
                    case .avatar: avatarStep
                    case .referral: referralStep
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
                .padding(Theme.Spacing.lg)
            }

            footer
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
            // Jump to the referral step so the user sees it was applied.
            withAnimation(Theme.Animation.spring) { step = .referral }
        }
    }

    // MARK: - Header / progress

    private var progressHeader: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Color.cauldronOrange : Color.appSeparator)
                    .frame(height: 4)
                    .animation(Theme.Animation.spring, value: step)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(step.title)
                .font(.system(.largeTitle, design: .serif).weight(.bold))
            Text(step.subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image("BrandMarks/CauldronIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .shadow(color: .cauldronOrange.opacity(0.25), radius: 20, y: 8)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                onboardingHighlight("square.and.arrow.down", "Import from the web, YouTube, TikTok & more")
                onboardingHighlight("flame.fill", "Cook hands-free with step timers")
                onboardingHighlight("person.2.fill", "Share recipes with friends")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, Theme.Spacing.md)
    }

    private func onboardingHighlight(_ icon: String, _ text: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Color.cauldronOrange)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }

    private var identityStep: some View {
        VStack(spacing: Theme.Spacing.lg) {
            avatarPreview

            fieldGroup(title: "Username", caption: "3–20 characters · letters, numbers, underscores") {
                TextField("username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textCase(.lowercase)
            }

            fieldGroup(title: "Display Name", caption: "This is how others will see you") {
                TextField("Your Name", text: $displayName)
                    .textInputAutocapitalization(.words)
            }
        }
    }

    private var avatarStep: some View {
        VStack(spacing: Theme.Spacing.lg) {
            avatarPreview

            HStack(spacing: Theme.Spacing.sm) {
                avatarOptionButton(icon: "face.smiling", label: hasEmoji ? "Edit Emoji" : "Emoji", selected: hasEmoji && !hasPhoto) {
                    showingAvatarCustomization = true
                }
                avatarOptionButton(icon: "photo.on.rectangle", label: "Photos", selected: hasPhoto) {
                    imagePickerSourceType = .photoLibrary
                    showingImagePicker = true
                }
                avatarOptionButton(icon: "camera", label: "Camera", selected: false) {
                    imagePickerSourceType = .camera
                    showingImagePicker = true
                }
            }

            if hasPhoto {
                Button(role: .destructive) {
                    withAnimation(Theme.Animation.snappy) { profileImage = nil }
                } label: {
                    Label("Remove photo", systemImage: "xmark.circle.fill")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var referralStep: some View {
        VStack(spacing: Theme.Spacing.lg) {
            avatarPreview

            fieldGroup(title: "Referral Code", caption: "Optional — unlocks an exclusive icon and connects you instantly.") {
                TextField("Enter friend's code", text: $referralCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }

            if didAutoApplyReferralCode {
                Label("Invite code applied from your link.", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Shared step components

    /// Live avatar + name preview shown across the profile-building steps.
    private var avatarPreview: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                if let image = profileImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill((profileColor.flatMap { Color(hex: $0) } ?? .cauldronOrange).opacity(0.15))
                        .frame(width: 96, height: 96)
                        .overlay {
                            if let emoji = profileEmoji {
                                Text(emoji).font(.system(size: 44))
                            } else {
                                Text(initials)
                                    .font(.system(.title, design: .serif).weight(.semibold))
                                    .foregroundColor(profileColor.flatMap { Color(hex: $0) } ?? .cauldronOrange)
                            }
                        }
                }
            }
            .animation(Theme.Animation.snappy, value: profileEmoji)
            .animation(Theme.Animation.snappy, value: profileImage)

            Text(displayName.isEmpty ? "Your Name" : displayName)
                .font(.system(.title3, design: .serif).weight(.bold))
            Text("@\(username.isEmpty ? "username" : username)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
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

    private func avatarOptionButton(icon: String, label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                selected ? Color.cauldronOrange.opacity(0.15) : Color.appSurface,
                in: RoundedRectangle(cornerRadius: Theme.Radius.card)
            )
            .foregroundColor(selected ? .cauldronOrange : .primary)
        }
        .buttonStyle(PressableScaleStyle())
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            if step != .welcome {
                Button {
                    withAnimation(Theme.Animation.spring) { goBack() }
                } label: {
                    Text("Back")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.extraLarge)
            }

            Button {
                advance()
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    if isCreating {
                        ProgressView().tint(.white)
                    } else {
                        Text(isLastStep ? "Create Profile" : "Continue")
                            .font(.headline)
                        Image(systemName: isLastStep ? "checkmark" : "arrow.right")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .tint(canAdvance ? .cauldronOrange : .gray)
            .disabled(!canAdvance || isCreating)
        }
        .padding(Theme.Spacing.lg)
    }

    // MARK: - Navigation

    private func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        step = prev
    }

    private func advance() {
        guard canAdvance else { return }
        if isLastStep {
            Task { await createUser() }
        } else {
            Haptics.light()
            withAnimation(Theme.Animation.spring) {
                step = Step(rawValue: step.rawValue + 1) ?? step
            }
        }
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
