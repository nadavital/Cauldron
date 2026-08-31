# Cauldron 2.0.1 Cloud release

## Scope

- User requested new iOS and Mac uploads through Xcode Cloud, preserving the complete 2.0 release notes. No App Review submission authorized or performed.
- Version 2.0 is READY_FOR_SALE on both platforms, so this release uses 2.0.1.
- Source: `b974c6e5a29ed5977410fd9f4bb3c56f322c50e2` on `main`, containing all consolidated app and web changes.
- Project build seed: `202608300001`; Xcode Cloud assigns its own uploaded build numbers.
- In-app What's New content and its `2.0` gate are unchanged.
- Release configuration verification and diff checks passed. Existing unrelated QA artifacts were preserved.

## App Store metadata

- iOS draft: `c741148c-66fa-4a69-b1b3-d32060f1c2f9`.
- Mac draft: `e8b3084f-7314-4e35-a9b3-fcc4db5fbad1`.
- Both drafts use AFTER_APPROVAL, remain PREPARE_FOR_SUBMISSION, and copied all six localization metadata fields from their respective published 2.0 versions.
- Both en-US What's New fields were read back and match the full published 2.0 notes.

## Cloud builds

| Platform | Workflow | Run | Cloud run number | State |
| --- | --- | --- | --- | --- |
| iOS | App Store Release (Xcode 26.6) | `9c6bfc72-b19b-400e-81ea-6964f05b3d4f` | 744807093 | SUCCEEDED |
| Mac Catalyst | Mac App Store Release (Xcode 26.6) | `564ced56-a090-4740-968a-019b4fce0a04` | 744807094 | SUCCEEDED |

Both runs confirmed the exact release commit. Downloaded archive logs show `ARCHIVE SUCCEEDED`, Xcode build `17F113`, and SDK paths `iPhoneOS26.5.sdk` / `MacOSX26.5.sdk` (not SDK 27).

## Final delivery verification

- iOS uploaded build **202608270005**, ID `84f29f5a-edd6-450b-8b45-9e3ee04988a9`: VALID, attached to iOS 2.0.1 draft, IN_BETA_TESTING.
- Mac uploaded build **202608270006**, ID `271d4538-01c2-485f-bfb1-f34da110dcd3`: VALID, attached to Mac 2.0.1 draft, IN_BETA_TESTING.
- Both complete 2.0 notes also copied to their en-US TestFlight What to Test fields and read back.
- Both builds explicitly assigned to the internal group below; the group's build relationship read-back includes both IDs. An initial Mac assignment returned a transient 404 during propagation; retry succeeded and membership was independently confirmed.
- Both App Store versions remain PREPARE_FOR_SUBMISSION. No App Review or external beta submission performed.
- Cloud logs: `/tmp/cauldron-2.0.1-ios-cloud-logs.zip` and `/tmp/cauldron-2.0.1-mac-cloud-logs.zip` (temporary local evidence).

Internal group: `8ca42c13-9941-479d-91e2-80fad57fe7fe`, Friends and Family, `hasAccessToAllBuilds=true`. Do not add external groups or submit for review.
