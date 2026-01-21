//
//  ProfileSheet.swift
//  Cauldron
//
//  Unified profile sheet with sharing, app icons, and profile stats
//

import SwiftUI

struct ProfileSheet: View {
    let dependencies: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    @StateObject private var currentUserSession = CurrentUserSession.shared
    @StateObject private var referralManager = ReferralManager.shared
    @StateObject private var iconManager = AppIconManager.shared
    @StateObject private var tierManager = UserTierManager.shared

    @State private var showIconPicker = false
    @State private var showProfileEdit = false
    @State private var shareLink: ShareableLink?
    @State private var codeCopied = false
    @State private var recipeCount = 0
    @State private var collectionCount = 0
    @State private var friendCount = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Profile Header with Edit Button
                    profileHeader

                    // Referral Section (prominent)
                    referralSection

                    // App Icon Section
                    appIconSection

                    // Stats Section
                    statsSection

                    // Quick Links
                    quickLinksSection
                }
                .padding()
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $shareLink) { link in
                ShareSheet(items: [link])
            }
            .sheet(isPresented: $showIconPicker) {
                AppIconPickerView()
            }
            .sheet(isPresented: $showProfileEdit) {
                ProfileEditView(dependencies: dependencies)
            }
            .task {
                await loadStats()
            }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 12) {
            if let user = currentUserSession.currentUser {
                // Large Avatar
                ProfileAvatar(user: user, size: 80, dependencies: dependencies)

                VStack(spacing: 4) {
                    Text(user.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("@\(user.username)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // Tier badge and Edit button row
                    HStack(spacing: 12) {
                        tierBadge

                        Button {
                            showProfileEdit = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "pencil")
                                Text("Edit")
                            }
                            .font(.caption)
                            .foregroundColor(.cauldronOrange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.cauldronOrange.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var tierBadge: some View {
        let tier = tierManager.currentTier

        return HStack(spacing: 4) {
            Image(systemName: tier.icon)
                .font(.caption2)
            Text(tier.displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(tier.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(tier.color.opacity(0.15))
        .cornerRadius(12)
    }

    // MARK: - Referral Section

    private var referralSection: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "gift.fill")
                    .foregroundColor(.cauldronOrange)
                Text("Invite Friends")
                    .font(.headline)
                Spacer()
            }

            if let user = currentUserSession.currentUser {
                let code = referralManager.generateReferralCode(for: user)

                VStack(spacing: 16) {
                    // Referral code
                    VStack(spacing: 8) {
                        Text("Your referral code")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // The code - big and tappable
                        Button {
                            UIPasteboard.general.string = code
                            withAnimation {
                                codeCopied = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    codeCopied = false
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Text(code)
                                    .font(.system(.title2, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(.cauldronOrange)

                                Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                                    .font(.body)
                                    .foregroundColor(codeCopied ? .green : .cauldronOrange)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.cauldronOrange.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)

                        if codeCopied {
                            Text("Copied!")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }

                    // Progress ring toward next icon
                    nextIconProgress

                    // Share button
                    Button {
                        shareApp()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share with Friends")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.cauldronOrange)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                }
            }
        }
        .padding()
        .background(Color.cauldronSecondaryBackground)
        .cornerRadius(16)
    }

    // MARK: - Progress Ring

    private var nextIconProgress: some View {
        Group {
            if let nextIcon = referralManager.nextIconToUnlock,
               let iconTheme = iconManager.availableIcons.first(where: { $0.id == nextIcon.iconId }) {
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        // Progress ring
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                                .frame(width: 50, height: 50)

                            Circle()
                                .trim(from: 0, to: progressToNextIcon)
                                .stroke(Color.cauldronOrange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .frame(width: 50, height: 50)
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut, value: progressToNextIcon)

                            Text("\(referralManager.referralCount)")
                                .font(.system(.caption, design: .rounded))
                                .fontWeight(.bold)
                        }

                        // Next icon preview
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(iconPreviewAssetName(for: iconTheme))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(7)
                                    .opacity(0.8)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(iconTheme.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    if let needed = referralManager.referralsToNextIcon {
                                        Text("\(needed) more to unlock")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }

                        Spacer()
                    }

                    // Progress bar
                    ProgressView(value: progressToNextIcon)
                        .tint(.cauldronOrange)
                }
                .padding(.vertical, 8)
            } else {
                // All icons unlocked
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("All icons unlocked!")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("\(referralManager.referralCount) friends joined")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var progressToNextIcon: Double {
        guard let nextIcon = referralManager.nextIconToUnlock else { return 1.0 }

        // Find previous icon threshold
        let allUnlocks = IconUnlock.all.sorted { $0.requiredReferrals < $1.requiredReferrals }
        let nextIndex = allUnlocks.firstIndex(where: { $0.iconId == nextIcon.iconId }) ?? 0
        let previousThreshold = nextIndex > 0 ? allUnlocks[nextIndex - 1].requiredReferrals : 0
        let nextThreshold = nextIcon.requiredReferrals

        let range = nextThreshold - previousThreshold
        guard range > 0 else { return 1.0 }

        let progress = referralManager.referralCount - previousThreshold
        return min(1.0, Double(progress) / Double(range))
    }

    // MARK: - App Icon Section

    private var appIconSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "app.gift.fill")
                    .foregroundColor(.cauldronOrange)
                Text("App Icon")
                    .font(.headline)
                Spacer()
                Text("\(iconManager.unlockedIcons.count)/\(iconManager.availableIcons.count) unlocked")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button {
                showIconPicker = true
            } label: {
                HStack(spacing: 12) {
                    // Current icon preview
                    Image(currentIconPreviewName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .cornerRadius(11)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(iconManager.currentTheme.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        Text("Tap to change")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.cauldronSecondaryBackground)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.cauldronOrange)
                Text("Your Stats")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 0) {
                statItem(value: recipeCount, label: "Recipes", icon: "fork.knife")
                Divider()
                    .frame(height: 40)
                statItem(value: collectionCount, label: "Collections", icon: "folder.fill")
                Divider()
                    .frame(height: 40)
                statItem(value: friendCount, label: "Friends", icon: "person.2.fill")
            }
            .padding(.vertical, 12)
            .background(Color.cauldronSecondaryBackground)
            .cornerRadius(12)
        }
    }

    private func statItem(value: Int, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.cauldronOrange)
                Text("\(value)")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Quick Links

    private var quickLinksSection: some View {
        VStack(spacing: 8) {
            if let user = currentUserSession.currentUser {
                NavigationLink(destination: UserProfileView(user: user, dependencies: dependencies)) {
                    HStack {
                        Image(systemName: "person.circle")
                            .foregroundColor(.cauldronOrange)
                        Text("View Public Profile")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.cauldronSecondaryBackground)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }

            Button {
                showProfileEdit = true
            } label: {
                HStack {
                    Image(systemName: "pencil.circle")
                        .foregroundColor(.cauldronOrange)
                    Text("Edit Profile")
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.cauldronSecondaryBackground)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var currentIconPreviewName: String {
        iconPreviewAssetName(for: iconManager.currentTheme)
    }

    private func iconPreviewAssetName(for theme: AppIconTheme) -> String {
        switch theme.id {
        case "default": return "BrandMarks/CauldronIcon"
        case "wicked": return "IconPreviews/IconPreviewWicked"
        case "goodwitch": return "IconPreviews/IconPreviewGoodWitch"
        case "maleficent": return "IconPreviews/IconPreviewMaleficent"
        case "ursula": return "IconPreviews/IconPreviewUrsula"
        case "agatha": return "IconPreviews/IconPreviewAgatha"
        case "scarletwitch": return "IconPreviews/IconPreviewScarletWitch"
        case "lion": return "IconPreviews/IconPreviewLion"
        case "serpent": return "IconPreviews/IconPreviewSerpent"
        case "badger": return "IconPreviews/IconPreviewBadger"
        case "eagle": return "IconPreviews/IconPreviewEagle"
        default: return "BrandMarks/CauldronIcon"
        }
    }

    // MARK: - Actions

    private func shareApp() {
        guard let user = currentUserSession.currentUser else { return }
        let shareURL = referralManager.getShareURL(for: user)
        let shareText = referralManager.getShareText(for: user)
        shareLink = ShareableLink(url: shareURL, previewText: shareText, image: nil)
    }

    private func loadStats() async {
        do {
            // Load recipe count
            let recipes = try await dependencies.recipeRepository.fetchAll()
            recipeCount = recipes.count
            tierManager.updateRecipeCount(recipeCount)

            // Load collection count
            let collections = try await dependencies.collectionRepository.fetchAll()
            collectionCount = collections.count

            // Load friend count
            if let userId = CurrentUserSession.shared.userId {
                let connections = try await dependencies.connectionRepository.fetchAcceptedConnections(forUserId: userId)
                friendCount = connections.count
            }
        } catch {
            AppLogger.general.error("Failed to load profile stats: \(error.localizedDescription)")
        }
    }
}

#Preview {
    ProfileSheet(dependencies: .preview())
}
