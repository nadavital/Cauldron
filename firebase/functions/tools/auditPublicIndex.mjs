// Read-only production coverage audit. Prints counts, never identities or credentials.
import { createSign } from "node:crypto";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { GoogleAuth, OAuth2Client } from "google-auth-library";
import { googleCloudCredential, loadProductionCloudKitEnvironment, projectId } from "./productionContext.mjs";

Object.assign(process.env, await loadProductionCloudKitEnvironment());
initializeApp({ projectId });
const credential = googleCloudCredential();
const authClient = new OAuth2Client();
authClient.refreshHandler = async () => {
    const token = await credential.getAccessToken();
    return { access_token: token.access_token, expiry_date: Date.now() + token.expires_in * 1000 };
};
const db = getFirestore();
db.settings({ projectId, auth: new GoogleAuth({ projectId, authClient }) });
const { canonicalCloudKitOwnerRecord, canonicalCloudKitRecipeCreator, cloudKitSignatureInput,
    sanitizeStoredRecipeShareInput } = await import("../lib/index.js");

async function cloudRead(operation, payload) {
    const subpath = `/database/1/iCloud.Nadav.Cauldron/production/public/records/${operation}`;
    const body = JSON.stringify(payload);
    const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
    const signature = createSign("SHA256").update(cloudKitSignatureInput(body, date, subpath)).end()
        .sign(process.env.CLOUDKIT_SERVER_PRIVATE_KEY.replace(/\\n/g, "\n")).toString("base64");
    const response = await fetch(`https://api.apple-cloudkit.com${subpath}`, {
        method: "POST", body, signal: AbortSignal.timeout(15000),
        headers: { "Content-Type": "application/json", "X-Apple-CloudKit-Request-KeyID": process.env.CLOUDKIT_SERVER_KEY_ID,
            "X-Apple-CloudKit-Request-ISO8601Date": date, "X-Apple-CloudKit-Request-SignatureV1": signature },
    });
    if (!response.ok) throw new Error(`CloudKit audit read failed: ${response.status}`);
    const data = await response.json();
    if (data.serverErrorCode) throw new Error("CloudKit audit returned a query error");
    return data;
}

const records = [];
let continuationMarker;
for (let page = 0; page < 10; page++) {
    const result = await cloudRead("query", continuationMarker ? { continuationMarker } : {
        query: { recordType: "User" }, resultsLimit: 100,
    });
    records.push(...(result.records || []));
    continuationMarker = result.continuationMarker;
    if (!continuationMarker) break;
}
const owners = [...new Set(records.map(r => r.fields?.userId?.value).filter(Boolean))];
const counts = { scannedUserRecords: records.length, owners: owners.length, scanComplete: !continuationMarker,
    missingCanonicalIdentity: 0, invalidPublicIdentity: 0, missingOrInvalidUsernameClaim: 0, validClaim: 0 };
for (const owner of owners) {
    const canonical = canonicalCloudKitOwnerRecord(records, owner);
    if (!canonical) { counts.missingCanonicalIdentity++; continue; }
    const creator = canonicalCloudKitRecipeCreator(records, owner);
    if (!creator) { counts.invalidPublicIdentity++; continue; }
    const result = await cloudRead("lookup", { records: [{ recordName: `username_${creator.username}` }] });
    const claim = result.records?.[0];
    if (claim?.recordType === "UsernameClaim" && claim.recordName === `username_${creator.username}` &&
        claim.created?.userRecordName === canonical.created?.userRecordName &&
        claim.fields?.userId?.value === owner && claim.fields?.username?.value === creator.username &&
        typeof claim.created?.timestamp === "number") counts.validClaim++;
    else counts.missingOrInvalidUsernameClaim++;
}
const [recipes, state] = await Promise.all([db.collection("shared_recipes").get(),
    db.collection("share_maintenance").doc("public_profile_backfill").get()]);
const valid = recipes.docs.filter(d => { const result = sanitizeStoredRecipeShareInput(d.data());
    return result.ok && result.value.recipeId === d.id; });
const data = state.data() || {};
console.log(JSON.stringify({ cloudKit: counts, index: { summaries: recipes.size,
    creators: new Set(recipes.docs.map(d => d.data().ownerId)).size, validSummaries: valid.length,
    validSummaryCreators: new Set(valid.map(d => d.data().ownerId)).size },
    backfill: { lastRunAt: data.lastRunAt?.toDate(), materialized: data.lastMaterializedCount,
        pending: data.pendingOwnerIds?.length || 0, failed: data.failedOwnerIds?.length || 0,
        morePages: Boolean(data.continuationMarker) } }, null, 2));
