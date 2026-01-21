//
//  AppIconPickerView.swift
//  Cauldron
//
//  Allows users to select from available app icon themes
//  Shows multiple icons with grid layout and share CTA
//

import SwiftUI

struct AppIconPickerView: View {
    @StateObject private var iconManager = AppIconManager.shared
    @StateObject private var referralManager = ReferralManager.shared
    @StateObject private var userSession = CurrentUserSession.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isChangingIcon = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var shareLink: ShareableLink?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Progress header with share CTA
                    progressHeader

                    // Icons grid
                    iconsGrid
                }
                .padding()
            }
            .background(Color.cauldronBackground.ignoresSafeArea())
            .navigationTitle("App Icons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .sheet(item: $shareLink) { link in
                ShareSheet(items: [link])
            }
            .disabled(isChangingIcon)
            .overlay {
                if isChangingIcon {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay {
                            ProgressView("Changing icon...")
                                .padding()
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                }
            }
        }
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(iconPreviewAssetName(for: iconManager.currentTheme))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .cornerRadius(12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(iconManager.currentTheme.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("\(iconManager.unlockedIcons.count) of \(iconManager.availableIcons.count) icons unlocked")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Bold share CTA
            if let nextIcon = referralManager.nextIconToUnlock,
               let needed = referralManager.referralsToNextIcon,
               let iconTheme = iconManager.availableIcons.first(where: { $0.id == nextIcon.iconId }) {
                Button {
                    shareApp()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline)
                        Text("Invite \(needed) \(needed == 1 ? "friend" : "friends") to unlock \(iconTheme.name)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.cauldronOrange)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("All icons unlocked!")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.green.opacity(0.15))
                .cornerRadius(10)
            }
        }
        .padding()
        .background(Color.cauldronSecondaryBackground)
        .cornerRadius(16)
    }

    // MARK: - Icons Grid

    private var iconsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All Icons")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(sortedIcons) { theme in
                    iconCell(theme: theme)
                }
            }
        }
    }

    private func iconCell(theme: AppIconTheme) -> some View {
        let isSelected = iconManager.currentTheme == theme
        let isUnlocked = iconManager.isUnlocked(theme)
        let referralsNeededCount = iconManager.referralsToUnlock(theme) ?? 0
        let progress = iconUnlockProgress(for: theme)

        return Button {
            selectIcon(theme)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if isUnlocked {
                        // Unlocked: show icon clearly with no effects
                        Image(iconPreviewAssetName(for: theme))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(isSelected ? Color.cauldronOrange : Color.clear, lineWidth: 3)
                            )
                    } else {
                        // Locked: show blurred icon with ring progress overlay
                        Image(iconPreviewAssetName(for: theme))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .cornerRadius(16)
                            .blur(radius: 4)
                            .saturation(0.3)
                            .opacity(0.6)

                        // Ring progress (centered, smaller than icon)
                        Circle()
                            .stroke(Color.primary.opacity(0.15), lineWidth: 4)
                            .frame(width: 48, height: 48)

                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                Color.cauldronOrange,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 48, height: 48)
                            .rotationEffect(.degrees(-90))
                    }

                    // Checkmark for selected
                    if isSelected {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.cauldronOrange)
                                    .background(Circle().fill(Color(.systemBackground)))
                            }
                        }
                        .frame(width: 72, height: 72)
                        .offset(x: 4, y: 4)
                    }
                }

                Text(theme.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(isUnlocked ? .primary : .secondary)

                // Status text
                if !isUnlocked {
                    Text("\(referralsNeededCount) more")
                        .font(.system(size: 10))
                        .foregroundColor(.cauldronOrange)
                } else if isSelected {
                    Text("Selected")
                        .font(.system(size: 10))
                        .foregroundColor(.cauldronOrange)
                } else {
                    Text("Tap to use")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
        .allowsHitTesting(!isSelected && isUnlocked)
    }

    /// Icons sorted: unlocked first, then by referral requirement
    private var sortedIcons: [AppIconTheme] {
        iconManager.availableIcons.sorted { theme1, theme2 in
            let unlocked1 = iconManager.isUnlocked(theme1)
            let unlocked2 = iconManager.isUnlocked(theme2)

            // Unlocked icons come first
            if unlocked1 && !unlocked2 { return true }
            if !unlocked1 && unlocked2 { return false }

            // Among same unlock status, sort by referral requirement
            let req1 = IconUnlock.unlock(for: theme1.id)?.requiredReferrals ?? 0
            let req2 = IconUnlock.unlock(for: theme2.id)?.requiredReferrals ?? 0
            return req1 < req2
        }
    }

    // MARK: - Helpers

    private func iconUnlockProgress(for theme: AppIconTheme) -> Double {
        guard let unlock = IconUnlock.unlock(for: theme.id) else { return 1.0 }

        let required = unlock.requiredReferrals
        if required == 0 { return 1.0 }

        let current = referralManager.referralCount
        return min(1.0, Double(current) / Double(required))
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

    private func selectIcon(_ theme: AppIconTheme) {
        guard !isChangingIcon else { return }
        guard iconManager.currentTheme != theme else { return }
        guard iconManager.isUnlocked(theme) else { return }

        isChangingIcon = true

        Task {
            let success = await iconManager.setIcon(theme)
            isChangingIcon = false

            if !success {
                errorMessage = "Failed to change app icon. Please try again."
                showError = true
            }
        }
    }

    private func shareApp() {
        guard let user = userSession.currentUser else { return }
        let shareURL = referralManager.getShareURL(for: user)
        let shareText = referralManager.getShareText(for: user)
        shareLink = ShareableLink(url: shareURL, previewText: shareText, image: nil)
    }
}

#Preview {
    AppIconPickerView()
}
