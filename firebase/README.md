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
collection URLs remain compact title-only recipe shelves. Rich recipe content
is not duplicated in Firebase; every page has a clear path back to the app.
There is no standalone web-sharing preference or unshare control; lifecycle
privacy cleanup remains tied to making an item private, deleting it, or deleting
the account.

The alternate `cauldron-f900a.firebaseapp.com` Hosting domain is reserved in the
app's Associated Domains entitlement and AASA file for a future cross-domain
Universal Link handoff. Do not switch public web buttons from the backward-
compatible custom scheme until an app build containing that entitlement has
shipped broadly.

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
cd functions && npm run test:rules && cd ..
```

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
aliases to the stable user-ID page. Capability-bound privacy epochs prevent an
older in-flight publish from racing a newer privacy removal.

Before releasing the matching app build, verify the deployed associated-domain
file contains both `/u/*` and `/u/*/*`; the checked-in file is not proof that
Firebase Hosting is current:

```sh
curl -fsS https://cauldron-f900a.web.app/.well-known/apple-app-site-association
```
