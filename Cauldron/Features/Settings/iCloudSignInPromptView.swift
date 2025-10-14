//
//  iCloudSignInPromptView.swift
//  Cauldron
//
//  Created by Claude on 10/8/25.
//

import SwiftUI

/// View shown when user is not signed into iCloud
struct iCloudSignInPromptView: View {
    let accountStatus: CloudKitAccountStatus
    let onRetry: () async -> Void
    let onContinueWithoutCloud: (() -> Void)?

    @State private var isRetrying = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Icon
                Image(systemName: statusIcon)
                    .font(.system(size: 80))
                    .foregroundColor(statusColor)

                // Title and message
                VStack(spacing: 16) {
                    Text(statusTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text(statusMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if let suggestion = recoverySuggestion {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.cauldronOrange)
                                Text("How to fix:")
                                    .fontWeight(.semibold)
                            }

                            Text(suggestion)
                                .font(.subheadline)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cauldronOrange.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                }

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        Task {
                            isRetrying = true
                            await onRetry()
                            isRetrying = false
                        }
                    } label: {
                        HStack {
                            if isRetrying {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Check Again")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.cauldronOrange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isRetrying)

                    if let continueAction = onContinueWithoutCloud {
                        Button {
                            continueAction()
                        } label: {
                            Text("Continue Without Cloud Sync")
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationBarHidden(true)
        }
    }

    private var statusIcon: String {
        switch accountStatus {
        case .noAccount:
            return "icloud.slash"
        case .restricted:
            return "lock.icloud"
        case .temporarilyUnavailable:
            return "icloud.slash"
        default:
            return "exclamationmark.icloud"
        }
    }

    private var statusColor: Color {
        switch accountStatus {
        case .restricted:
            return .red
        case .temporarilyUnavailable:
            return .orange
        default:
            return .gray
        }
    }

    private var statusTitle: String {
        switch accountStatus {
        case .noAccount:
            return "Sign in to iCloud"
        case .restricted:
            return "iCloud Access Restricted"
        case .temporarilyUnavailable:
            return "iCloud Temporarily Unavailable"
        default:
            return "iCloud Connection Issue"
        }
    }

    private var statusMessage: String {
        switch accountStatus {
        case .noAccount:
            return "Cauldron uses iCloud to sync your recipes across devices and share them with friends. Please sign in to iCloud to continue."
        case .restricted:
            return "iCloud access is restricted on this device. This may be due to parental controls or device management settings."
        case .temporarilyUnavailable:
            return "iCloud services are temporarily unavailable. Please try again in a few moments."
        default:
            return "We're having trouble connecting to iCloud. Please check your settings and try again."
        }
    }

    private var recoverySuggestion: String? {
        switch accountStatus {
        case .noAccount:
            return "Open the Settings app, tap your name at the top, then sign in with your Apple ID."
        case .restricted:
            return "Check Settings > Screen Time > Content & Privacy Restrictions to see if iCloud is restricted."
        case .temporarilyUnavailable:
            return "Wait a few minutes and tap 'Check Again'. If the problem persists, check Apple's System Status page."
        default:
            return nil
        }
    }
}

#Preview("No Account") {
    iCloudSignInPromptView(
        accountStatus: .noAccount,
        onRetry: {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        },
        onContinueWithoutCloud: {
            print("Continue without cloud")
        }
    )
}

#Preview("Restricted") {
    iCloudSignInPromptView(
        accountStatus: .restricted,
        onRetry: {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        },
        onContinueWithoutCloud: nil
    )
}
