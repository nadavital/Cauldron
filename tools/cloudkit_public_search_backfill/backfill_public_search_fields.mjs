#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import {
  areStringArraysEqual,
  deriveSearchFieldsFromRecord,
  getStringListFieldValue,
} from "./shared_recipe_search_terms.mjs";

const DEFAULT_RESULTS_LIMIT = 200;
const DEFAULT_MODIFY_BATCH_SIZE = 100;
const DEFAULT_RECORD_TYPE = "SharedRecipe";
const PUBLIC_RECIPE_VISIBILITY = "public";
const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_CHECKPOINT_FILE = path.join(
  SCRIPT_DIR,
  "backfill-checkpoint.json",
);

function parseArgs(argv) {
  const options = {
    environment: process.env.CLOUDKIT_ENVIRONMENT ?? "development",
    container: process.env.CLOUDKIT_CONTAINER_ID,
    keyId: process.env.CLOUDKIT_KEY_ID,
    privateKeyPath: process.env.CLOUDKIT_PRIVATE_KEY_PATH,
    privateKeyPem: process.env.CLOUDKIT_PRIVATE_KEY_PEM,
    privateKeyBase64: process.env.CLOUDKIT_PRIVATE_KEY_BASE64,
    apiBase: process.env.CLOUDKIT_API_BASE ?? "https://api.apple-cloudkit.com",
    recordType: process.env.CLOUDKIT_RECORD_TYPE ?? DEFAULT_RECORD_TYPE,
    resultsLimit: Number(process.env.CLOUDKIT_RESULTS_LIMIT ?? DEFAULT_RESULTS_LIMIT),
    modifyBatchSize: Number(process.env.CLOUDKIT_MODIFY_BATCH_SIZE ?? DEFAULT_MODIFY_BATCH_SIZE),
    checkpointFile: process.env.CLOUDKIT_CHECKPOINT_FILE ?? DEFAULT_CHECKPOINT_FILE,
    dryRun: process.env.CLOUDKIT_DRY_RUN === "1",
    resetCheckpoint: false,
    forceUpdate: process.env.CLOUDKIT_FORCE_UPDATE === "1",
    maxPages: null,
    maxRecords: null,
    authProbe: process.env.CLOUDKIT_AUTH_PROBE === "1",
    authDebug: process.env.CLOUDKIT_AUTH_DEBUG === "1",
    verbose: process.env.CLOUDKIT_VERBOSE === "1",
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = argv[index + 1];

    switch (arg) {
      case "--container":
        options.container = next;
        index += 1;
        break;
      case "--environment":
        options.environment = next;
        index += 1;
        break;
      case "--key-id":
        options.keyId = next;
        index += 1;
        break;
      case "--private-key-path":
        options.privateKeyPath = next;
        index += 1;
        break;
      case "--private-key-pem":
        options.privateKeyPem = next;
        index += 1;
        break;
      case "--private-key-base64":
        options.privateKeyBase64 = next;
        index += 1;
        break;
      case "--api-base":
        options.apiBase = next;
        index += 1;
        break;
      case "--record-type":
        options.recordType = next;
        index += 1;
        break;
      case "--results-limit":
        options.resultsLimit = Number(next);
        index += 1;
        break;
      case "--modify-batch-size":
        options.modifyBatchSize = Number(next);
        index += 1;
        break;
      case "--checkpoint-file":
        options.checkpointFile = next;
        index += 1;
        break;
      case "--max-pages":
        options.maxPages = Number(next);
        index += 1;
        break;
      case "--max-records":
        options.maxRecords = Number(next);
        index += 1;
        break;
      case "--dry-run":
        options.dryRun = true;
        break;
      case "--auth-debug":
        options.authDebug = true;
        break;
      case "--auth-probe":
        options.authProbe = true;
        break;
      case "--reset-checkpoint":
        options.resetCheckpoint = true;
        break;
      case "--no-force-update":
        options.forceUpdate = false;
        break;
      case "--force-update":
        options.forceUpdate = true;
        break;
      case "--verbose":
        options.verbose = true;
        break;
      case "--help":
        printHelp();
        process.exit(0);
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  validateOptions(options);
  return options;
}

function validateOptions(options) {
  if (!options.container) {
    throw new Error("Missing CloudKit container. Pass --container or set CLOUDKIT_CONTAINER_ID.");
  }

  if (!options.keyId) {
    throw new Error("Missing CloudKit key ID. Pass --key-id or set CLOUDKIT_KEY_ID.");
  }

  if (!["development", "production"].includes(options.environment)) {
    throw new Error(`Invalid CloudKit environment: ${options.environment}`);
  }

  if (!Number.isInteger(options.resultsLimit) || options.resultsLimit <= 0 || options.resultsLimit > 200) {
    throw new Error("results-limit must be an integer between 1 and 200.");
  }

  if (!Number.isInteger(options.modifyBatchSize) || options.modifyBatchSize <= 0 || options.modifyBatchSize > 200) {
    throw new Error("modify-batch-size must be an integer between 1 and 200.");
  }
}

function printHelp() {
  console.log(`CloudKit public-search backfill

Usage:
  node tools/cloudkit_public_search_backfill/backfill_public_search_fields.mjs [options]

Required:
  --container <iCloud.container.id>
  --key-id <cloudkit server-to-server key id>
  --private-key-path <path to EC private key pem>

Optional:
  --environment <development|production>   Default: development
  --record-type <record type>              Default: SharedRecipe
  --results-limit <1-200>                  Default: 200
  --modify-batch-size <1-200>              Default: 100
  --checkpoint-file <path>                 Default: tools/cloudkit_public_search_backfill/backfill-checkpoint.json
  --max-pages <n>                          Stop after n pages
  --max-records <n>                        Stop after scanning n records
  --dry-run                                Compute changes without writing
  --auth-probe                             Check server-to-server auth with users/current and exit
  --auth-debug                             Print non-secret signing diagnostics
  --reset-checkpoint                       Ignore any saved continuation marker
  --force-update                           Force update without a record change tag
  --no-force-update                        Use normal update; accepted for older commands
  --verbose                                Log per-page details

Environment variables:
  CLOUDKIT_CONTAINER_ID
  CLOUDKIT_ENVIRONMENT
  CLOUDKIT_KEY_ID
  CLOUDKIT_PRIVATE_KEY_PATH
  CLOUDKIT_PRIVATE_KEY_PEM
  CLOUDKIT_PRIVATE_KEY_BASE64
  CLOUDKIT_RESULTS_LIMIT
  CLOUDKIT_MODIFY_BATCH_SIZE
  CLOUDKIT_CHECKPOINT_FILE
  CLOUDKIT_DRY_RUN=1
  CLOUDKIT_AUTH_PROBE=1
  CLOUDKIT_AUTH_DEBUG=1
  CLOUDKIT_FORCE_UPDATE=1
  CLOUDKIT_VERBOSE=1
`);
}

function loadPrivateKey(options) {
  if (options.privateKeyPem) {
    return crypto.createPrivateKey(options.privateKeyPem);
  }

  if (options.privateKeyBase64) {
    return crypto.createPrivateKey(Buffer.from(options.privateKeyBase64, "base64").toString("utf8"));
  }

  if (!options.privateKeyPath) {
    throw new Error(
      "Missing private key. Pass --private-key-path or set CLOUDKIT_PRIVATE_KEY_PATH / CLOUDKIT_PRIVATE_KEY_PEM / CLOUDKIT_PRIVATE_KEY_BASE64.",
    );
  }

  return crypto.createPrivateKey(fs.readFileSync(options.privateKeyPath, "utf8"));
}

function buildSubpath(options, endpoint) {
  return `/database/1/${options.container}/${options.environment}/public/${endpoint}`;
}

function buildSignedHeaders({ body, hasBody, keyId, privateKey, subpath }) {
  const isoDate = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const bodyHash = crypto.createHash("sha256").update(body).digest("base64");
  const message = `${isoDate}:${bodyHash}:${subpath}`;
  const signer = crypto.createSign("SHA256");
  signer.update(message, "utf8");
  signer.end();
  const signature = signer.sign(privateKey).toString("base64");

  return {
    ...(hasBody ? { "Content-Type": "application/json" } : {}),
    "X-Apple-CloudKit-Request-KeyID": keyId,
    "X-Apple-CloudKit-Request-ISO8601Date": isoDate,
    "X-Apple-CloudKit-Request-SignatureV1": signature,
  };
}

function getPublicKeyBody(privateKey) {
  return crypto
    .createPublicKey(privateKey)
    .export({ type: "spki", format: "pem" })
    .toString("utf8")
    .split(/\r?\n/)
    .filter((line) => line && !line.includes("BEGIN PUBLIC KEY") && !line.includes("END PUBLIC KEY"))
    .join("");
}

function printAuthDebug(options, privateKey, endpoint, payload) {
  const subpath = buildSubpath(options, endpoint);
  const body = payload == null ? "" : JSON.stringify(payload);
  const bodyHash = crypto.createHash("sha256").update(body).digest("base64");
  const publicKeyBody = getPublicKeyBody(privateKey);
  const publicKeyFingerprint = crypto.createHash("sha256").update(publicKeyBody).digest("hex");

  console.log("CloudKit auth debug:");
  console.log(`  container: ${options.container}`);
  console.log(`  environment: ${options.environment}`);
  console.log(`  endpoint subpath: ${subpath}`);
  console.log(`  key id: ${options.keyId}`);
  console.log(`  request body sha256/base64: ${bodyHash}`);
  console.log(`  public key body length: ${publicKeyBody.length}`);
  console.log(`  public key body prefix/suffix: ${publicKeyBody.slice(0, 12)}...${publicKeyBody.slice(-12)}`);
  console.log(`  public key body sha256: ${publicKeyFingerprint}`);
}

async function cloudKitRequest(options, privateKey, endpoint, payload, method = "POST") {
  const subpath = buildSubpath(options, endpoint);
  const url = new URL(subpath, options.apiBase);
  const hasBody = payload != null;
  const body = hasBody ? JSON.stringify(payload) : "";
  const headers = buildSignedHeaders({
    body,
    hasBody,
    keyId: options.keyId,
    privateKey,
    subpath,
  });

  const response = await fetch(url, {
    method,
    headers,
    ...(hasBody ? { body } : {}),
  });

  const responseText = await response.text();
  const data = responseText ? JSON.parse(responseText) : {};

  if (!response.ok) {
    const retryAfter = Number(response.headers.get("Retry-After") ?? data?.retryAfter ?? 0);
    const error = new Error(
      `CloudKit request failed (${response.status}) for ${endpoint}: ${data?.serverErrorCode ?? "UNKNOWN"} ${data?.reason ?? ""}`.trim(),
    );
    error.retryAfter = Number.isFinite(retryAfter) ? retryAfter : 0;
    error.response = data;
    throw error;
  }

  return data;
}

async function requestWithRetry(options, privateKey, endpoint, payload, method = "POST", attempt = 0) {
  try {
    return await cloudKitRequest(options, privateKey, endpoint, payload, method);
  } catch (error) {
    const retryableCodes = new Set([
      "REQUEST_RATE_LIMITED",
      "ZONE_BUSY",
      "SERVICE_UNAVAILABLE",
      "INTERNAL_ERROR",
    ]);
    const serverErrorCode = error?.response?.serverErrorCode;
    const shouldRetry = attempt < 5 && retryableCodes.has(serverErrorCode);

    if (!shouldRetry) {
      throw error;
    }

    const waitSeconds = error.retryAfter > 0 ? error.retryAfter : 2 ** (attempt + 1);
    console.warn(`Retrying ${endpoint} after ${waitSeconds}s due to ${serverErrorCode}...`);
    await sleep(waitSeconds * 1000);
    return requestWithRetry(options, privateKey, endpoint, payload, method, attempt + 1);
  }
}

function buildQueryPayload(options, continuationMarker) {
  const payload = {
    query: {
      recordType: options.recordType,
      filterBy: [
        {
          fieldName: "visibility",
          comparator: "EQUALS",
          fieldValue: {
            value: PUBLIC_RECIPE_VISIBILITY,
            type: "STRING",
          },
        },
      ],
    },
    desiredKeys: [
      "title",
      "tagsData",
      "ingredientsData",
      "searchableTags",
      "searchableTitleTerms",
      "searchableIngredients",
    ],
    resultsLimit: options.resultsLimit,
  };

  if (continuationMarker) {
    payload.continuationMarker = continuationMarker;
  }

  return payload;
}

function getChangedFieldPatch(record) {
  const derived = deriveSearchFieldsFromRecord(record);
  const existingFields = record.fields ?? {};

  const changedFields = {};
  const changedFieldNames = [];

  for (const [fieldName, nextValues] of Object.entries(derived)) {
    const currentValues = getStringListFieldValue(existingFields[fieldName]);
    if (!areStringArraysEqual(currentValues, nextValues)) {
      changedFields[fieldName] = { value: nextValues };
      changedFieldNames.push(fieldName);
    }
  }

  return {
    changedFields,
    changedFieldNames,
    derived,
    changed: changedFieldNames.length > 0,
  };
}

function buildModifyPayload(options, patches) {
  const operationType = options.forceUpdate ? "forceUpdate" : "update";

  return {
    operations: patches.map(({ record, changedFields }) => ({
      operationType,
      record: {
        recordName: record.recordName,
        ...(options.forceUpdate ? { recordType: record.recordType ?? options.recordType } : { recordChangeTag: record.recordChangeTag }),
        fields: changedFields,
      },
    })),
  };
}

function loadCheckpoint(checkpointFile, resetCheckpoint) {
  if (resetCheckpoint || !fs.existsSync(checkpointFile)) {
    return {
      continuationMarker: null,
      pageCount: 0,
      scanned: 0,
      updated: 0,
      skipped: 0,
      completed: false,
    };
  }

  return JSON.parse(fs.readFileSync(checkpointFile, "utf8"));
}

function saveCheckpoint(checkpointFile, checkpoint) {
  fs.mkdirSync(path.dirname(checkpointFile), { recursive: true });
  fs.writeFileSync(checkpointFile, `${JSON.stringify(checkpoint, null, 2)}\n`, "utf8");
}

function summarizePatch(patch) {
  return patch.changedFieldNames.map((fieldName) => {
    const values = patch.derived[fieldName];
    return `${fieldName}=[${values.join(", ")}]`;
  }).join(" ");
}

async function sleep(milliseconds) {
  await new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const privateKey = loadPrivateKey(options);
  const checkpoint = loadCheckpoint(options.checkpointFile, options.resetCheckpoint);

  console.log(
    `${options.dryRun ? "Starting dry-run" : "Starting"} CloudKit public search backfill for ${options.container} (${options.environment})`,
  );
  console.log(`Checkpoint file: ${options.checkpointFile}`);

  if (options.authProbe) {
    if (options.authDebug) {
      printAuthDebug(options, privateKey, "users/current", null);
    }

    const probeResponse = await requestWithRetry(options, privateKey, "users/current", null, "GET");
    console.log("CloudKit server-to-server auth probe succeeded.");
    if (options.verbose) {
      console.log(JSON.stringify(probeResponse, null, 2));
    }
    return;
  }

  while (true) {
    if (options.maxPages && checkpoint.pageCount >= options.maxPages) {
      console.log(`Stopping after max-pages=${options.maxPages}`);
      break;
    }

    if (options.maxRecords && checkpoint.scanned >= options.maxRecords) {
      console.log(`Stopping after max-records=${options.maxRecords}`);
      break;
    }

    const queryPayload = buildQueryPayload(options, checkpoint.continuationMarker);
    if (options.authDebug && checkpoint.pageCount === 0) {
      printAuthDebug(options, privateKey, "records/query", queryPayload);
    }
    const queryResponse = await requestWithRetry(options, privateKey, "records/query", queryPayload);
    const records = Array.isArray(queryResponse.records) ? queryResponse.records : [];

    checkpoint.pageCount += 1;
    checkpoint.continuationMarker = queryResponse.continuationMarker ?? null;

    const patches = [];
    for (const record of records) {
      checkpoint.scanned += 1;
      const patch = getChangedFieldPatch(record);

      if (patch.changed) {
        patches.push({ record, ...patch });
        if (options.verbose) {
          console.log(`Needs update ${record.recordName}: ${summarizePatch(patch)}`);
        }
      } else {
        checkpoint.skipped += 1;
      }

      if (options.maxRecords && checkpoint.scanned >= options.maxRecords) {
        break;
      }
    }

    if (options.dryRun) {
      checkpoint.updated += patches.length;
      if (patches.length > 0 && !options.verbose) {
        console.log(`Page ${checkpoint.pageCount}: ${patches.length} record(s) would be updated.`);
      }
    } else {
      for (let start = 0; start < patches.length; start += options.modifyBatchSize) {
        const batch = patches.slice(start, start + options.modifyBatchSize);
        const modifyPayload = buildModifyPayload(options, batch);
        const modifyResponse = await requestWithRetry(options, privateKey, "records/modify", modifyPayload);
        const modifyResults = Array.isArray(modifyResponse.records) ? modifyResponse.records : [];

        for (const result of modifyResults) {
          if (result.serverErrorCode) {
            throw new Error(
              `Modify failed for ${result.recordName ?? "unknown record"}: ${result.serverErrorCode} ${result.reason ?? ""}`.trim(),
            );
          }
        }

        checkpoint.updated += batch.length;
        console.log(`Page ${checkpoint.pageCount}: updated ${batch.length} record(s).`);
      }
    }

    checkpoint.completed = checkpoint.continuationMarker == null;
    saveCheckpoint(options.checkpointFile, checkpoint);

    console.log(
      `Progress: pages=${checkpoint.pageCount} scanned=${checkpoint.scanned} updated=${checkpoint.updated} skipped=${checkpoint.skipped} remaining=${checkpoint.continuationMarker ? "yes" : "no"}`,
    );

    if (!checkpoint.continuationMarker) {
      break;
    }
  }

  if (checkpoint.completed) {
    console.log(`Backfill completed. Final checkpoint saved to ${options.checkpointFile}`);
  } else {
    console.log(`Backfill paused. Resume with the same checkpoint file: ${options.checkpointFile}`);
  }
}

main().catch((error) => {
  console.error(error.stack || String(error));
  process.exitCode = 1;
});
