# Website follow-up status — 2026-08-30

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
