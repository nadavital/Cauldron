# CloudKit Public Search Backfill

This tool backfills the derived public-search fields on every `SharedRecipe` record in the CloudKit public database:

- `searchableTags`
- `searchableTitleTerms`
- `searchableIngredients`

It uses CloudKit Web Services with a server-to-server key, so it can update all public records without shipping elevated write access in the client app.

## What It Does

1. Queries `SharedRecipe` records from the CloudKit public database where `visibility == public`
2. Decodes `tagsData` and `ingredientsData` from the existing record payload
3. Recomputes the three derived search fields using the same normalization rules as the app
4. Updates only records whose derived fields are missing or stale
5. Saves a checkpoint file so the job can resume safely after interruptions

## Prerequisites

1. Create a CloudKit server-to-server key in CloudKit Dashboard:
   - Container > `API Access` > `Server-to-Server Keys`
   - Create/use the key in the same CloudKit environment you are targeting.
     A key that authenticates in `development` may still fail with
     `AUTHENTICATION_FAILED` in `production` until the public key is added for
     production and the production Key ID is used.
2. Keep the private EC key PEM file on the machine where you run the job
3. Make sure the production schema already contains these fields on `SharedRecipe`:
   - `searchableTags`
   - `searchableTitleTerms`
   - `searchableIngredients`
4. Make sure `visibility` is queryable in the target environment, because the sweep query filters on `visibility == public`

## Schema and Index Setup

The admin backfill updates existing records. It does not create or deploy
CloudKit schema fields by itself.

Before running the production backfill:

1. In the development environment, create/update at least one public recipe from
   the current app build so CloudKit learns the three searchable fields.
2. In CloudKit Dashboard, confirm `SharedRecipe` has these fields as string-list
   fields:
   - `searchableTags`
   - `searchableTitleTerms`
   - `searchableIngredients`
3. Mark the fields as queryable/searchable enough for the app queries:
   - `visibility` is queryable.
   - `ownerId` is queryable.
   - `updatedAt` is sortable.
   - `searchableTags`, `searchableTitleTerms`, and `searchableIngredients`
     support the app's `ANY field == token` predicates.
4. Deploy the development schema changes to production from CloudKit Dashboard.
5. Run the dry run below against production, then the production write.

If the production write returns `ACCESS_DENIED WRITE operation not permitted`,
first retry with the default normal `update` operation. If it still fails, the
server-to-server key can read public records but does not have write permission
for records created by app users. In CloudKit Dashboard, update the
`SharedRecipe` security roles in development, deploy the role change to
production, run the backfill, then restore the narrower role if you do not want
that broader write permission to remain.

You can also inspect schema from the command line with `cktool` once you have a
management token:

```sh
xcrun cktool save-token --type management

xcrun cktool export-schema \
  --team-id YOUR_TEAM_ID \
  --container-id iCloud.Nadav.Cauldron \
  --environment production \
  --output-file /tmp/cauldron-production-schema.json
```

If the schema export does not show the three searchable fields on
`SharedRecipe`, do not run the write backfill yet.

Apple docs:

- [Composing Web Service Requests](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/SettingUpWebServices.html)
- [Fetching Records Using a Query (records/query)](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/QueryingRecords.html)
- [Modifying Records (records/modify)](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/ModifyRecords.html)
- [Data Size Limits](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/PropertyMetrics.html)

## Dry Run

```sh
node tools/cloudkit_public_search_backfill/backfill_public_search_fields.mjs \
  --container iCloud.Nadav.Cauldron \
  --environment production \
  --key-id YOUR_KEY_ID \
  --private-key-path /secure/path/eckey.pem \
  --dry-run
```

## Production Run

```sh
node tools/cloudkit_public_search_backfill/backfill_public_search_fields.mjs \
  --container iCloud.Nadav.Cauldron \
  --environment production \
  --key-id YOUR_KEY_ID \
  --private-key-path /secure/path/eckey.pem
```

## Recommended Run Order

```sh
# 1. Verify the derivation logic locally.
node --test tools/cloudkit_public_search_backfill/backfill_public_search_fields.test.mjs

# 2. Verify the production server-to-server key before touching records.
node tools/cloudkit_public_search_backfill/backfill_public_search_fields.mjs \
  --container iCloud.Nadav.Cauldron \
  --environment production \
  --key-id YOUR_PRODUCTION_KEY_ID \
  --private-key-path /secure/path/eckey.pem \
  --checkpoint-file /tmp/cauldron-public-search-backfill-production.json \
  --auth-probe \
  --auth-debug

# 3. Dry-run a small production sample.
node tools/cloudkit_public_search_backfill/backfill_public_search_fields.mjs \
  --container iCloud.Nadav.Cauldron \
  --environment production \
  --key-id YOUR_PRODUCTION_KEY_ID \
  --private-key-path /secure/path/eckey.pem \
  --checkpoint-file /tmp/cauldron-public-search-backfill-production.json \
  --dry-run \
  --reset-checkpoint \
  --max-pages 1 \
  --verbose

# 4. Write one production page after the dry-run output looks correct.
node tools/cloudkit_public_search_backfill/backfill_public_search_fields.mjs \
  --container iCloud.Nadav.Cauldron \
  --environment production \
  --key-id YOUR_PRODUCTION_KEY_ID \
  --private-key-path /secure/path/eckey.pem \
  --checkpoint-file /tmp/cauldron-public-search-backfill-production.json \
  --reset-checkpoint \
  --max-pages 1 \
  --verbose

# 5. Resume the same checkpoint for the full production migration.
node tools/cloudkit_public_search_backfill/backfill_public_search_fields.mjs \
  --container iCloud.Nadav.Cauldron \
  --environment production \
  --key-id YOUR_PRODUCTION_KEY_ID \
  --private-key-path /secure/path/eckey.pem \
  --checkpoint-file /tmp/cauldron-public-search-backfill-production.json
```

## Helpful Flags

- `--checkpoint-file <path>`: store progress somewhere explicit
- `--reset-checkpoint`: ignore any saved continuation marker and restart
- `--max-pages <n>`: stop after `n` pages for testing
- `--max-records <n>`: stop after scanning `n` records for testing
- `--modify-batch-size <1-200>`: tune write batch size
- `--force-update`: use CloudKit `forceUpdate`; the default is normal `update` with `recordChangeTag`
- `--auth-probe`: make a signed `users/current` request and exit without querying or modifying records
- `--auth-debug`: print non-secret signing diagnostics for key/environment mismatches
- `--verbose`: print per-record updates

## Resume After Interruption

The script writes a checkpoint JSON file after every page. Re-run the same command with the same checkpoint file to continue from the saved `continuationMarker`.

## Safety Notes

- Start with `--dry-run` in `development`
- Then test `--max-pages 1` in `production`
- Run the full production job only after validating a small sample
- Keep the private key outside the repo
