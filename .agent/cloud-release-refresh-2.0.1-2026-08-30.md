# Cauldron 2.0.1 refreshed Cloud release

## Source and intent

- User requested fresh Xcode Cloud builds for iOS/iPadOS and Mac, full version 2.0 update notes, and the refreshed screenshots on every supported platform.
- Release source: `d12ff7ccf89f600a0ff23dab6cfdbd8aedf188f6`, pushed to `main`.
- Marketing version stays `2.0.1`; version 2.0 is already published. Project build seed increased to `202608300002` across all eight configurations; Xcode Cloud assigns its own uploaded build numbers.
- Release configuration verification and `git diff --check` passed. Native source is unchanged from the previous successful Cloud release at `b974c6e`; this is a fresh archive of consolidated main, not a claim of new native behavior or new device QA.
- Existing unrelated screenshots and QA artifacts preserved; release-number change prepared in an isolated temporary worktree.

## Cloud delivery

| Platform | Workflow | Cloud run | Uploaded build | Build ID | Final state |
| --- | --- | --- | --- | --- | --- |
| iOS / iPadOS | App Store Release (Xcode 26.6) | `58a9b9e7-f518-4ce2-847c-0c734615e9c6` | `202608270007` | `3f4f993a-3e93-454d-b83b-d2572a241b3c` | SUCCEEDED; VALID; attached |
| Mac Catalyst | Mac App Store Release (Xcode 26.6) | `7730295a-8d9b-4bd8-b489-362b1b67a2cd` | `202608270008` | `9634efe0-37a1-46e4-97ea-c12ff21b626f` | SUCCEEDED; VALID; attached |

Both runs read back the exact release commit. Downloaded archive/export logs contain `ARCHIVE SUCCEEDED`, `EXPORT SUCCEEDED`, Xcode build `17F113`, and SDK paths `iPhoneOS26.5.sdk` / `MacOSX26.5.sdk`. No SDK 27 archive was uploaded. Both processed builds report `usesNonExemptEncryption=false`.

## Notes and screenshots

- Draft iOS version: `c741148c-66fa-4a69-b1b3-d32060f1c2f9`; Mac: `e8b3084f-7314-4e35-a9b3-fcc4db5fbad1`.
- Both draft en-US What's New fields match their published 2.0 equivalents byte-for-byte. Full notes also copied into both new builds' TestFlight What to Test fields and independently read back.
- Assets: `appstorescreenshots/output/cauldron_2_0_appstore/{iPhone,iPad,Mac}`. Existing rendered design retained; no synthetic replacement screenshots or new framing.
- Seven iPhone (1320 x 2868), five iPad (2048 x 2732), seven Mac (2560 x 1600). All local asset dimensions validated; source SHA-256 hashes match their render manifests. Contact sheets plus representative full-size assets visually reviewed, including the Mac profile footer and visible generator save action.
- All 19 uploaded assets verified in order, with exact local MD5/sourceFileChecksum equality and Apple's `COMPLETE` delivery state. No duplicate or incomplete uploads remain.
- Old 6.5-inch iPhone override backed up and removed, including the empty set, so Apple's scaling uses the new high-resolution iPhone images. The old iPhone/iPad/Mac draft assets were downloaded before replacement.
- Transient Apple object-storage TLS/broken-pipe failures recovered using the same artwork; incomplete upload placeholders were explicitly removed. Recovery records moved outside the repository.

## Final review gate

- Both versions read back `PREPARE_FOR_SUBMISSION` with the new build IDs above. Existing `AFTER_APPROVAL` release behavior was not changed.
- Both `asc validate` checks: zero errors, zero warnings, zero blocking items. Both `asc review submit --dry-run` checks returned `wouldSubmit=true`, with the expected build already attached.
- One informational limitation remains: App Privacy publication state is not available through the public API. The browser requested Apple sign-in, so its live UI state was not independently confirmed this turn. No privacy declarations were changed.
- No App Review submission was performed. Asked the user whether to press Submit for Review for both platforms or leave that final step to them; await explicit direction.
- Temporary evidence and screenshot backups: `/private/tmp/CauldronASC20260830/`.
