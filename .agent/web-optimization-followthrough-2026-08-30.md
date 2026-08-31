# Website optimization follow-through

## Scope and release boundary

Follow-up to `web-performance-seo-audit-2026-08-30.md`. Website/backend only, on `codex/web-performance-seo-audit`; existing app changes and unrelated QA/screenshot artifacts preserved. No native build or App Review action. Main-branch merge requires explicit approval because the user requested a review branch. The scheduled GitHub hosted monitor runs from main and needs the updated monitor contract merged; local execution of the updated hosted monitor passes against production.

## Implemented

- Responsive 320/640/1280 WebP images with explicit `srcset`/layout-aware `sizes`, including the larger homepage feature and recipe hero. Fixed-origin UUID routes cannot proxy arbitrary URLs. Original CloudKit images remain untouched.
- Fresh publication, privacy/revocation, canonical owner and current public recipe validation precedes each thumbnail cache lookup. Bytes only are cached: 16 MB/process, 10-minute expiry, asset-revision key, 128-entry bound. No permanent image bucket, third-party image service or cross-request authorization cache. Download cap 10 MB, decode cap 16 MP, transform timeout 3 seconds; max three image instances, independent 360/minute client image budget. Social photo responses also now use no-store.
- Batched Firestore privacy/revocation reads; request-local owner lookup reuse across sparse candidate batches; recipe and collection rendering reuse their already validated owner; no unnecessary avatar fetch for shelf validation.
- `/recipes` and profile/collection cursor navigation. Up to 24 visible items, bounded four-batch sparse filling, no dropped lookahead records, self-referencing page canonicals, and resilient deleted-boundary handling. Legacy collection IDs deduplicated to prevent cursor loops.
- Six-hourly atomic ID-only catalog/sitemap manifest. One bounded manifest read replaces repeated scans through ineligible legacy accounts for global browse. Candidate IDs are never content authority: every rendered card and sitemap leaf rechecks current public CloudKit content and Firebase guards. New global catalog entries may take six hours to appear; profiles use live queries. Expired/missing manifests fall back to bounded live catalog scanning.
- `/sitemap.xml` is an index of small validated leaves; unavailable authoritative reads return 503. Empty leaves after legitimate removals remain valid. Refresh verified through the real deployed Scheduler path at `2026-08-31T02:26:11.285Z`: scanned 130, included 9, one leaf; job is ENABLED, every six hours.
- Homepage WebSite + visible ItemList structured data; profile, collection and browse ItemLists. No invented ratings, nutrition, dates or videos.
- Preview routes and hosted monitor updated for thumbnails, sitemap index/leaf traversal and deletion edge cases.

## Lab observations

Three HTTP samples per existing primary route immediately after first deployment. These are not field Core Web Vitals; cold-start/network variability remains, and profile did not improve in this sample.

| Route | Median response headers |
| --- | ---: |
| Home | 1.234 s |
| Profile | 2.095 s |
| Recipe | 0.910 s |
| Collection | 1.641 s |
| Sitemap index (one request) | 0.242 s |

Recipe previously measured ~1.30 s in the prior audit; this sample measured ~0.91 s. Do not claim statistically established gains from three requests.

Actual cake image delivery: original 1320px JPEG 589,508 bytes; 320px WebP 26,586 bytes (~95% smaller), 640px WebP 95,012 (~84% smaller), 1280px WebP 247,768 (~58% smaller). Individual thumbnail HTTP requests were 2.1–2.8 seconds including fresh backend checks, so byte reduction is not a claim of zero image latency. Cold starts and network costs still exist.

Google PageSpeed Insights UI worked after the unauthenticated API returned quota exhaustion. Lighthouse 13.4.1, emulated mobile/slow 4G, single-run results:

| Page | Performance | Accessibility | Best practices | SEO | LCP | CLS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Home (after featured-size refinement) | 98 | 100 | 100 | 100 | 1.7 s | 0 |
| Recipe | 98 | 100 | 100 | 100 | 2.3 s | 0 |
| Profile | 99 | 100 | 100 | 100 | 1.4 s | 0 |
| Collection | 98 | 100 | 100 | 100 | 1.8 s | 0 |

All measured zero total blocking time. The earlier homepage desktop run scored 94/100/100/100 with 0.3s LCP and 0 CLS. These automated checks do not guarantee accessibility, rankings or real-user performance. Google reports **No Data** for field metrics; no new visitor tracking was added.

Reports:
- Home: https://pagespeed.web.dev/analysis/https-cauldronrecipes-com/wjb2zm9ss0?form_factor=mobile
- Recipe: https://pagespeed.web.dev/analysis/https-cauldronrecipes-com-recipe-7DBEAFFD-895F-43B1-9985-463F36EA5D8C/9319yshwvb?form_factor=mobile
- Profile: https://pagespeed.web.dev/analysis/https-cauldronrecipes-com-u-nadav/3flgle54bu?form_factor=mobile
- Collection: https://pagespeed.web.dev/analysis/https-cauldronrecipes-com-collection-9B0D2D38-3B17-406A-83EC-3F35B21BDB42/vytdspi94h?form_factor=mobile
- Google Rich Results Test detected one valid Recipe; optional warnings for absent video, nutrition, ratings, cuisine and per-step metadata remain intentionally truthful: https://search.google.com/test/rich-results/result?id=rruh1cEB7iH-2Z57zTpzeg

## Verification

- Full preflight passed before both broad deployments (sanitizer/optimization, monitor, preview, Firestore rules, production dependency high-severity gate, signed CloudKit contracts).
- Five fresh review passes; addressed independent image budgets, unavailable-vs-empty sitemap distinction, preview routes, bootstrap order, sparse fill, legacy duplicate cursor loops and index reuse. Final scoped reviews found no actionable blockers.
- Hosted sharing monitor passed all existing routes, aliases, data APIs, sitemap index + leaf, sampled images and recipe destinations after broad refinement deployment.
- Production negative probes: bad cursor 400; unsupported width, arbitrary URL query and absent sitemap leaf 404.
- Before manifest reuse, catalog paging enumerated all nine eligible recipes exactly once across two pages; measured first page 4.739s, second 1.749s. This motivated the final manifest-candidate optimization.
- Desktop and 390px mobile screenshots inspected with loaded images: no logo overlay or horizontal overflow; mobile recipe, profile and catalog layouts checked. Local screenshots in `.agent/web-optimization-qa-2026-08-30/` are QA artifacts, not App Store assets.
- Final catalog-only deployment succeeded. Production `/recipes` returned HTTP 200 with all nine eligible recipe links, each exactly once, and no unnecessary next page; response headers arrived in 1.654 seconds versus the earlier 4.739-second first-page sample. This is an individual observation, not a field performance guarantee.
- Final full preflight: **120 passing tests** (75 sanitizer/optimization, 19 hosted-monitor contract, 6 preview, 20 Firestore rules); zero failures. Production CloudKit authorization/lookup and dependency high-severity checks passed.
- Final desktop homepage readback selected the 1280px responsive image for the 704px-wide feature; no horizontal overflow. The 390px collection layout also passed visual inspection with all six photos loaded and no logo overlay. Temporary browser viewport override was reset afterward.

## Remaining external gates and limits

1. Search Console needs the user's Google sign-in, then domain ownership verification and sitemap submission. No claim those were completed.
2. Approve merging this branch into main so the scheduled GitHub monitor uses the current website contracts. Deployment alone does not update scheduled workflow source.
3. Field metrics require enough real Chrome traffic and time; lab scores cannot substitute for it.
4. The manifest's explicit safety guard is 10,000 indexed rows (currently 130). It fails loudly rather than silently truncating and should be sharded before that threshold. Public browsing has a bounded live fallback. No unlimited scan/cost endpoint was introduced.
5. Seven moderate transitive uuid advisory entries remain upstream; the suggested forced fix downgrades Firebase across breaking versions and was not applied. No high/critical production advisories.
6. Current one-creator coverage is unchanged: 52 legacy accounts need one successful updated-app migration/sync to establish their creator-owned username claim. Server indexing cannot manufacture that identity.
