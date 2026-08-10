import { createHash, createSign } from "node:crypto";

const required = [
    "CLOUDKIT_SERVER_KEY_ID",
    "CLOUDKIT_SERVER_PRIVATE_KEY",
    "CLOUDKIT_PREFLIGHT_USER_RECORD",
    "CLOUDKIT_PREFLIGHT_USERNAME_CLAIM_RECORD",
    "CLOUDKIT_PREFLIGHT_SHARED_RECIPE_RECORD",
    "CLOUDKIT_PREFLIGHT_COLLECTION_RECORD",
];
const missing = required.filter((name) => !process.env[name]);
if (missing.length > 0) {
    throw new Error(`Missing production CloudKit preflight environment: ${missing.join(", ")}`);
}

const container = process.env.CLOUDKIT_CONTAINER_ID || "iCloud.Nadav.Cauldron";
const environment = process.env.CLOUDKIT_ENVIRONMENT || "production";
if (container !== "iCloud.Nadav.Cauldron" || environment !== "production") {
    throw new Error("Production preflight must target iCloud.Nadav.Cauldron/production");
}

const expectations = [
    [process.env.CLOUDKIT_PREFLIGHT_USER_RECORD, "User"],
    [process.env.CLOUDKIT_PREFLIGHT_USERNAME_CLAIM_RECORD, "UsernameClaim"],
    [process.env.CLOUDKIT_PREFLIGHT_SHARED_RECIPE_RECORD, "SharedRecipe"],
    [process.env.CLOUDKIT_PREFLIGHT_COLLECTION_RECORD, "Collection"],
];
async function signedRequest(operation, requestBody) {
    const subpath = `/database/1/${container}/${environment}/public/records/${operation}`;
    const body = JSON.stringify(requestBody);
    const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
    const bodyHash = createHash("sha256").update(body, "utf8").digest("base64");
    const signature = createSign("SHA256")
        .update(`${date}:${bodyHash}:${subpath}`)
        .end()
        .sign(process.env.CLOUDKIT_SERVER_PRIVATE_KEY.replace(/\\n/g, "\n"))
        .toString("base64");
    const response = await fetch(`https://api.apple-cloudkit.com${subpath}`, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            "X-Apple-CloudKit-Request-KeyID": process.env.CLOUDKIT_SERVER_KEY_ID,
            "X-Apple-CloudKit-Request-ISO8601Date": date,
            "X-Apple-CloudKit-Request-SignatureV1": signature,
        },
        body,
    });
    if (!response.ok) {
        throw new Error(`CloudKit preflight ${operation} failed with HTTP ${response.status}`);
    }
    return response.json();
}

const payload = await signedRequest("lookup", {
    records: expectations.map(([recordName]) => ({ recordName })),
});
const records = Array.isArray(payload.records) ? payload.records : [];
for (const [recordName, recordType] of expectations) {
    const record = records.find((candidate) => candidate.recordName === recordName);
    if (!record || record.recordType !== recordType || record.serverErrorCode) {
        throw new Error(`CloudKit preflight could not read ${recordType} ${recordName}`);
    }
}

const [userName, claimName, recipeName, collectionName] = expectations.map(([recordName]) => recordName);
const user = records.find((record) => record.recordName === userName);
const claim = records.find((record) => record.recordName === claimName);
const recipe = records.find((record) => record.recordName === recipeName);
const collection = records.find((record) => record.recordName === collectionName);
const userId = user?.fields?.userId?.value;
const username = user?.fields?.username?.value;
const referralCode = user?.fields?.referralCode?.value;
const capabilityHash = user?.fields?.webShareCapabilityHash?.value;
const capabilityGeneration = user?.fields?.webShareCapabilityGeneration?.value;
const creator = user?.created?.userRecordName;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
if (!uuidPattern.test(userId) || typeof username !== "string" || username !== username.toLowerCase() ||
    typeof referralCode !== "string" || !/^[A-Z0-9]{6}$/.test(referralCode) ||
    !/^[0-9a-f]{64}$/i.test(capabilityHash) || !Number.isSafeInteger(capabilityGeneration) || capabilityGeneration < 1 ||
    typeof creator !== "string" || (userName !== creator && userName !== `user_${creator}`)) {
    throw new Error("CloudKit preflight User is missing runtime authorization fields or canonical creator metadata");
}
const claimIdentity = claim?.fields?.identityRecordName?.value;
if (claimName !== `username_${username}` || claim?.created?.userRecordName !== creator ||
    claim?.fields?.userId?.value !== userId || claim?.fields?.username?.value !== username ||
    (claimIdentity !== creator && claimIdentity !== userName) || typeof claim?.created?.timestamp !== "number") {
    throw new Error("CloudKit preflight UsernameClaim is not bound to the canonical QA user");
}
for (const [record, label, ownerField] of [[recipe, "SharedRecipe", "ownerId"], [collection, "Collection", "userId"]]) {
    if (record?.fields?.[ownerField]?.value !== userId || record?.fields?.visibility?.value !== "public" ||
        record?.created?.userRecordName !== creator) {
        throw new Error(`CloudKit preflight ${label} is not a public resource owned by the canonical QA user`);
    }
}

const userQuery = {
    recordType: "User",
    filterBy: [{ fieldName: "userId", comparator: "EQUALS", fieldValue: { value: userId } }],
};
let queryPayload = await signedRequest("query", {
    query: userQuery,
    resultsLimit: 200,
});
const queriedUsers = Array.isArray(queryPayload.records) ? [...queryPayload.records] : [];
let pageCount = 1;
while (typeof queryPayload.continuationMarker === "string") {
    if (pageCount >= 100) {
        throw new Error("CloudKit User.userId preflight query exceeded 100 pages");
    }
    queryPayload = await signedRequest("query", {
        query: userQuery,
        continuationMarker: queryPayload.continuationMarker,
        resultsLimit: 200,
    });
    if (Array.isArray(queryPayload.records)) {
        queriedUsers.push(...queryPayload.records);
    }
    pageCount += 1;
}
const canonicalQueriedUsers = queriedUsers.filter((record) => {
    const recordCreator = record?.created?.userRecordName;
    return record?.recordType === "User" && record?.fields?.userId?.value === userId &&
        typeof recordCreator === "string" &&
        (record.recordName === recordCreator || record.recordName === `user_${recordCreator}`) &&
        typeof record?.created?.timestamp === "number";
}).sort((lhs, rhs) => lhs.created.timestamp - rhs.created.timestamp);
const selectedUser = canonicalQueriedUsers[0];
if (canonicalQueriedUsers.length !== 1 || selectedUser?.recordName !== userName ||
    selectedUser?.fields?.username?.value !== username ||
    selectedUser?.fields?.webShareCapabilityHash?.value !== capabilityHash) {
    throw new Error("CloudKit User.userId query is missing or ambiguously selects the canonical QA authority");
}

const referralPayload = await signedRequest("query", {
    query: {
        recordType: "User",
        filterBy: [{
            fieldName: "referralCode",
            comparator: "EQUALS",
            fieldValue: { value: referralCode },
        }],
    },
    resultsLimit: 2,
});
const referralMatches = (Array.isArray(referralPayload.records) ? referralPayload.records : [])
    .filter((record) => {
        const recordCreator = record?.created?.userRecordName;
        return record?.recordType === "User" &&
            record?.fields?.referralCode?.value === referralCode &&
            uuidPattern.test(record?.fields?.userId?.value) &&
            typeof recordCreator === "string" &&
            (record.recordName === recordCreator || record.recordName === `user_${recordCreator}`);
    });
if (typeof referralPayload.continuationMarker === "string" ||
    referralMatches.length !== 1 || referralMatches[0]?.recordName !== userName ||
    referralMatches[0]?.fields?.userId?.value !== userId) {
    throw new Error("CloudKit User.referralCode query is missing or does not uniquely select the canonical QA user");
}

console.log(`CloudKit ${environment} runtime authorization and invite lookup verified for User, UsernameClaim, SharedRecipe, and Collection.`);
