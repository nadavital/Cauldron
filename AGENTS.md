# AGENTS.md

Guidance for coding agents working in this repository.

## Project Snapshot
- App: `Cauldron` (SwiftUI-first recipe app)
- Main targets: iOS/iPad app, Mac Catalyst app, Widget extension, Share extension
- Core backend: CloudKit (+ Firebase for share-link hosting endpoints)
- Parser stack: model-backed import pipeline with parity-tested assembly

## Repository Layout
- App code: `/Users/nadav/Desktop/Cauldron/Cauldron`
- Tests: `/Users/nadav/Desktop/Cauldron/CauldronTests`
- Share extension: `/Users/nadav/Desktop/Cauldron/CauldronShareExtension`
- Widget: `/Users/nadav/Desktop/Cauldron/CauldronWidget`
- Parser tooling/labs: `/Users/nadav/Desktop/Cauldron/tools`

## Build And Test Commands
- iOS build:
  - `xcodebuild build -scheme Cauldron -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO`
- Mac Catalyst build:
  - `xcodebuild build -scheme Cauldron -destination 'platform=macOS,variant=Mac Catalyst,name=My Mac' -configuration Debug CODE_SIGNING_ALLOWED=NO`
- iOS tests:
  - `xcodebuild test -scheme Cauldron -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug CODE_SIGNING_ALLOWED=NO`
- Mac Catalyst tests:
  - `xcodebuild test -scheme Cauldron -destination 'platform=macOS,variant=Mac Catalyst,name=My Mac' -configuration Debug CODE_SIGNING_ALLOWED=NO`

## Current Product Priorities
- Maintain first-class iPad and Mac experiences (not only iPhone layouts)
- Preserve parser quality and import consistency across share sheet, URL, and text flows
- Keep social/invite flows stable and performant
- Favor practical incremental changes over broad refactors unless requested

## Critical Features And Behaviors
- Import quality is core product value:
  - Model-backed parser + shared import pipeline should stay consistent across URL, text, and share-extension entry points.
  - Parser behavior changes should keep parity/regression tests green.
- Social sharing is a core workflow:
  - Invite links/referrals, friend connections, and profile/friends UX should remain reliable and low-friction.
  - CloudKit + Firebase share-link behavior must remain compatible with associated domains and app routing.
- Large-screen experience is intentional:
  - iPad layouts are first-class, not stretched iPhone views.
  - Mac app behavior is intentionally supported via Mac Catalyst target configuration.
- Offline-first sync reliability matters:
  - Operation queue + CloudKit sync paths should not be bypassed without a clear migration plan.
- Update-surface behavior matters:
  - `What's New` is gated by content version and should be updated for meaningful user-visible changes.

## Release/Update Checklist
- App versioning is managed in:
  - `/Users/nadav/Desktop/Cauldron/Cauldron.xcodeproj/project.pbxproj`
  - `MARKETING_VERSION` should be updated consistently across targets.
- "What’s New" screen:
  - UI content: `/Users/nadav/Desktop/Cauldron/Cauldron/Features/Settings/WhatsNewView.swift`
  - show-once content gate: `/Users/nadav/Desktop/Cauldron/Cauldron/ContentView.swift` (`whatsNewContentVersion`)
- If update text changes materially, bump `whatsNewContentVersion` so existing users see it.

## Platform Notes
- Mac app path is Mac Catalyst-enabled in the main target.
- Embedded iOS extensions are filtered for iOS-only embedding in project settings.
- ActivityKit/Live Activities are conditionally excluded from Mac Catalyst code paths.

## Working Norms
- Keep SwiftUI code idiomatic and readable; prefer focused edits over wide churn.
- When touching parser or import flows, run relevant parser/import tests before finalizing.
- Avoid modifying unrelated files in a dirty worktree.
- Do not remove existing product behavior unless explicitly requested.

## AGENTS.md Maintenance Rules
- Update this file in the same PR whenever any of the following changes:
  - Build/test commands, destinations, scheme names, or required flags
  - App targets/platform support (iOS/iPad/Mac Catalyst/extension behavior)
  - Core architecture boundaries (new layer, service ownership shift, major DI changes)
  - Critical feature workflows (import/parser pipeline, sharing/invites, sync model)
  - Release/update process (`MARKETING_VERSION`, `What's New` gating, rollout steps)
- Keep updates minimal and factual; prefer editing existing sections over adding noisy new ones.
- If a change is temporary, annotate it as temporary and include expected cleanup timing.
