# Website follow-up status — 2026-08-30

## Production release verification (latest)

- User explicitly approved the previously blocked localhost and production
  preflight operations. Browser access and signed checks succeeded.
- Full preflight passed: 102 tests, production CloudKit User/UsernameClaim/
  SharedRecipe/Collection checks, and the high-severity dependency audit gate.
  Seven moderate transitive uuid advisory entries remain; no blind downgrade.
- All seven legacy mutation endpoints returned HTTP 426 before deployment.
- Firebase Functions deployment completed, including discovery, owner-manifest
  reconciliation, and public-profile backfill. Hosting/rules/indexes deployed.
- Backfill scheduler is ENABLED, every two hours; first successful execution
  has not yet been observed. Do not claim additional creators were indexed.
- Browser QA caught homepage image intrinsic sizing expanding the hero after
  loading. Images now fill a positioned container; desktop hero stayed 420px
  with all nine current photos loaded. The previewHome correction was deployed
  separately and confirmed in production HTML.
- Live desktop/mobile homepage/category checks and mobile recipe/collection
  checks showed no horizontal overflow. Recipe had 10 ingredients and six steps.
- `/u/nadav` now has matching canonical metadata. The legacy UUID profile route
  redirects to it. Shared headers are present across checked live pages.
- Hosted monitor passed all 17 route/API checks plus sampled homepage images
  and recipe destinations. Initial image probe failed because Apple returns
  HEAD 501 and JPEG bytes as octet-stream. It now checks bounded JPEG/PNG/WebP
  signatures and cancels the response stream instead of relying on MIME alone.
- QA screenshots: `.agent/web-release-qa-2026-08-30/` (local, not published).
- Remaining: the default-branch scheduled GitHub monitor still uses old profile
  expectations. User was asked whether to merge the consolidated branch into
  main; no merge performed without that choice. `www` DNS remains unchanged
  and pending its separate approval. Native device app-opening not retested.

## Implementation history (before deployment)

- All active public templates now use one header markup/style implementation.
- Discovery combines 24 recent summaries with an age-independent, wrapping
  daily document-ID sample of 36 summaries. It validates up to 24 candidates and
  reselects up to 12 pictured recipes using current tags and creator diversity.
- Archive selection is deterministic sampling, not guaranteed exhaustive rotation.
- Hosted checks now fail on empty discovery and probe three displayed image and
  canonical recipe destinations. These checks are public, bounded, and do not
  replace rendered browser or device QA.
- TypeScript build and 82 web unit/contract tests passed. All 20 emulator tests
  passed, including an actual archive query covering old/timestamp-less records.
- No new deployment or browser/local-preview approval was obtained in these
  follow-ups; production and visual verification gates below remain outstanding.

## Source provenance

- Shared checkout: `/Users/nadav/Desktop/Cauldron`.
- Branch: `codex/app-web-polish-2026-08-30`.
- Base consolidation commit: `d284651` (app, website, screenshot generator work).
- Native generator action, Mac profile footer/sidebar, avatar handling, profile
  layout, and native performance changes are included in that commit.
- Generated screenshot outputs remain local/ignored, not uploaded by this task.
- Unrelated `.agent` QA artifacts and the old dirty detached worktree are preserved.

## This follow-up

- Homepage preview calls the production discovery loader with real Firebase
  summaries and current public CloudKit validation. No fake recipes or writes.
- Detail links from localhost explicitly open production; they are not evidence
  of un-deployed detail template changes.
- Recipe shelf titles, time, and tags now come from validated CloudKit records.
- Category filters include all recognized categories, not just the first.
- Failed homepage images hide their card even if they fail before script setup.
- Preview handler rejects writes/traversal, handles missing files, and avoids
  logging sensitive backend error bodies.

## Verification

- TypeScript build passed.
- 75 sanitizer/hosted-monitor-unit/preview tests passed.
- 19 Firestore security-rules emulator tests passed with Java 21.
- `git diff --check` passed.
- Production-data homepage HTTP request succeeded: 10 indexed, 9 validated,
  1 creator, approximately 2.5 seconds for that request. This is one observation,
  not a performance benchmark. The later metadata/filter changes were tested
  locally but are not yet loaded by the running preview process.
- No new native build/device QA performed in this website follow-up.

## External state and remaining gates

- Firebase `www.cauldronrecipes.com` redirect-domain resource was created with
  target `cauldronrecipes.com`; DNS/certificate validation remains pending.
- Vercel's apex records were not changed. Explicit www CNAME and certificate TXT
  additions require the pending user approval.
- Browser policy rejected localhost navigation. User approval was requested;
  no alternate browser, headless tool, or indirect screenshot bypass was used.
- Production preflight was blocked by auto-review pending approval for npm
  advisory metadata and read-only CloudKit fixture verification using the
  existing signing credential. Do not bypass this gate or deploy without it.
- No Functions/Hosting deployment was performed in this follow-up.
- After approval: restart preview, capture desktop/mobile screenshots, run
  production preflight, deploy Functions/Hosting, finish DNS, verify canonical
  and legacy routes/OG assets/hosted monitor, and separately prove app opening.
- The production Firebase index currently contains recipes from only one creator.
  Pending scheduled public backfill may improve diversity only if other eligible
  public CloudKit recipes exist; do not imply rotation can invent more authors.
