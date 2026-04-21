# CloudKit Public Search Backfill

This tool backfills the derived public-search fields on every `sharedRecipe` record in the CloudKit public database:

- `searchableTags`
- `searchableTitleTerms`
- `searchableIngredients`

It uses CloudKit Web Services with a server-to-server key, so it can update all public records without shipping elevated write access in the client app.

## What It Does

1. Queries `sharedRecipe` records from the CloudKit public database where `visibility == publicRecipe`
2. Decodes `tagsData` and `ingredientsData` from the existing record payload
3. Recomputes the three derived search fields using the same normalization rules as the app
4. Updates only records whose derived fields are missing or stale
5. Saves a checkpoint file so the job can resume safely after interruptions

## Prerequisites

1. Create a CloudKit server-to-server key in CloudKit Dashboard:
   - Container > `API Access` > `Server-to-Server Keys`
2. Keep the private EC key PEM file on the machine where you run the job
3. Make sure the production schema already contains:
   - `searchableTags`
   - `searchableTitleTerms`
   - `searchableIngredients`
4. Make sure `visibility` is queryable in the target environment, because the sweep query filters on `visibility == publicRecipe`

Apple docs:

- [Composing Web Service Requests](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/SettingUpWebServices.html)
- [Fetching Records Using a Query (records/query)](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/QueryingRecords.html)
- [Modifying Records (records/modify)](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/ModifyRecords.html)
- [Data Size Limits](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/PropertyMetrics.html)

## Dry Run

```sh
node tools/cloudkit_public_search_backfill/backfill_public_search_fields.mjs \
  --container iCloud.com.example.Cauldron \
  --environment production \
  --key-id YOUR_KEY_ID \
  --private-key-path /secure/path/eckey.pem \
  --dry-run
```

## Production Run

```sh
node tools/cloudkit_public_search_backfill/backfill_public_search_fields.mjs \
  --container iCloud.com.example.Cauldron \
  --environment production \
  --key-id YOUR_KEY_ID \
  --private-key-path /secure/path/eckey.pem
```

## Helpful Flags

- `--checkpoint-file <path>`: store progress somewhere explicit
- `--reset-checkpoint`: ignore any saved continuation marker and restart
- `--max-pages <n>`: stop after `n` pages for testing
- `--max-records <n>`: stop after scanning `n` records for testing
- `--modify-batch-size <1-200>`: tune write batch size
- `--verbose`: print per-record updates

## Resume After Interruption

The script writes a checkpoint JSON file after every page. Re-run the same command with the same checkpoint file to continue from the saved `continuationMarker`.

## Safety Notes

- Start with `--dry-run` in `development`
- Then test `--max-pages 1` in `production`
- Run the full production job only after validating a small sample
- Keep the private key outside the repo
