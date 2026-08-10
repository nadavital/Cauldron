# Performance and Reliability Audit — 2026-07-12

## Scope

- Review target: latest remote source (`fcf0489`), tree-identical to `origin/main` (`d199ba2`).
- User request: findings and prioritized suggestions only; no product-code changes.
- Symptoms: app is broadly slow and flaky; no single reproduction path supplied.

## Review areas

- SwiftUI rendering, state propagation, images, navigation
- CloudKit, offline queue, social persistence, lifecycle
- Import, parser, share extension
- App startup, cross-cutting concurrency, tests and build health

## Evidence ledger

| Area | Status | Findings / evidence |
| --- | --- | --- |
| Remote synchronization | Complete | Current branch matches upstream; source tree matches `origin/main`. |
| SwiftUI/UI | Complete | Main-thread image byte comparisons; eager non-lazy result/collection rows; synchronous avatar file decode in `body`; unstable random search-user sentinel. |
| Sync/data/social | Complete | Duplicate CloudKit membership/tombstone scans; serial two-request edge writes; repeated full local edge scans; overlapping retry loops and startup warmups. |
| Import/parser/share | Complete | Network image localization gates preview/save; extension waits up to 12s on extraction; social fetch path lacks hardened networking; single-slot share inbox can overwrite. |
| Startup/concurrency/build | Complete | UI readiness waits on serial CloudKit session work and full-store cleanup/migration. Cloud image migration creates non-terminating event consumers on every status change. |

## Validation

- Generic iOS Simulator build completed successfully with app-icon selection disabled to isolate the unrelated local icon edit.
- Mac Catalyst build completed successfully with the same icon override.
- Added focused collection membership batch mapping and share FIFO/malformed-head regression tests.
- XCTest execution remains blocked by the local CoreSimulator/simdiskimaged service and Icon Composer `actool` failures from the unrelated `CauldronIcon.icon/icon.json` change.
- Final changed Swift sources and tests pass `swiftc -frontend -parse`; `git diff --check` passes.
- Seventeen fresh-context review rounds were completed. Every actionable finding was addressed; round 17 reported no actionable correctness, privacy, data-loss, or concurrency findings.

## Residual risks / manual follow-up

- No runtime reproduction, device/OS, or Instruments trace was supplied; static findings must be distinguished from measured bottlenecks.
- Runtime launch/frame/request-count deltas still require a working simulator/device capture.
