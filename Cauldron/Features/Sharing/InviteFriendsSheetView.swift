//
//  InviteFriendsSheetView.swift
//  Cauldron
//
//  Extracted from FriendsTabView.swift: invite-a-friend sheet.
//

import SwiftUI
import os

struct InviteFriendsSheetView: View {
    let dependencies: DependencyContainer

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var currentUserSession = CurrentUserSession.shared
    @StateObject private var referralManager = ReferralManager.shared

    @State private var shareLink: ShareableLink?
    @State private var copiedCode = false
    @State private var referredUsers: [User] = []
    @State private var isLoadingReferredUsers = false

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedMeshGradient()
                    .ignoresSafeArea()

                Color.cauldronBackground.opacity(0.35)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        heroSection
                        actionSection
                        invitesAndRewardsSection
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Invite Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $shareLink) { link in
                ShareSheet(items: [link])
            }
            .task(id: currentUserSession.currentUser?.id) {
                referralManager.configure(
                    userCloudService: dependencies.userCloudService,
                    connectionCloudService: dependencies.connectionCloudService
                )
                await loadReferredUsers()
            }
        }
    }

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color.cauldronOrange.opacity(0.3), Color.cauldronOrange.opacity(0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 8) {
                Label("Invite Friends to Cauldron", systemImage: "person.3.fill")
                    .font(.title3)
                    .fontWeight(.bold)

                Text("Send one tap invite links that auto-apply your code and connect you as friends.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .bottomLeading)
        .overlay(alignment: .topTrailing) {
            Image("BrandMarks/CauldronIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 92, height: 92)
                .opacity(0.22)
                .padding(14)
        }
        .clipShape(.rect(cornerRadius: 22))
    }

    private var invitesAndRewardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.2.wave.2.fill")
                    .foregroundColor(.cauldronOrange)
                Text("Invites & Rewards")
                    .font(.headline)
            }

            Text("Rewards Progress")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            if let nextUnlock = referralManager.nextIconToUnlock {
                let target = max(1, nextUnlock.requiredReferrals)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(
                            "\(referralManager.referralCount) referral join\(referralManager.referralCount == 1 ? "" : "s")",
                            systemImage: "person.2.fill"
                        )
                        .font(.subheadline.weight(.semibold))

                        Spacer()

                        Text("\(min(referralManager.referralCount, target))/\(target)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }

                    ProgressView(
                        value: Double(min(referralManager.referralCount, target)),
                        total: Double(target)
                    )
                    .tint(.cauldronOrange)

                    let remaining = max(0, nextUnlock.requiredReferrals - referralManager.referralCount)
                    Text("\(remaining) more to unlock '\(nextUnlock.iconId)'")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Label("All referral icon rewards unlocked.", systemImage: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Divider()
                .overlay(Color.secondary.opacity(0.2))
                .padding(.vertical, 2)

            Text("People You Invited")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            if isLoadingReferredUsers {
                ProgressView("Loading invites...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if referredUsers.isEmpty {
                Text("No one has joined from your invite yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(referredUsers.prefix(8)) { user in
                        HStack(spacing: 10) {
                            ProfileAvatar(user: user, size: 34, dependencies: dependencies)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                Text("@\(user.username)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                        .padding(10)
                        .background(Color.cauldronBackground.opacity(0.8))
                        .clipShape(.rect(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(16)
        .background(Color.cauldronSecondaryBackground)
        .clipShape(.rect(cornerRadius: 18))
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Invite Tools")
                    .font(.headline)
                Spacer()
            }

            if let user = currentUserSession.currentUser {
                let referralCode = referralManager.generateReferralCode(for: user)
                let inviteURL = referralManager.getShareURL(for: user)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Referral Code")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 10) {
                            Text(referralCode)
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Spacer()

                            Button {
                                UIPasteboard.general.string = referralCode
                                copiedCode = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    copiedCode = false
                                }
                            } label: {
                                Label(copiedCode ? "Copied" : "Copy", systemImage: copiedCode ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(12)
                        .background(Color.cauldronBackground)
                        .clipShape(.rect(cornerRadius: 14))
                    }

                    Button {
                        shareLink = ShareableLink(
                            url: inviteURL,
                            previewText: referralManager.getShareText(for: user),
                            image: nil
                        )
                    } label: {
                        Label("Invite Friends", systemImage: "square.and.arrow.up.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cauldronOrange)
                }
            } else {
                Label("Sign in to generate your invite link.", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color.cauldronSecondaryBackground)
        .clipShape(.rect(cornerRadius: 18))
    }

    @MainActor
    private func loadReferredUsers() async {
        guard let currentUser = currentUserSession.currentUser else {
            referredUsers = []
            return
        }

        isLoadingReferredUsers = true
        defer { isLoadingReferredUsers = false }

        do {
            referredUsers = try await dependencies.userCloudService.fetchReferredUsers(for: currentUser.id, limit: 40)
        } catch {
            AppLogger.general.warning("Failed to load referred users for invite sheet: \(error.localizedDescription)")
            referredUsers = []
        }
    }
}
