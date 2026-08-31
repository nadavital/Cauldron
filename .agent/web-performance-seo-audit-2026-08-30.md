# Website performance, public coverage, and SEO audit

## Scope and proof boundaries

Production `https://cauldronrecipes.com`, August 30, 2026 (Pacific). Checked homepage, profile, recipe, collection, invite, missing recipe, robots, sitemap, compatibility links, public data APIs, and www redirect. Rendered profile/collection at desktop and 390px mobile widths; checked recipe hero after loading. This is an HTTP/DOM/source lab audit, **not** Lighthouse or real-user Core Web Vitals and not a guarantee of Google indexing/ranking.

## User coverage: the actual blocker

- Read-only CloudKit scan completed across all three pages: 54 public User records / 54 owners.
- All had canonical record ownership; 1 lacked usable public identity fields, 52 lacked a valid creator-owned UsernameClaim, and 1 had a valid claim.
- Firebase initially had 178 recipe summaries from 15 creators. After canonical reconciliation it had 130 summaries, 89 structurally valid summaries from 15 creators. These are derived index rows, not authoritative recipe deletions.
- Homepage currently displays 9 validated pictured recipes from the sole claim-eligible creator. Rotation cannot bypass missing identity claims.
- Existing users with a valid claim and public synced recipes are included server-side without opening the app or pressing Share. Legacy users missing a claim must open a migration-capable app once with iCloud available and let sync finish. `ContentView.repairPublicWebSnapshots` calls profile publication, which registers the capability and ensures the creator-owned claim. Local-only/unsynced/private/revoked content remains excluded.
- The server must not manufacture creator-owned claims or relax creator validation to fill the homepage.
- Running backfill exposed a second blocker: continuation requests omitted the required original query, so the second page returned CloudKit HTTP 400. Fixed all three affected paths: User backfill, SharedRecipe owner queries, CollectionMembership queries. Added a shared request builder and regression test. The read-only audit itself verified the corrected three-page query.

## Implemented and deployed

1. Profile/collection recipe photos now occupy an absolute, fixed-aspect-ratio layer above their fallback. Real loaded photos no longer display the Cauldron logo; the fallback remains for missing/failed images. Confirmed on live desktop profile and mobile profile/collection.
2. First visible grid photo has high fetch priority; the next two load eagerly; remaining photos remain lazy. Image geometry remains 4:3 during loading.
3. Profile shelf reuses its already-validated owner within the same request, removing duplicate CloudKit identity/claim/image lookups. No cross-request cache or relaxed authorization.
4. Recipe JSON-LD uses the stable same-origin recipe image proxy and includes actual creator attribution, description, and canonical URL. It does not invent reviews, nutrition, or publication dates.
5. `/sitemap.xml` now contains current validated discovery recipes instead of only the homepage (10 URLs at verification). It is intentionally a conservative discovery sitemap, **not an exhaustive catalog sitemap**. Validation failure returns 503/Retry-After rather than stale entries.
6. Unavailable pages have noindex; invite handoffs have X-Robots-Tag noindex/follow. They remain usable and shareable.
7. Unversioned static brand assets have a one-day browser cache. Dynamic content keeps no-store so deletion/privacy changes are checked on each request.
8. Hosted monitor now checks sitemap health and permits only the matching stable recipe proxy, not the generic brand fallback, as recipe structured-data imagery.
9. Added reusable read-only `auditPublicIndex.mjs` (aggregate identities only) and `auditHostedWeb.mjs` (HTTP timing/SEO summaries; no credential output).

## Timing observations

Three sequential samples per primary route, same Mac/network. Median time to response headers, seconds:

| Route | Before | After first deployment | HTML size after |
| --- | ---: | ---: | ---: |
| Home | 1.52 | 1.43 | 25.6 KB |
| Profile | 2.08 | 1.52 | 21.4 KB |
| Recipe | 1.42 | 1.30 | 19.3 KB |
| Collection | 1.83 | 2.34 | 17.8 KB |

The profile reduction is consistent with removing duplicate reads, but this sample cannot establish a statistically reliable improvement. Collection varied from 1.8s to 5.0s across checks and is still a priority. No claim that every route became faster.

Rendered pages have no external JS bundles or stylesheet/webfont files. HTML download time is small compared with backend waiting. A homepage card rendered at 229px used a 2000px photo; most other 292px cards used 1320px photos. Oversized imagery and backend round trips, not framework bundle size, are the primary optimization targets.

## Remaining priorities and tradeoffs

1. **Responsive image variants:** generate bounded thumbnail sizes (e.g. 320/640/1280) with modern formats, preserving original recipe images. Choose durable revision keys, deletion invalidation, storage/lifecycle limits and CloudKit-origin validation before implementation. No arbitrary public image-proxy URLs. This adds image processing/storage work and should be budgeted, not hidden behind an unbounded resize endpoint.
2. **Further same-request reuse and batching:** collection validation repeats owner work; profile/collection visibility checks issue per-record reads. Reuse validated identities and batch privacy/revocation records without weakening final content checks. Benchmark independently after each change.
3. **Exhaustive catalog discovery:** current public profile/collection pages cap displayed cards and sitemap follows daily discovery. Add cursor-based browse pages and a bounded validated sitemap index as the eligible public catalog grows; avoid offset scans or a request that validates the entire database.
4. **Search Console and field measurement:** verify the domain property, submit the sitemap, run Google's Rich Results Test on representative live recipes, and inspect actual indexing/field Core Web Vitals. This task has not verified Search Console ownership or real-user LCP/INP/CLS. Do not claim rankings or rich-result appearance.
5. **Homepage/schema refinement:** homepage currently describes the app with SoftwareApplication data. Consider WebSite plus an ItemList of the visible recipe collection; profile/collection structured data can describe actual visible lists. Do not add fictitious ratings just to satisfy app rich-result recommendations.
6. **Bounded caching only with invalidation:** full CDN page caching would improve TTFB but can serve deleted or unshared content. Current strict no-store policy is intentional. Keep it until a reviewed revision/revocation-aware strategy exists.
7. **Dependency maintenance:** high-severity production audit gate passes; 7 moderate transitive uuid advisory entries remain. Resolve via compatible upstream updates, not forced breaking downgrades.

## Verification and operations

- Full production preflight passed after selecting installed Java 21 and the existing production credential wrapper: source/monitor/preview/security-rule tests plus signed CloudKit User/UsernameClaim/SharedRecipe/Collection checks.
- Final total after the additional monitor header test: 107 tests (62 sanitizer, 19 monitor, 6 preview, 20 rules).
- Main web/SEO deployment succeeded; pagination deployment succeeded for backfillPublicProfiles, previewCollection and api; final Hosting-only invite header deployment succeeded.
- Hosted monitor passed its 18 route/API/sitemap checks plus sampled homepage images and destination checks.
- HTTPS www returns 301 to the matching non-www path; canonical links use the apex. Favicon responds as SVG with one-day cache. Invite noindex header read back live.
- The redirect also preserves query parameters. The stable recipe social image proxy returned HTTP 200 with `image/jpeg`, not the generic artwork redirect.
- Mobile profile screenshot: `.agent/web-release-qa-2026-08-30/profile-no-overlay-mobile.png` (local QA artifact, not committed).
- No app source changed in this task, and no new native upload or App Review submission was performed. Existing TestFlight builds use the updated backend automatically.
- Temporary detailed output: `/tmp/cauldron-hosted-web-audit-20260830.jsonl`, `/tmp/cauldron-hosted-monitor-20260830.log`, `/tmp/cauldron-backfill-deploy-20260830.log`.
- Final backfill cycle completed at 2026-08-31T02:05:37.102Z: pending 0, failed 0, morePages false. No additional profiles materialized because the remaining legacy identities lack valid creator-owned username claims.

## Primary references

- Google recipe structured data: https://developers.google.com/search/docs/appearance/structured-data/recipe
- Google sitemap guidance: https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap
- Web performance image priority: https://web.dev/articles/optimize-lcp
- CloudKit continuation requests require query: https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/QueryingRecords.html
