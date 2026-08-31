# Cauldron sharing backend

Recipe and profile pages use stable IDs so old links continue to work. Mutations
are authorized by a private capability whose hash is registered on the owner's
creator-write-protected public CloudKit `User` record. Firebase verifies that
record before an initial publication or key rotation. Profile usernames are
reserved by creator-protected, deterministic CloudKit `UsernameClaim` records,
which Firebase also verifies before publishing an alias. Raw Firestore reads are
denied; public reads go through the validated API and preview functions.

The browser product is deliberately read-only. `/recipe/<uuid>` validates the
Firebase publication pointer and then hydrates the current public recipe from
CloudKit, including its hero image, ingredients, and method. Signed CloudKit
asset URLs are fetched per request so image links do not go stale. Profile and
collection URLs show compact image-led recipe shelves. Shelf titles, times, tags,
visibility, ownership, and image URLs are validated against current CloudKit
records. Rich recipe content
is not duplicated in Firebase; every page has a clear path back to the app.
There is no standalone web-sharing preference or unshare control; lifecycle
privacy cleanup remains tied to making an item private, deleting it, or deleting
the account.

`cauldronrecipes.com` is the canonical public origin. The legacy
`cauldron-f900a.web.app` and alternate `cauldron-f900a.firebaseapp.com` Hosting
domains remain in the app's Associated Domains entitlement and AASA file so old
links keep working. Do not remove the backward-compatible custom-scheme button
until an app build containing the custom-domain entitlement has shipped broadly.

Human-facing profile URLs are `/u/<username>`. Stable-ID routes remain valid and
redirect to the current username when one is available. Historical username
claims remain reserved while the account exists so old links remain resolvable.

## Read-only homepage preview

Run `npm run preview:live` in `firebase/functions` with an authorized `gcloud`
session. It binds only to `http://127.0.0.1:8766` and uses the same homepage loader
as production: a recent/archive mix, daily rotation, creator/category diversity,
and authoritative CloudKit validation. It neither publishes nor repairs records,
and it never substitutes made-up recipes. Credentials are loaded from the
existing Google Secret Manager secrets into server memory, never browser code.
Only aggregate recipe/creator counts are logged. `google-auth-library` is an
explicit development dependency for the local authenticated read client.

This is a **homepage** preview: recipe, profile, collection, and invite links
redirect to production, so those pages do not preview un-deployed templates.
Use the deployed hosted monitor and browser QA separately for those routes.
The handler tests run as part of `npm test` and cover rejected writes, path
traversal, missing files, bodyless HEAD responses, and sanitized failures.

`tools/withProductionContext.mjs <command> ...` supplies the existing CloudKit
credentials and public monitor fixtures to the production preflight without
writing secrets to disk. `tools/configureWWWRedirect.mjs` reads Firebase's
`www` redirect-domain status; `--apply` configures only that redirect domain.
Complete the DNS records returned by Firebase separately in Vercel. Never
replace the apex Firebase ownership, certificate-validation, or address records.

## Homepage discovery

Each request reads up to 24 recent summaries and 36 summaries from a daily
UUID/document-ID pivot, wrapping at the end of the index. This bounded archive
sample has no age cutoff and includes records without an `updatedAt` field.
Both historical UUID cases are sampled. It is sampling, not a guarantee that
every recipe will appear within a fixed number of days.

The daily UTC key gives deterministic ranking for an unchanged candidate pool.
The selector alternates recent and archive recipes, prefers underrepresented
creators and categories, deduplicates IDs, and relaxes diversity preferences
only when needed to fill a small library. Up to 24 candidates receive CloudKit
validation; selection then runs again on current metadata and usable image URLs
to display up to 12 cards. Six recent/six archive is a target, not a hard quota.
New publications, edits, privacy changes, and availability can change a day's
results; do not cache a daily page past current visibility validation.

The hosted monitor requires a nonempty real-image shelf and checks up to three
displayed images and canonical recipe destinations. Empty discovery or broken
sampled cards fail the job. This is a bounded availability check, not a full
image-decode/browser-layout test. Logs include only counts (candidates, displayed
recipes, creators, archive picks), never signed asset URLs.

To audit snapshots created before the Firebase summary-only contract, run
`npm run scrub:legacy-web-snapshots` from `firebase/functions`. Add
`-- --apply` only after reviewing the dry-run count. Apply mode deletes images,
ingredients, instructions, notes, sources, and creator attribution, then fails
if any affected snapshot remains.

Before deploying, add `webShareCapabilityHash` as a String field and
`webShareCapabilityGeneration` as an Int(64) field on the production CloudKit
`User` schema and confirm both `userId` and `referralCode` remain queryable. The
seeded QA `User` must have a unique six-character uppercase referral code so the
preflight also proves that public invite validation can resolve a live invite. Add a
public `UsernameClaim` record type with String fields `userId`, `username`, and
`identityRecordName`; authenticated users may create records and creators may
write/delete their own records. The deterministic `username_<normalized name>`
record ID supplies atomic uniqueness, so do not grant general authenticated
write access to records created by other users. Add a private-zone
`WebShareCapability` record type with String fields `userId` and `capability`
plus an Int(64) `generation` field;
authenticated users create it and only its creator may read, write, or delete
it. The server-to-server key must be able to read public `User`,
`UsernameClaim`, `SharedRecipe`, and `Collection` records so Firebase can bind
each publication to the CloudKit identity that owns that exact resource. Then
create a P-256 CloudKit server-to-server key, register its public key in
CloudKit Dashboard, and store the generated key ID and private PEM as Firebase
Functions secrets:

```sh
openssl ecparam -name prime256v1 -genkey -noout -out cauldron-cloudkit.pem
openssl ec -in cauldron-cloudkit.pem -pubout
firebase functions:secrets:set CLOUDKIT_SERVER_KEY_ID
firebase functions:secrets:set CLOUDKIT_SERVER_PRIVATE_KEY
```

Seed one non-sensitive public QA record of each required type, export their
record names plus the server credentials, and run the same production preflight
that Firebase invokes before every Functions deploy:

```sh
export CLOUDKIT_SERVER_KEY_ID="..."
export CLOUDKIT_SERVER_PRIVATE_KEY="$(cat cauldron-cloudkit.pem)"
export CLOUDKIT_PREFLIGHT_USER_RECORD="user_..."
export CLOUDKIT_PREFLIGHT_USERNAME_CLAIM_RECORD="username_..."
export CLOUDKIT_PREFLIGHT_SHARED_RECIPE_RECORD="..."
export CLOUDKIT_PREFLIGHT_COLLECTION_RECORD="..."
cd functions && npm run preflight:production && cd ..
```

The preflight runs the backend security/sanitizer suite and signed production
lookups for `User`, `UsernameClaim`, `SharedRecipe`, and `Collection`, plus
signed queries for both `User.userId` and `User.referralCode`. A deploy
fails closed if those environment variables, records, schema permissions, or
credentials are unavailable.

The production dependency gate fails on high or critical advisories. As of
2026-08-10, Firebase Admin 14.2.0 retains seven moderate npm advisories through
Google Cloud Storage's `uuid` 9.0.1 dependency. The advisory affects the
optional output-buffer path in UUID v3/v5/v6; the installed Google clients call
UUID v4 without an output buffer. Keep this exception under review on every
dependency update and remove it when the upstream Google package refreshes the
dependency. Do not force npm's suggested downgrade to Firebase Admin 10.3.0.

Run Firestore rules tests with Java 21 or newer:

```sh
export JAVA_HOME="$(/usr/libexec/java_home -v 21)" # macOS, when multiple JDKs are installed
cd functions && npm run test:rules && cd ..
```

The repository's `.java-version` pins the required major version for compatible
version managers, and `npm test` now checks the active runtime before starting
the emulator. CI reads the same file through `actions/setup-java`, so a local
Java 17 default cannot silently turn the rules suite into an unverified gate.

The suite proves that anonymous and authenticated clients cannot read or write
public snapshots, mutation state, privacy epochs, revocations, or rate-limit
records; only the Admin SDK path bypasses these rules.

Treat this as a bounded security cutoff, not a compatibility window. Firebase
updates functions independently, so first deploy and verify HTTP 426 for all
seven retained legacy mutation names. Only then deploy the authenticated V2 and
read functions, and release the V2-capable app immediately. This intentionally
creates a short interval where old clients cannot publish; it never creates an
interval where V2 is advertised while an unauthenticated Admin SDK writer may
still be live. Existing public links remain readable. The first authorized update
upgrades legacy documents in place. Profile username documents become data-free
aliases to stable user identities; rendered pages use the current `/u/<username>`
URL where available. Capability-bound privacy epochs prevent an
older in-flight publish from racing a newer privacy removal.

Before releasing the matching app build, verify the deployed associated-domain
file contains both `/u/*` and `/u/*/*`; the checked-in file is not proof that
Firebase Hosting is current:

```sh
curl -fsS https://cauldronrecipes.com/.well-known/apple-app-site-association
```

## Production sharing monitor

`.github/workflows/hosted-sharing-monitor.yml` probes production every six
hours. It verifies the Hosting landing page, both application entries and every
supported route in the AASA file, canonical and legacy profile routes, canonical
and direct recipe routes, safe invalid-invite handoffs, and a public collection.
It also validates the profile, recipe, and collection data API contracts through
both the Hosting rewrite and the direct Cloud Functions origin used by the app.
Recipe proof parses JSON-LD and requires nonempty ingredients, instructions,
image, and tags plus exact creator, canonical URL, and app-link identities. The
job uses only public GET requests and requires no production credentials.

The default profile, recipe, and Bakery collection are intentionally public,
non-sensitive monitor fixtures. If any fixture is removed, update the repository variables
`CAULDRON_MONITOR_PROFILE_PATH`, `CAULDRON_MONITOR_LEGACY_PROFILE_PATH`,
`CAULDRON_MONITOR_PROFILE_HANDLE`, `CAULDRON_MONITOR_PROFILE_NAME`,
`CAULDRON_MONITOR_RECIPE_PATH`, and `CAULDRON_MONITOR_CANONICAL_RECIPE_PATH`
or `CAULDRON_MONITOR_COLLECTION_PATH` before removing it so an outage is not
confused with fixture retirement. Collection validation is mandatory; there is
no green skip when the configured fixture is unavailable or empty. Override
`CAULDRON_MONITOR_COLLECTION_TITLE` as well if the fixture is intentionally
renamed.

Run the identical probe locally with:

```sh
cd functions
npm run monitor:hosted
```

This is availability and response-contract proof only. It does not prove a
signed-in app launch, Universal Link dispatch on a device, CloudKit mutation
authorization, TestFlight installation, or a real device accepting an invite.

## Xcode 27 CI image

GitHub currently provides Xcode 27 through the dedicated `xcode-27` preview
runner, not a beta-specific label. `production-readiness.yml` always requires
Xcode and the iPhoneOS SDK major to remain 27. PR and push checks report the
exact build and warn, rather than fail, when GitHub rotates the preview image.
A manually dispatched release verification requires the exact Xcode build in
its workflow input, preserving reproducible release proof without stranding
ordinary CI after an image rotation.
