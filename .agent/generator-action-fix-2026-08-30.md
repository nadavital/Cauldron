# Shared generator action fix — 2026-08-30

## Scope

Generator UI only. Preserve the shared dirty `main` checkout and all unrelated profile, sync, image, and web work. No commit, push, release, or screenshot-set publication performed.

## Findings and changes

- Original Generate/Save action was conditionally inserted into an animated bottom-aligned ZStack with a hard-coded 100-point content spacer.
- Runtime isolation on Mac: even after moving to a persistent safe-area inset, restoring `.glassProminent` reproduced the invisible button while accessibility still exposed it. Switching the same control to `.borderedProminent` rendered it correctly. The user also reported the original symptom on iPhone.
- Keep a persistent primary action with explicit Generate / Generating / Save / Saving states. Empty/unavailable input disables Generate instead of removing it.
- Use a compact native orange capsule, not a full-width button or material footer strip. Reserve bottom space using the safe-area inset and let the system account for the keyboard.
- Move the animated gradient into a background so it does not participate in sizing; remove prompt-driven whole-screen spring animations and the fixed spacer.
- Disable Regenerate during saving to avoid replacing the displayed result during an in-flight save.

## Automated verification

- Mac Catalyst Debug build: passed, `/tmp/CauldronGenerator-Mac-build.log`.
- iOS Simulator Debug build: passed, `/tmp/CauldronGenerator-iOS-build.log`.
- `AIRecipePrimaryActionTests`: 8 passed on iPhone 17 / iOS 26.5. Covers empty/whitespace, prompt clearing, category-only input, unavailable model, generating, completed save, saving/failure retry, generation failure retry.
- Test result: `/tmp/CauldronIntegrated-iOS/Logs/Test/Test-Cauldron-2026.08.30_16-57-45--0700.xcresult`.
- `git diff --check`: passed.

## Interactive verification

All input-state checks use the real Add → Generate sheet with `--cauldron-simulator-qa --cauldron-ai-preview`, not the nested screenshot-scene wrapper.

- Mac Catalyst, normal-size window: visible disabled empty action; valid prompt enables; clearing disables; Vegetarian-only input enables; Generate becomes disabled in-progress control. Foundation Models actually generated Creamy Mushroom Risotto; Save was visible and tappable. Long content scrolls to the end with the action still reachable.
- iPhone 17 / iOS 26.5 simulator: empty, typed, keyboard shown, keyboard dismissal on Generate, category-only, model-error and retry checks passed.
- iPad Pro 11-inch (M5) / iOS 26.5 simulator: empty, typed, portrait/landscape with keyboard, generating, model-error and retry checks passed.
- Completed-state Save remained visible and enabled on both simulators using the deterministic preview. Evidence: `/tmp/CauldronGenerator-QA/iphone-seeded-save.jpeg` and `/tmp/CauldronGenerator-QA/ipad-seeded-save.jpeg`.
- Mac evidence: `/tmp/CauldronGeneratorQA/mac-{empty,typed,cleared,category-only,outcome,save-retry}.jpeg`.
- Simulator evidence: `/tmp/CauldronGenerator-QA/iphone-*.jpeg`, `/tmp/CauldronGenerator-QA/ipad-*.jpeg`.

## Proof limits

- Simulators return the expected Foundation Models unavailable/error result; they do not establish live model-generation success.
- Saving the Mac-generated recipe in the synthetic QA account was rejected by the existing account-scope safety guard ("Your iCloud account changed while saving"). Save recovered for retry. No guard was bypassed; successful account-backed persistence is not claimed.
- Completed-state simulator checks use the existing deterministic screenshot preview, not actual model output. Final tested iOS debug dylib SHA-256: `4059a5fbecb0300831b0132eab15f610bb19d29177926e7749254d7e07b5b5df`.
