# Cauldron production-readiness audit — 2026-08-10

## Scope

- Current checkout on `codex/lasting-product-polish`
- iOS/iPad app, Mac Catalyst app, Widget, Share extension
- Firebase Functions/Hosting/Firestore and CloudKit-backed public sharing
- Findings-only audit; no product code changes

## Provenance

- `origin/main` fetched on 2026-08-10.
- Branch is 6 commits ahead and 12 commits behind `origin/main`.
- Working tree contains 107 modified tracked files plus many untracked source/test files.
- Committed branch delta from merge base: 69 files, 4,267 insertions, 578 deletions.
- Uncommitted tracked delta: 107 files, 12,832 insertions, 2,812 deletions.
- Xcode: 27.0 beta, build 27A5194q.
- App version/build: 1.8 (202607171354).

## Review areas

| Area | Status | Evidence / follow-up |
| --- | --- | --- |
| Source and release provenance | Finding | Dirty, diverged branch is not a reproducible release candidate. |
| Firebase functions/templates | Finding | Local build and 24 sanitizer tests pass; live recipe HTML is an older template. |
| Firebase rules/indexes/deployment | Finding | Rules are locked down locally, but have no emulator test suite; production CloudKit preflight could not run without named QA records/credentials. |
| iOS build/tests | Passed with gap | Debug and Release builds pass; 1,017 tests pass, 0 fail, 1 migration fixture test is skipped. |
| Mac Catalyst build/tests | Passed with gap | Debug and Release builds pass; 1,017 tests pass, 0 fail, 1 migration fixture test is skipped. |
| CloudKit/public sharing | Partial | AASA, secrets metadata, public recipe hydration, and seven legacy HTTP 426 cutoffs verified; full signed CloudKit preflight remains unverified. |
| App lifecycle/sync/import/social | Finding | Broad automated coverage passes, but store initialization still terminates the app on migration/corruption failure. |
| Real device/browser acceptance | Not proven | No signed archive, installation, physical-device upgrade, accessibility, or cross-browser acceptance run was performed from this checkout. |

## Findings

### P0 — No reproducible release candidate exists yet

The current branch is both behind `origin/main` and contains a very large uncommitted change set. A production build from this checkout would not map to a reviewable commit, cannot be reliably reproduced, and risks omitting untracked source files or mixing unrelated work.

### P0 — Firebase production dependency audit is not clean

`npm audit --omit=dev` reports 26 advisories in the production dependency tree: 3 critical, 15 high, 7 moderate, and 1 low. The installed Firebase packages are several major versions behind (`firebase-admin` 11.11.1 vs 14.2.0; `firebase-functions` 4.9.0 vs 7.3.2). Advisory reachability still needs case-by-case triage, but a release should not proceed until the runtime upgrade is tested and the production audit is either clean or each remaining advisory has a documented non-reachability/acceptance decision.

### P1 — Tested website code is not what production serves

The local sanitizer suite explicitly rejects “Shared recipe” and tests the canonical creator block. The live recipe response still contains “Shared recipe” and does not contain the local creator markup. Production is operational, hydrates the image/ingredients/instructions, and returns `private, no-store`, but it is behind this checkout. Deploy only after the full CloudKit preflight passes, then compare a live response against the tested template contract.

### P1 — Persistence failure is unrecoverable while the only real upgrade fixture is skipped

Production initialization calls `fatalError` when the persistent `ModelContainer` cannot open and directs the user to reinstall. Both platform suites skipped `testLegacyStoreFixtureOpensWithCurrentLocalSchema` because no fixture was supplied. That combination leaves the highest-impact upgrade failure untested and turns a migration/corruption problem into a launch loop. Add a versioned migration strategy, check a sanitized previous-release store into controlled test infrastructure (or fetch it securely in CI), and provide non-destructive backup/quarantine/recovery behavior before suggesting reinstall.

### P1 — There is no build/test/security CI gate

The only GitHub workflows invoke Claude; neither compiles the app, runs the 1,018-test suite, tests Firebase functions, audits dependencies, validates Firestore rules, or checks a Release build. A very large change set can currently merge without executable verification.

### P1 release gate — Full production CloudKit preflight is not proven

The predeploy hook correctly requires `preflight:production`, but this shell lacks the server key variables and named production QA records required to execute its signed schema/permission/content checks. Firebase secret metadata exists and all seven legacy endpoints return HTTP 426; that is useful partial proof, not a substitute for the full preflight.

### P2 — Firestore rules and TTL policy lack automated behavioral tests

The rules deny raw public reads locally and the indexes add TTL policies, but there is no Rules Test Environment/emulator test suite. Add allow/deny tests for every mutation/read path plus deployment smoke checks for TTL/index state.

### P2 — Dynamic web pages lack defense-in-depth browser headers

The live recipe has HSTS and a safe cache policy but no Content-Security-Policy, X-Content-Type-Options, Referrer-Policy, or Permissions-Policy response headers. Add a nonce/hash-compatible CSP and the remaining headers in the dynamic function response, then cover them with HTTP contract tests.

### P2 — Release and operational acceptance are still missing

Unsigned builds establish compilation only. Production readiness still requires a signed archive/export, TestFlight processing, install/upgrade on physical iPhone and iPad, Catalyst smoke testing, two-account CloudKit sharing, offline/reconnect replay, share-extension handoff, universal-link cold/warm launch, deletion/privacy cleanup, VoiceOver/Dynamic Type, and Safari/Chrome responsive web checks. The app has local privacy-safe OSLog diagnostics but no demonstrated Apple-native MetricKit/crash/launch-hang operational loop.

## Validation log

- 2026-08-10: fetched `origin`; established branch/diff/version/toolchain state.
- 2026-08-10: iOS Debug and Release builds passed.
- 2026-08-10: Mac Catalyst Debug and Release builds passed.
- 2026-08-10: iOS tests passed: 1,017 passed, 0 failed, 1 skipped (`Test-Cauldron-2026.08.10_15-37-13--0700.xcresult`).
- 2026-08-10: Catalyst tests passed: 1,017 passed, 0 failed, 1 skipped (`Test-Cauldron-2026.08.10_15-39-33--0700.xcresult`).
- 2026-08-10: Firebase TypeScript build and 24 sanitizer/contract tests passed.
- 2026-08-10: `git diff --check` passed.
- 2026-08-10: live AASA returned JSON for production/dev app IDs and required route families.
- 2026-08-10: all seven legacy mutation endpoints returned HTTP 426; CloudKit Firebase secrets each have an enabled version.
- 2026-08-10: live recipe returned HTTP 200 with image, ingredients, instructions, HSTS, and no-store; template drift and missing defense-in-depth headers confirmed.
- 2026-08-10: full CloudKit production preflight not run because the required local key and QA-record environment variables are unavailable.
- 2026-08-10: `npm audit --omit=dev` found 26 production-tree advisories (3 critical, 15 high, 7 moderate, 1 low).
