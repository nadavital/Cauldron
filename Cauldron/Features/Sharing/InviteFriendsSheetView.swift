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
            ScrollView {
                GlassEffectContainer(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        heroSection
                        actionSection
                        invitesAndRewardsSection
                    }
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.xl)
                }
            }
            .warmCanvas()
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
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: "person.badge.plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.cauldronOrange)
                .frame(width: 48, height: 48)
                .glassEffect(.regular, in: Circle())

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Bring your recipes together")
                    .font(Theme.Typography.sectionTitle)

                Text("Your invite link connects you automatically when a friend joins Cauldron.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var invitesAndRewardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("People You Invited")
                .font(.headline)

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
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    }
                }
            }
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let user = currentUserSession.currentUser {
                let referralCode = referralManager.generateReferralCode(for: user)
                let inviteURL = referralManager.getShareURL(for: user)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Invite code")
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
                            .buttonStyle(.glass)
                        }
                        .padding(Theme.Spacing.sm)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    }

                    Button {
                        shareLink = ShareableLink(
                            url: inviteURL,
                            previewText: referralManager.getShareText(for: user),
                            image: nil
                        )
                    } label: {
                        Label("Share Invite Link", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.extraLarge)
                    .tint(.cauldronOrange)
                }
            } else {
                Label("Sign in to generate your invite link.", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
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
