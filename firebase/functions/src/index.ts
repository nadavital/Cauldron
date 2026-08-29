import { onRequest, Request } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { initializeApp } from "firebase-admin/app";
import {
    DocumentReference,
    DocumentSnapshot,
    FieldValue,
    getFirestore,
    Query,
    QueryDocumentSnapshot,
    Timestamp,
} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { createHash, createSign, timingSafeEqual } from "node:crypto";

initializeApp();
const db = getFirestore();
const cloudKitServerKeyID = defineSecret("CLOUDKIT_SERVER_KEY_ID");
const cloudKitServerPrivateKey = defineSecret("CLOUDKIT_SERVER_PRIVATE_KEY");
const CLOUDKIT_CONTAINER = "iCloud.Nadav.Cauldron";

// --- Utilities ---

const MAX_TITLE_LENGTH = 160;
const MAX_DISPLAY_NAME_LENGTH = 80;
const MAX_TAG_COUNT = 20;
const MAX_TAG_LENGTH = 48;
const MAX_RECIPE_IDS_PER_COLLECTION = 200;
const MAX_WEB_INGREDIENTS = 250;
const MAX_WEB_STEPS = 200;
const MAX_WEB_RECIPE_TEXT_LENGTH = 4_000;
const MAX_WEB_RECIPE_CARDS = 12;
const WEB_RECIPE_CARD_QUERY_LIMIT = MAX_WEB_RECIPE_CARDS + 1;
const CLOUDKIT_WEB_REQUEST_TIMEOUT_MS = 4_000;
const CLOUDKIT_WEB_MAX_ATTEMPTS = 2;
const CLOUDKIT_WEB_RETRY_DELAY_MS = 150;
const SOCIAL_IMAGE_MAX_BYTES = 10_000_000;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const usernamePattern = /^[A-Za-z0-9_]{3,20}$/;
const capabilityPattern = /^[A-Za-z0-9_-]{43,128}$/;

export function publicSecurityHeaders(): Readonly<Record<string, string>> {
    return {
        "Content-Security-Policy": [
            "default-src 'none'",
            "base-uri 'none'",
            "object-src 'none'",
            "frame-ancestors 'none'",
            "form-action 'none'",
            "img-src 'self' https: data:",
            "font-src 'self' data:",
            "style-src 'self' 'unsafe-inline'",
            "script-src 'self' 'unsafe-inline'",
            "connect-src 'none'",
            "upgrade-insecure-requests",
        ].join("; "),
        "Cross-Origin-Opener-Policy": "same-origin",
        "Permissions-Policy": "camera=(), microphone=(), geolocation=(), payment=(), usb=()",
        "Referrer-Policy": "no-referrer",
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
    };
}

type ValidationResult<T> =
    | { ok: true; value: T }
    | { ok: false; error: string };

type SanitizedRecipeShare = {
    recipeId: string;
    ownerId: string;
    identityRecordName: string;
    title: string;
    totalMinutes: number | null;
    tags: string[];
    capability: string;
    shouldCreate: boolean;
};

type WebRecipeIndexItem = SanitizedRecipeShare & {
    imageURL?: string | null;
};

type WebRecipeQuantity = {
    value: number;
    upperValue: number | null;
    unit: string;
};

type WebRecipeIngredient = {
    name: string;
    quantity: WebRecipeQuantity | null;
    additionalQuantities: WebRecipeQuantity[];
    note: string | null;
    section: string | null;
};

type WebRecipeStep = {
    index: number;
    text: string;
    section: string | null;
};

export type WebRecipeContent = {
    recipeId: string;
    ownerId: string;
    title: string;
    yields: string | null;
    totalMinutes: number | null;
    tags: string[];
    ingredients: WebRecipeIngredient[];
    steps: WebRecipeStep[];
    imageURL: string | null;
};

export type WebRecipeCreator = {
    username: string;
    displayName: string;
    profileEmoji: string | null;
    profileColor: string | null;
};

type SanitizedProfileShare = {
    userId: string;
    identityRecordName: string;
    username: string;
    displayName: string;
    profileEmoji: string | null;
    profileColor: string | null;
    recipeCount: number | null;
    capability: string;
    shouldCreate: boolean;
};

type SanitizedProfileUnshare = {
    userId: string;
    identityRecordName: string;
    username: string;
    capability: string;
};

type SanitizedRecipeUnshare = {
    recipeId: string;
    ownerId: string;
    identityRecordName: string;
    capability: string;
};

type SanitizedAccountUnshare = {
    userId: string;
    identityRecordName: string;
    capability: string;
};

type SanitizedCollectionShare = {
    collectionId: string;
    ownerId: string;
    identityRecordName: string;
    title: string;
    recipeCount: number;
    recipeIds: string[];
    capability: string;
    shouldCreate: boolean;
};

type SanitizedCollectionUnshare = {
    collectionId: string;
    ownerId: string;
    identityRecordName: string;
    capability: string;
};

export function publishedShareResponse(shareId: string, shareUrl: string, published: boolean) {
    return { shareId, shareUrl, published };
}

export function escapeHtml(value: unknown): string {
    return String(value ?? "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}

export function safeImageURL(rawURL: unknown): string | null {
    if (typeof rawURL !== "string") {
        return null;
    }

    try {
        const parsed = new URL(rawURL);
        if (parsed.protocol !== "https:" || parsed.username || parsed.password) {
            return null;
        }
        // Never republish imported or signed third-party image URLs. Public web
        // snapshots may only reference assets hosted on Cauldron's own origin.
        if (parsed.hostname !== "cauldron-f900a.web.app") {
            return null;
        }
        parsed.search = "";
        parsed.hash = "";
        return parsed.toString();
    } catch {
        return null;
    }
}

function safeWebURL(rawURL: unknown): string | null {
    if (typeof rawURL !== "string") {
        return null;
    }

    try {
        const parsed = new URL(rawURL);
        if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
            return null;
        }
        parsed.username = "";
        parsed.password = "";
        // Source links are attribution, not request replay. Query strings are
        // an open-ended credential surface (signed CDN URLs, session tokens,
        // vendor keys), so a denylist cannot make them safe to republish.
        parsed.search = "";
        parsed.hash = "";
        return parsed.toString();
    } catch {
        return null;
    }
}

function sanitizedCapability(value: unknown): string | null {
    return typeof value === "string" && capabilityPattern.test(value) ? value : null;
}

function capabilityHash(capability: string): string {
    return createHash("sha256").update(capability, "utf8").digest("hex");
}

const recordNamePattern = /^[A-Za-z0-9_.:-]{1,255}$/;

function sanitizedRecordName(value: unknown): string | null {
    return typeof value === "string" && recordNamePattern.test(value) ? value : null;
}

function capabilityHashesMatch(storedHash: unknown, suppliedHash: string): boolean {
    if (typeof storedHash !== "string" || !/^[0-9a-f]{64}$/i.test(storedHash)) {
        return false;
    }

    return timingSafeEqual(Buffer.from(storedHash, "hex"), Buffer.from(suppliedHash, "hex"));
}

type CloudKitRecordLike = {
    recordName?: unknown;
    recordType?: unknown;
    serverErrorCode?: unknown;
    retryAfter?: unknown;
    created?: { timestamp?: unknown; userRecordName?: unknown };
    fields?: Record<string, { value?: unknown }>;
};

type CloudKitRecordsPayload = {
    records?: CloudKitRecordLike[];
    serverErrorCode?: unknown;
    retryAfter?: unknown;
};

const missingCloudKitRecordCodes = new Set(["UNKNOWN_ITEM", "NOT_FOUND"]);
const transientCloudKitRecordCodes = new Set([
    "INTERNAL_ERROR",
    "REQUEST_RATE_LIMITED",
    "SERVICE_UNAVAILABLE",
    "THROTTLED",
    "TRY_AGAIN_LATER",
    "ZONE_BUSY",
]);

function cloudKitPayloadErrorCodes(payload: CloudKitRecordsPayload): string[] {
    const topLevelCode = typeof payload.serverErrorCode === "string"
        ? [payload.serverErrorCode.toUpperCase()]
        : [];
    const recordCodes = (payload.records ?? []).flatMap((record) =>
        typeof record.serverErrorCode === "string"
            ? [record.serverErrorCode.toUpperCase()]
            : []
    );
    return [...topLevelCode, ...recordCodes];
}

export function cloudKitRecordsPayloadIsRetryableError(payload: CloudKitRecordsPayload): boolean {
    const hasRetryAfter = typeof payload.retryAfter === "number" && payload.retryAfter >= 0 ||
        (payload.records ?? []).some((record) =>
            typeof record.retryAfter === "number" && record.retryAfter >= 0
        );
    const codes = cloudKitPayloadErrorCodes(payload)
        .filter((code) => !missingCloudKitRecordCodes.has(code));
    return hasRetryAfter ||
        (codes.length > 0 && codes.every((code) => transientCloudKitRecordCodes.has(code)));
}

class RetryableCloudKitError extends Error {}

function isTransientCloudKitNetworkError(error: unknown): boolean {
    if (!(error instanceof Error)) {
        return false;
    }
    if (error.name === "TimeoutError" || error.name === "AbortError" ||
        error.message === "fetch failed" || error.message === "terminated") {
        return true;
    }
    const cause = (error as Error & { cause?: unknown }).cause;
    if (!cause || typeof cause !== "object") {
        return false;
    }
    const code = (cause as { code?: unknown }).code;
    return code === "ECONNRESET" || code === "ECONNREFUSED" ||
        code === "EPIPE" || code === "ETIMEDOUT" || code === "ENETUNREACH" ||
        code === "UND_ERR_SOCKET" || code === "UND_ERR_CONNECT_TIMEOUT" ||
        code === "UND_ERR_HEADERS_TIMEOUT" || code === "UND_ERR_BODY_TIMEOUT" ||
        code === "UND_ERR_RES_CONTENT_LENGTH_MISMATCH";
}

export async function retryTransientCloudKitOperation<T>(
    operation: (attempt: number) => Promise<T>,
    maxAttempts = CLOUDKIT_WEB_MAX_ATTEMPTS,
    retryDelayMs = CLOUDKIT_WEB_RETRY_DELAY_MS
): Promise<T> {
    const attempts = Math.max(1, Math.trunc(maxAttempts));
    for (let attempt = 1; attempt <= attempts; attempt += 1) {
        try {
            return await operation(attempt);
        } catch (error) {
            const shouldRetry = error instanceof RetryableCloudKitError ||
                isTransientCloudKitNetworkError(error);
            if (!shouldRetry || attempt === attempts) {
                throw error;
            }
            if (retryDelayMs > 0) {
                await new Promise((resolve) => setTimeout(resolve, retryDelayMs));
            }
        }
    }
    throw new Error("CloudKit retry loop completed without a result");
}

export function isTransientCloudKitHTTPStatus(status: number): boolean {
    return status === 408 || status === 425 || status === 429 ||
        status === 500 || status === 502 || status === 503 || status === 504;
}

export function cloudKitRecordsPayloadDisposition(
    payload: CloudKitRecordsPayload
): "records" | "notFound" | "error" {
    const topLevelCode = typeof payload.serverErrorCode === "string"
        ? payload.serverErrorCode.toUpperCase()
        : null;
    if (topLevelCode) {
        return missingCloudKitRecordCodes.has(topLevelCode) ? "notFound" : "error";
    }

    const records = payload.records ?? [];
    if (records.some((record) => typeof record.serverErrorCode !== "string")) {
        return "records";
    }

    const recordErrorCodes = records.flatMap((record) =>
        typeof record.serverErrorCode === "string"
            ? [record.serverErrorCode.toUpperCase()]
            : []
    );
    if (recordErrorCodes.length === 0 ||
        recordErrorCodes.every((code) => missingCloudKitRecordCodes.has(code))) {
        return "notFound";
    }
    return "error";
}

type VerifiedCloudKitAuthority = {
    record: CloudKitRecordLike;
    usernameClaimCreatedAt?: number;
};

export function cloudKitAuthorityMatches(
    record: CloudKitRecordLike | null,
    identityRecordName: string,
    ownerId: string,
    suppliedCapabilityHash: string
): boolean {
    const creatorRecordName = record?.created?.userRecordName;
    const canonicalRecordNames = typeof creatorRecordName === "string"
        ? [creatorRecordName, `user_${creatorRecordName}`]
        : [];
    return record?.recordName === identityRecordName &&
        canonicalRecordNames.includes(identityRecordName) &&
        record.recordType === "User" &&
        record.fields?.userId?.value === ownerId &&
        capabilityHashesMatch(record.fields?.webShareCapabilityHash?.value, suppliedCapabilityHash);
}

export function canonicalCloudKitOwnerRecord(
    records: CloudKitRecordLike[],
    ownerId: string
): CloudKitRecordLike | null {
    const canonicalRecords = records.filter((record) => {
        const creator = record.created?.userRecordName;
        return record.recordType === "User" &&
            record.fields?.userId?.value === ownerId &&
            typeof creator === "string" &&
            (record.recordName === creator || record.recordName === `user_${creator}`) &&
            typeof record.created?.timestamp === "number";
    });
    canonicalRecords.sort((lhs, rhs) =>
        (lhs.created?.timestamp as number) - (rhs.created?.timestamp as number)
    );
    return canonicalRecords[0] ?? null;
}

export function canonicalCloudKitRecipeCreator(
    records: CloudKitRecordLike[],
    ownerId: string
): WebRecipeCreator | null {
    const record = canonicalCloudKitOwnerRecord(records, ownerId);
    if (!record) {
        return null;
    }
    const username = optionalPublicText(record.fields?.username?.value, MAX_DISPLAY_NAME_LENGTH)?.toLocaleLowerCase();
    const displayName = optionalPublicText(record.fields?.displayName?.value, MAX_DISPLAY_NAME_LENGTH);
    if (!username || !usernamePattern.test(username) || !displayName) {
        return null;
    }
    const profileEmoji = optionalProfileEmoji(record.fields?.profileEmoji?.value);
    const profileColor = typeof record.fields?.profileColor?.value === "string" &&
        /^#[0-9a-f]{6}$/i.test(record.fields.profileColor.value)
        ? record.fields.profileColor.value
        : null;
    return { username, displayName, profileEmoji, profileColor };
}

export function cloudKitOwnerQuery(ownerId: string): object {
    return {
        query: {
            recordType: "User",
            filterBy: [{
                fieldName: "userId",
                comparator: "EQUALS",
                fieldValue: { value: ownerId },
            }],
        },
        resultsLimit: 20,
    };
}

export function cloudKitReferralRecordIsActive(
    record: CloudKitRecordLike,
    referralCode: string
): boolean {
    const creator = record.created?.userRecordName;
    return record.recordType === "User" &&
        record.fields?.referralCode?.value === referralCode &&
        isValidUUID(record.fields?.userId?.value) &&
        typeof creator === "string" &&
        (record.recordName === creator || record.recordName === `user_${creator}`);
}

export function cloudKitReferralQueryResolvesUniquely(
    records: CloudKitRecordLike[],
    referralCode: string,
    continuationMarker?: unknown
): boolean {
    if (typeof continuationMarker === "string") {
        return false;
    }
    return records.filter((record) =>
        cloudKitReferralRecordIsActive(record, referralCode)
    ).length === 1;
}

async function verifyCloudKitReferralCode(referralCode: string): Promise<boolean> {
    const keyID = cloudKitServerKeyID.value();
    const privateKey = cloudKitServerPrivateKey.value().replace(/\\n/g, "\n");
    if (!keyID || !privateKey) {
        logger.warn("Invite preview validation is unavailable because CloudKit credentials are missing");
        return false;
    }

    const subpath = `/database/1/${CLOUDKIT_CONTAINER}/production/public/records/query`;
    const body = JSON.stringify({
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
    const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
    const signature = createSign("SHA256")
        .update(cloudKitSignatureInput(body, date, subpath))
        .end()
        .sign(privateKey)
        .toString("base64");

    try {
        const response = await fetch(`https://api.apple-cloudkit.com${subpath}`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-Apple-CloudKit-Request-KeyID": keyID,
                "X-Apple-CloudKit-Request-ISO8601Date": date,
                "X-Apple-CloudKit-Request-SignatureV1": signature,
            },
            body,
        });
        if (!response.ok) {
            logger.warn("CloudKit invite lookup failed", { status: response.status });
            return false;
        }
        const payload = await response.json() as {
            records?: CloudKitRecordLike[];
            continuationMarker?: unknown;
        };
        return cloudKitReferralQueryResolvesUniquely(
            payload.records ?? [],
            referralCode,
            payload.continuationMarker
        );
    } catch (error) {
        logger.warn("CloudKit invite lookup failed", { error });
        return false;
    }
}

async function verifyCloudKitAuthority(
    identityRecordName: string,
    ownerId: string,
    capability: string,
    expectedUsername?: string
): Promise<VerifiedCloudKitAuthority | null> {
    const keyID = cloudKitServerKeyID.value();
    const privateKey = cloudKitServerPrivateKey.value().replace(/\\n/g, "\n");
    if (!keyID || !privateKey) {
        throw new Error("CloudKit server-to-server credentials are not configured");
    }
    const subpath = `/database/1/${CLOUDKIT_CONTAINER}/production/public/records/query`;
    const endpoint = new URL(`https://api.apple-cloudkit.com${subpath}`);
    const body = JSON.stringify(cloudKitOwnerQuery(ownerId));
    const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
    const signatureInput = cloudKitSignatureInput(body, date, subpath);
    const signature = createSign("SHA256")
        .update(signatureInput)
        .end()
        .sign(privateKey)
        .toString("base64");
    const response = await fetch(endpoint, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            "X-Apple-CloudKit-Request-KeyID": keyID,
            "X-Apple-CloudKit-Request-ISO8601Date": date,
            "X-Apple-CloudKit-Request-SignatureV1": signature,
        },
        body,
    });
    if (!response.ok) {
        logger.warn("CloudKit authority lookup failed", { status: response.status });
        return null;
    }
    const payload = await response.json() as { records?: CloudKitRecordLike[] };
    const canonicalRecord = canonicalCloudKitOwnerRecord(payload.records ?? [], ownerId);
    if (expectedUsername &&
        canonicalRecord?.fields?.username?.value !== expectedUsername.toLocaleLowerCase()) {
        return null;
    }
    let usernameClaimCreatedAt: number | undefined;
    if (expectedUsername && canonicalRecord) {
        const claimTimestamp = await verifyCloudKitUsernameClaim(
            expectedUsername.toLocaleLowerCase(),
            ownerId,
            canonicalRecord
        );
        if (claimTimestamp === null) {
            return null;
        }
        usernameClaimCreatedAt = claimTimestamp;
    }
    if (!cloudKitAuthorityMatches(
        canonicalRecord,
        identityRecordName,
        ownerId,
        capabilityHash(capability)
    ) || !canonicalRecord) {
        return null;
    }
    return { record: canonicalRecord, usernameClaimCreatedAt };
}

async function verifyCloudKitUsernameClaim(
    username: string,
    ownerId: string,
    canonicalUserRecord: CloudKitRecordLike,
    maxAttempts = CLOUDKIT_WEB_MAX_ATTEMPTS
): Promise<number | null> {
    const keyID = cloudKitServerKeyID.value();
    const privateKey = cloudKitServerPrivateKey.value().replace(/\\n/g, "\n");
    return retryTransientCloudKitOperation(async (attempt) => {
        const subpath = `/database/1/${CLOUDKIT_CONTAINER}/production/public/records/lookup`;
        const body = JSON.stringify({ records: [{ recordName: `username_${username}` }] });
        const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
        const signature = createSign("SHA256")
            .update(cloudKitSignatureInput(body, date, subpath))
            .end()
            .sign(privateKey)
            .toString("base64");
        const response = await fetch(`https://api.apple-cloudkit.com${subpath}`, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-Apple-CloudKit-Request-KeyID": keyID,
                "X-Apple-CloudKit-Request-ISO8601Date": date,
                "X-Apple-CloudKit-Request-SignatureV1": signature,
            },
            body,
            signal: AbortSignal.timeout(CLOUDKIT_WEB_REQUEST_TIMEOUT_MS),
        });
        if (!response.ok) {
            logger.warn("CloudKit username claim lookup failed", {
                ownerId,
                status: response.status,
                attempt,
            });
            const message = `CloudKit username claim lookup returned ${response.status}`;
            if (isTransientCloudKitHTTPStatus(response.status)) {
                throw new RetryableCloudKitError(message);
            }
            return null;
        }
        const payload = await response.json() as CloudKitRecordsPayload;
        const disposition = cloudKitRecordsPayloadDisposition(payload);
        if (disposition === "error") {
            const message = "CloudKit username claim lookup returned a record error";
            throw cloudKitRecordsPayloadIsRetryableError(payload)
                ? new RetryableCloudKitError(message)
                : new Error(message);
        }
        if (disposition === "notFound") {
            return null;
        }
        const claim = payload.records?.find((record) =>
            typeof record.serverErrorCode !== "string"
        );
        const isValid = claim?.recordName === `username_${username}` &&
            claim.recordType === "UsernameClaim" &&
            claim.created?.userRecordName === canonicalUserRecord.created?.userRecordName &&
            claim.fields?.userId?.value === ownerId &&
            claim.fields?.username?.value === username;
        const createdAt = claim?.created?.timestamp;
        return isValid && typeof createdAt === "number" ? createdAt : null;
    }, maxAttempts);
}

async function verifyCloudKitResourceAuthority(
    recordName: string,
    recordType: "SharedRecipe" | "Collection",
    ownerField: "ownerId" | "userId",
    ownerId: string,
    identityRecordName: string
): Promise<boolean> {
    const keyID = cloudKitServerKeyID.value();
    const privateKey = cloudKitServerPrivateKey.value().replace(/\\n/g, "\n");
    const subpath = `/database/1/${CLOUDKIT_CONTAINER}/production/public/records/lookup`;
    const body = JSON.stringify({ records: [{ recordName }] });
    const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
    const signature = createSign("SHA256")
        .update(cloudKitSignatureInput(body, date, subpath))
        .end()
        .sign(privateKey)
        .toString("base64");
    const response = await fetch(`https://api.apple-cloudkit.com${subpath}`, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            "X-Apple-CloudKit-Request-KeyID": keyID,
            "X-Apple-CloudKit-Request-ISO8601Date": date,
            "X-Apple-CloudKit-Request-SignatureV1": signature,
        },
        body,
    });
    if (!response.ok) {
        return false;
    }
    const payload = await response.json() as { records?: CloudKitRecordLike[] };
    const record = payload.records?.[0];
    const creator = record?.created?.userRecordName;
    return record?.recordName === recordName &&
        record.recordType === recordType &&
        record.fields?.[ownerField]?.value === ownerId &&
        record.fields?.visibility?.value === "public" &&
        typeof creator === "string" &&
        (identityRecordName === creator || identityRecordName === `user_${creator}`);
}

function decodeCloudKitJSONList(value: unknown, maximumEncodedLength = 2_000_000): unknown[] {
    if (typeof value !== "string" || value.length === 0 || value.length > maximumEncodedLength) {
        return [];
    }
    try {
        const decoded = JSON.parse(Buffer.from(value, "base64").toString("utf8"));
        return Array.isArray(decoded) ? decoded : [];
    } catch {
        return [];
    }
}

function sanitizeWebQuantity(value: unknown): WebRecipeQuantity | null {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
        return null;
    }
    const quantity = value as Record<string, unknown>;
    if (typeof quantity.value !== "number" || !Number.isFinite(quantity.value) ||
        quantity.value < 0 || quantity.value > 100_000 ||
        typeof quantity.unit !== "string" || quantity.unit.length > 40) {
        return null;
    }
    const upperValue = typeof quantity.upperValue === "number" &&
        Number.isFinite(quantity.upperValue) && quantity.upperValue >= quantity.value &&
        quantity.upperValue <= 100_000
        ? quantity.upperValue
        : null;
    return { value: quantity.value, upperValue, unit: quantity.unit };
}

function safeCloudKitAssetURL(value: unknown): string | null {
    if (typeof value !== "string") {
        return null;
    }
    try {
        const url = new URL(value);
        const isAppleAssetHost = url.hostname === "cvws.icloud-content.com" ||
            url.hostname.endsWith(".icloud-content.com");
        return url.protocol === "https:" && !url.username && !url.password && isAppleAssetHost
            ? url.toString()
            : null;
    } catch {
        return null;
    }
}

export function sanitizeCloudKitRecipeForWeb(
    record: CloudKitRecordLike,
    expectedRecipeId: string,
    expectedOwnerId: string
): WebRecipeContent | null {
    const fields = record.fields ?? {};
    if (record.recordName !== expectedRecipeId || record.recordType !== "SharedRecipe" ||
        fields.recipeId?.value !== expectedRecipeId || fields.ownerId?.value !== expectedOwnerId ||
        fields.visibility?.value !== "public") {
        return null;
    }

    const title = requiredPublicText(fields.title?.value, "title", MAX_TITLE_LENGTH);
    if (!title.ok) {
        return null;
    }

    const ingredients = decodeCloudKitJSONList(fields.ingredientsData?.value)
        .slice(0, MAX_WEB_INGREDIENTS)
        .flatMap((rawIngredient): WebRecipeIngredient[] => {
            if (!rawIngredient || typeof rawIngredient !== "object" || Array.isArray(rawIngredient)) {
                return [];
            }
            const ingredient = rawIngredient as Record<string, unknown>;
            const name = optionalPublicText(ingredient.name, MAX_WEB_RECIPE_TEXT_LENGTH);
            if (!name) {
                return [];
            }
            const additionalQuantities = Array.isArray(ingredient.additionalQuantities)
                ? ingredient.additionalQuantities.slice(0, 4)
                    .map(sanitizeWebQuantity)
                    .filter((quantity): quantity is WebRecipeQuantity => quantity !== null)
                : [];
            return [{
                name,
                quantity: sanitizeWebQuantity(ingredient.quantity),
                additionalQuantities,
                note: optionalPublicText(ingredient.note, 500),
                section: optionalPublicText(ingredient.section, MAX_TITLE_LENGTH),
            }];
        });

    const steps = decodeCloudKitJSONList(fields.stepsData?.value)
        .slice(0, MAX_WEB_STEPS)
        .flatMap((rawStep, fallbackIndex): WebRecipeStep[] => {
            if (!rawStep || typeof rawStep !== "object" || Array.isArray(rawStep)) {
                return [];
            }
            const step = rawStep as Record<string, unknown>;
            const text = optionalPublicText(step.text, MAX_WEB_RECIPE_TEXT_LENGTH);
            if (!text) {
                return [];
            }
            return [{
                index: typeof step.index === "number" && Number.isSafeInteger(step.index) && step.index >= 0
                    ? step.index
                    : fallbackIndex,
                text,
                section: optionalPublicText(step.section, MAX_TITLE_LENGTH),
            }];
        })
        .sort((lhs, rhs) => lhs.index - rhs.index);

    const tags = decodeCloudKitJSONList(fields.tagsData?.value)
        .flatMap((rawTag): string[] => {
            if (!rawTag || typeof rawTag !== "object" || Array.isArray(rawTag)) {
                return [];
            }
            const name = optionalPublicText((rawTag as Record<string, unknown>).name, MAX_TAG_LENGTH);
            return name ? [name] : [];
        });
    const asset = fields.imageAsset?.value;
    const assetRecord = asset && typeof asset === "object" && !Array.isArray(asset)
        ? asset as Record<string, unknown>
        : null;
    const assetSize = typeof assetRecord?.size === "number" ? assetRecord.size : null;

    return {
        recipeId: expectedRecipeId,
        ownerId: expectedOwnerId,
        title: title.value,
        yields: optionalPublicText(fields.yields?.value, 160),
        totalMinutes: optionalPositiveInteger(fields.totalMinutes?.value, 1440),
        tags: sanitizedTagList(tags),
        ingredients,
        steps,
        imageURL: assetSize !== null && assetSize <= 25_000_000
            ? safeCloudKitAssetURL(assetRecord?.downloadURL)
            : null,
    };
}

async function fetchPublicCloudKitRecipe(
    recipeId: string,
    ownerId: string
): Promise<WebRecipeContent | null> {
    const keyID = cloudKitServerKeyID.value();
    const privateKey = cloudKitServerPrivateKey.value().replace(/\\n/g, "\n");
    if (!keyID || !privateKey) {
        throw new Error("CloudKit web recipe credentials are unavailable");
    }
    try {
        return await retryTransientCloudKitOperation(async (attempt) => {
            const subpath = `/database/1/${CLOUDKIT_CONTAINER}/production/public/records/lookup`;
            const body = JSON.stringify({ records: [{ recordName: recipeId }] });
            const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
            const signature = createSign("SHA256")
                .update(cloudKitSignatureInput(body, date, subpath))
                .end()
                .sign(privateKey)
                .toString("base64");
            const response = await fetch(`https://api.apple-cloudkit.com${subpath}`, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-Apple-CloudKit-Request-KeyID": keyID,
                    "X-Apple-CloudKit-Request-ISO8601Date": date,
                    "X-Apple-CloudKit-Request-SignatureV1": signature,
                },
                body,
                signal: AbortSignal.timeout(CLOUDKIT_WEB_REQUEST_TIMEOUT_MS),
            });
            if (!response.ok) {
                logger.warn("CloudKit web recipe lookup failed", {
                    recipeId,
                    status: response.status,
                    attempt,
                });
                const message = `CloudKit web recipe lookup returned ${response.status}`;
                throw isTransientCloudKitHTTPStatus(response.status)
                    ? new RetryableCloudKitError(message)
                    : new Error(message);
            }
            const payload = await response.json() as CloudKitRecordsPayload;
            const disposition = cloudKitRecordsPayloadDisposition(payload);
            if (disposition === "error") {
                const message = "CloudKit web recipe lookup returned a record error";
                throw cloudKitRecordsPayloadIsRetryableError(payload)
                    ? new RetryableCloudKitError(message)
                    : new Error(message);
            }
            if (disposition === "notFound") {
                return null;
            }
            const record = payload.records?.find((candidate) =>
                typeof candidate.serverErrorCode !== "string"
            );
            return record ? sanitizeCloudKitRecipeForWeb(record, recipeId, ownerId) : null;
        });
    } catch (error) {
        logger.warn("CloudKit web recipe lookup failed", { recipeId, error });
        throw error;
    }
}

export function recipeIndexItemsWithCloudKitImages(
    recipes: SanitizedRecipeShare[],
    records: CloudKitRecordLike[]
): WebRecipeIndexItem[] {
    const recordsByName = new Map(records.flatMap((record) =>
        typeof record.recordName === "string" && typeof record.serverErrorCode !== "string"
            ? [[record.recordName, record] as const]
            : []
    ));
    return recipes.map((recipe) => {
        const record = recordsByName.get(recipe.recipeId);
        const canonical = record
            ? sanitizeCloudKitRecipeForWeb(record, recipe.recipeId, recipe.ownerId)
            : null;
        return {
            ...recipe,
            imageURL: canonical?.imageURL ?? null,
        };
    });
}

async function fetchPublicCloudKitRecipeIndexItems(
    recipes: SanitizedRecipeShare[]
): Promise<WebRecipeIndexItem[]> {
    if (recipes.length === 0) {
        return [];
    }
    const keyID = cloudKitServerKeyID.value();
    const privateKey = cloudKitServerPrivateKey.value().replace(/\\n/g, "\n");
    if (!keyID || !privateKey) {
        throw new Error("CloudKit web recipe credentials are unavailable");
    }
    const subpath = `/database/1/${CLOUDKIT_CONTAINER}/production/public/records/lookup`;
    const body = JSON.stringify(cloudKitRecipeShelfLookupBody(recipes));
    const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
    const signature = createSign("SHA256")
        .update(cloudKitSignatureInput(body, date, subpath))
        .end()
        .sign(privateKey)
        .toString("base64");
    const response = await fetch(`https://api.apple-cloudkit.com${subpath}`, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            "X-Apple-CloudKit-Request-KeyID": keyID,
            "X-Apple-CloudKit-Request-ISO8601Date": date,
            "X-Apple-CloudKit-Request-SignatureV1": signature,
        },
        body,
        // Shelf imagery is optional. Fall back quickly so a CloudKit slowdown
        // never holds an otherwise valid profile or collection page hostage.
        signal: AbortSignal.timeout(2_000),
    });
    if (!response.ok) {
        throw new Error(`CloudKit web recipe shelf lookup returned ${response.status}`);
    }
    const payload = await response.json() as CloudKitRecordsPayload;
    if (typeof payload.serverErrorCode === "string" &&
        payload.serverErrorCode.toUpperCase() !== "UNKNOWN_ITEM") {
        throw new Error("CloudKit web recipe shelf lookup returned a server error");
    }
    return recipeIndexItemsWithCloudKitImages(recipes, payload.records ?? []);
}

export function cloudKitRecipeShelfLookupBody(
    recipes: Array<Pick<SanitizedRecipeShare, "recipeId">>
): Readonly<{ records: Array<{ recordName: string }>; desiredKeys: string[] }> {
    return {
        records: recipes.map((recipe) => ({ recordName: recipe.recipeId })),
        desiredKeys: ["recipeId", "ownerId", "visibility", "title", "imageAsset"],
    };
}

async function bestEffortRecipeIndexItems(
    recipes: SanitizedRecipeShare[]
): Promise<WebRecipeIndexItem[]> {
    try {
        return await fetchPublicCloudKitRecipeIndexItems(recipes);
    } catch (error) {
        logger.warn("CloudKit recipe shelf imagery is temporarily unavailable", { error });
        return recipes.map((recipe) => ({ ...recipe, imageURL: null }));
    }
}

async function fetchPublicCloudKitRecipeCreator(ownerId: string): Promise<WebRecipeCreator | null> {
    const keyID = cloudKitServerKeyID.value();
    const privateKey = cloudKitServerPrivateKey.value().replace(/\\n/g, "\n");
    if (!keyID || !privateKey) {
        throw new Error("CloudKit web creator credentials are unavailable");
    }
    try {
        const identity = await retryTransientCloudKitOperation(async (attempt) => {
            const subpath = `/database/1/${CLOUDKIT_CONTAINER}/production/public/records/query`;
            const body = JSON.stringify(cloudKitOwnerQuery(ownerId));
            const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
            const signature = createSign("SHA256")
                .update(cloudKitSignatureInput(body, date, subpath))
                .end()
                .sign(privateKey)
                .toString("base64");
            const response = await fetch(`https://api.apple-cloudkit.com${subpath}`, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-Apple-CloudKit-Request-KeyID": keyID,
                    "X-Apple-CloudKit-Request-ISO8601Date": date,
                    "X-Apple-CloudKit-Request-SignatureV1": signature,
                },
                body,
                signal: AbortSignal.timeout(CLOUDKIT_WEB_REQUEST_TIMEOUT_MS),
            });
            if (!response.ok) {
                logger.warn("CloudKit web recipe creator lookup failed", {
                    ownerId,
                    status: response.status,
                    attempt,
                });
                const message = `CloudKit web recipe creator lookup returned ${response.status}`;
                throw isTransientCloudKitHTTPStatus(response.status)
                    ? new RetryableCloudKitError(message)
                    : new Error(message);
            }
            const payload = await response.json() as CloudKitRecordsPayload;
            const disposition = cloudKitRecordsPayloadDisposition(payload);
            if (disposition === "error") {
                const message = "CloudKit web creator lookup returned a record error";
                throw cloudKitRecordsPayloadIsRetryableError(payload)
                    ? new RetryableCloudKitError(message)
                    : new Error(message);
            }
            if (disposition === "notFound") {
                return null;
            }
            const records = (payload.records ?? []).filter((record) =>
                typeof record.serverErrorCode !== "string"
            );
            const canonicalRecord = canonicalCloudKitOwnerRecord(records, ownerId);
            const creator = canonicalCloudKitRecipeCreator(records, ownerId);
            if (!canonicalRecord || !creator || await verifyCloudKitUsernameClaim(
                creator.username,
                ownerId,
                canonicalRecord,
                1
            ) === null) {
                return null;
            }
            return creator;
        });
        return identity;
    } catch (error) {
        logger.warn("CloudKit web recipe creator lookup failed", { ownerId, error });
        throw error;
    }
}

export function cloudKitSignatureInput(body: string, date: string, subpath: string): string {
    const bodyHash = createHash("sha256").update(body, "utf8").digest("base64");
    return `${date}:${bodyHash}:${subpath}`;
}

export function isValidUUID(value: unknown): value is string {
    return typeof value === "string" && uuidPattern.test(value);
}

function requiredBoundedString(value: unknown, field: string, maxLength: number): ValidationResult<string> {
    if (typeof value !== "string") {
        return { ok: false, error: `${field} must be a string` };
    }

    const trimmed = value.trim();
    if (!trimmed) {
        return { ok: false, error: `${field} is required` };
    }

    if (trimmed.length > maxLength) {
        return { ok: false, error: `${field} is too long` };
    }

    return { ok: true, value: trimmed };
}

function optionalBoundedString(value: unknown, maxLength: number): string | null {
    if (typeof value !== "string") {
        return null;
    }

    const trimmed = value.trim();
    return trimmed ? trimmed.slice(0, maxLength) : null;
}

function optionalPublicText(value: unknown, maxLength: number): string | null {
    const bounded = optionalBoundedString(value, maxLength);
    if (!bounded) {
        return null;
    }

    return bounded.replace(
        /(?:https?:[\\/]{1,2}|[\\/]{2}|[a-z][a-z0-9+.-]*:[\\/]{1,2})[^\s<>"']+/gi,
        (rawURL) => /^https?:[\\/]{1,2}/i.test(rawURL)
            ? safeWebURL(rawURL) ?? "[private URL removed]"
            : "[private URL removed]"
    );
}

function optionalProfileEmoji(value: unknown): string | null {
    const bounded = optionalBoundedString(value, 16);
    if (!bounded || /(?:https?:[\\/]{1,2}|[\\/]{2}|[a-z][a-z0-9+.-]*:[\\/]{1,2})/i.test(bounded)) {
        return null;
    }
    return bounded;
}

function requiredPublicText(value: unknown, field: string, maxLength: number): ValidationResult<string> {
    const required = requiredBoundedString(value, field, maxLength);
    if (!required.ok) {
        return required;
    }
    const sanitized = optionalPublicText(required.value, maxLength);
    return sanitized
        ? { ok: true, value: sanitized }
        : { ok: false, error: `${field} is required` };
}

function optionalNonNegativeInteger(value: unknown, fallback: number, max: number): number {
    if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
        return fallback;
    }

    return Math.min(value, max);
}

function optionalPositiveInteger(value: unknown, max: number): number | null {
    if (value === null || value === undefined) {
        return null;
    }

    if (typeof value !== "number" || !Number.isInteger(value) || value <= 0) {
        return null;
    }

    return Math.min(value, max);
}

function sanitizedTagList(value: unknown): string[] {
    if (!Array.isArray(value)) {
        return [];
    }

    const seen = new Set<string>();
    const tags: string[] = [];

    for (const item of value) {
        if (typeof item !== "string") {
            continue;
        }

        const trimmed = optionalPublicText(item, MAX_TAG_LENGTH);
        if (!trimmed) {
            continue;
        }
        const key = trimmed.toLocaleLowerCase();
        if (!trimmed || seen.has(key)) {
            continue;
        }

        seen.add(key);
        tags.push(trimmed);
        if (tags.length >= MAX_TAG_COUNT) {
            break;
        }
    }

    return tags;
}

function sanitizedUUIDList(value: unknown): string[] {
    if (!Array.isArray(value)) {
        return [];
    }

    const seen = new Set<string>();
    const ids: string[] = [];

    for (const item of value) {
        if (!isValidUUID(item) || seen.has(item)) {
            continue;
        }

        seen.add(item);
        ids.push(item);
        if (ids.length >= MAX_RECIPE_IDS_PER_COLLECTION) {
            break;
        }
    }

    return ids;
}

export function sanitizeRecipeShareInput(input: Record<string, unknown>): ValidationResult<SanitizedRecipeShare> {
    if (!isValidUUID(input.recipeId)) {
        return { ok: false, error: "recipeId must be a UUID" };
    }
    if (!isValidUUID(input.ownerId)) {
        return { ok: false, error: "ownerId must be a UUID" };
    }

    const title = requiredPublicText(input.title, "title", MAX_TITLE_LENGTH);
    if (!title.ok) {
        return title;
    }
    const identityRecordName = sanitizedRecordName(input.identityRecordName);
    if (!identityRecordName) {
        return { ok: false, error: "identityRecordName is invalid" };
    }

    const capability = sanitizedCapability(input.capability);
    if (!capability) {
        return { ok: false, error: "a valid management capability is required" };
    }

    const value: SanitizedRecipeShare = {
        recipeId: input.recipeId,
        ownerId: input.ownerId,
        identityRecordName,
        title: title.value,
        totalMinutes: optionalPositiveInteger(input.totalMinutes, 1440),
        tags: sanitizedTagList(input.tags),
        capability,
        shouldCreate: input.shouldCreate === true,
    };

    return { ok: true, value };
}

/// Revalidates a persisted public snapshot without requiring the private
/// mutation capability, which is deliberately never stored in Firestore.
export function sanitizeStoredRecipeShareInput(
    input: Record<string, unknown>
): ValidationResult<SanitizedRecipeShare> {
    return sanitizeRecipeShareInput({
        ...input,
        identityRecordName: "server_persisted_snapshot",
        capability: "s".repeat(43),
    });
}

export function sanitizeRecipeUnshareInput(input: Record<string, unknown>): ValidationResult<SanitizedRecipeUnshare> {
    if (!isValidUUID(input.recipeId) || !isValidUUID(input.ownerId)) {
        return { ok: false, error: "recipeId and ownerId must be UUIDs" };
    }
    const capability = sanitizedCapability(input.capability);
    const identityRecordName = sanitizedRecordName(input.identityRecordName);
    if (!capability || !identityRecordName) {
        return { ok: false, error: "a valid management capability is required" };
    }

    return {
        ok: true,
        value: {
            recipeId: input.recipeId,
            ownerId: input.ownerId,
            identityRecordName,
            capability,
        },
    };
}

export function sanitizeProfileShareInput(input: Record<string, unknown>): ValidationResult<SanitizedProfileShare> {
    if (!isValidUUID(input.userId)) {
        return { ok: false, error: "userId must be a UUID" };
    }
    if (typeof input.username !== "string" || !usernamePattern.test(input.username)) {
        return { ok: false, error: "username is invalid" };
    }

    const displayName = requiredPublicText(
        input.displayName || input.username,
        "displayName",
        MAX_DISPLAY_NAME_LENGTH
    );
    if (!displayName.ok) {
        return displayName;
    }
    const capability = sanitizedCapability(input.capability);
    const identityRecordName = sanitizedRecordName(input.identityRecordName);
    if (!capability || !identityRecordName) {
        return { ok: false, error: "a valid management capability is required" };
    }

    return {
        ok: true,
        value: {
            userId: input.userId,
            identityRecordName,
            username: input.username.toLocaleLowerCase(),
            displayName: displayName.value,
            profileEmoji: optionalProfileEmoji(input.profileEmoji),
            profileColor: typeof input.profileColor === "string" && /^#[0-9a-f]{6}$/i.test(input.profileColor)
                ? input.profileColor
                : null,
            recipeCount: input.recipeCount === undefined
                ? null
                : optionalNonNegativeInteger(input.recipeCount, 0, 10000),
            capability,
            shouldCreate: input.shouldCreate === true,
        },
    };
}

export function sanitizeStoredProfileShareInput(
    input: Record<string, unknown>
): ValidationResult<SanitizedProfileShare> {
    if (input.ownerId !== input.userId) {
        return { ok: false, error: "stored profile owner mismatch" };
    }
    return sanitizeProfileShareInput({
        ...input,
        identityRecordName: "server_persisted_snapshot",
        capability: "s".repeat(43),
    });
}

export function sanitizeProfileUnshareInput(input: Record<string, unknown>): ValidationResult<SanitizedProfileUnshare> {
    if (!isValidUUID(input.userId)) {
        return { ok: false, error: "userId must be a UUID" };
    }
    const capability = sanitizedCapability(input.capability);
    const identityRecordName = sanitizedRecordName(input.identityRecordName);
    if (!capability || !identityRecordName || typeof input.username !== "string" || !usernamePattern.test(input.username)) {
        return { ok: false, error: "a valid management capability is required" };
    }
    return {
        ok: true,
        value: {
            userId: input.userId,
            identityRecordName,
            username: input.username.toLocaleLowerCase(),
            capability,
        },
    };
}

export function sanitizeAccountUnshareInput(input: Record<string, unknown>): ValidationResult<SanitizedAccountUnshare> {
    if (!isValidUUID(input.userId)) {
        return { ok: false, error: "userId must be a UUID" };
    }
    const capability = sanitizedCapability(input.capability);
    const identityRecordName = sanitizedRecordName(input.identityRecordName);
    if (!capability || !identityRecordName) {
        return { ok: false, error: "valid CloudKit identity and management capability are required" };
    }
    return { ok: true, value: { userId: input.userId, identityRecordName, capability } };
}

export function sanitizeCollectionShareInput(input: Record<string, unknown>): ValidationResult<SanitizedCollectionShare> {
    if (!isValidUUID(input.collectionId)) {
        return { ok: false, error: "collectionId must be a UUID" };
    }
    if (!isValidUUID(input.ownerId)) {
        return { ok: false, error: "ownerId must be a UUID" };
    }

    const title = requiredPublicText(input.title, "title", MAX_TITLE_LENGTH);
    if (!title.ok) {
        return title;
    }

    const recipeIds = sanitizedUUIDList(input.recipeIds);
    const capability = sanitizedCapability(input.capability);
    const identityRecordName = sanitizedRecordName(input.identityRecordName);
    if (!capability || !identityRecordName) {
        return { ok: false, error: "a valid management capability is required" };
    }

    return {
        ok: true,
        value: {
            collectionId: input.collectionId,
            ownerId: input.ownerId,
            identityRecordName,
            title: title.value,
            recipeCount: optionalNonNegativeInteger(input.recipeCount, recipeIds.length, 10000),
            recipeIds,
            capability,
            shouldCreate: input.shouldCreate === true,
        },
    };
}

export function sanitizeStoredCollectionShareInput(
    input: Record<string, unknown>
): ValidationResult<SanitizedCollectionShare> {
    return sanitizeCollectionShareInput({
        ...input,
        identityRecordName: "server_persisted_snapshot",
        capability: "s".repeat(43),
    });
}

export function sanitizeCollectionUnshareInput(
    input: Record<string, unknown>
): ValidationResult<SanitizedCollectionUnshare> {
    if (!isValidUUID(input.collectionId) || !isValidUUID(input.ownerId)) {
        return { ok: false, error: "collectionId and ownerId must be UUIDs" };
    }
    const capability = sanitizedCapability(input.capability);
    const identityRecordName = sanitizedRecordName(input.identityRecordName);
    if (!capability || !identityRecordName) {
        return { ok: false, error: "a valid management capability is required" };
    }
    return {
        ok: true,
        value: { collectionId: input.collectionId, ownerId: input.ownerId, identityRecordName, capability },
    };
}

class ShareAuthorizationError extends Error {}
class StaleShareMutationError extends Error {}

function shareRevocationRef(ownerId: string): DocumentReference {
    return db.collection('share_revocations').doc(ownerId);
}

async function isShareRevoked(ownerId: unknown): Promise<boolean> {
    if (!isValidUUID(ownerId)) {
        return true;
    }
    const revocation = await shareRevocationRef(ownerId).get();
    return revocation.exists && typeof revocation.data()?.restoredCapabilityHash !== "string";
}

function revocationBlocksCapability(
    revocation: DocumentSnapshot,
    suppliedHash: string
): boolean {
    if (!revocation.exists) {
        return false;
    }
    return revocation.data()?.restoredCapabilityHash !== suppliedHash;
}

function accountMutationRef(ownerId: string): DocumentReference {
    return db.collection("share_account_mutation_states").doc(ownerId);
}

export function retiredCapabilityCannotSupersedeRestoration(
    stateIntent: unknown,
    stateCapabilityHash: unknown,
    restoredCapabilityHash: unknown,
    suppliedHash: string
): boolean {
    return (stateIntent === "restore" && stateCapabilityHash !== suppliedHash) ||
        (typeof restoredCapabilityHash === "string" && restoredCapabilityHash !== suppliedHash);
}

async function beginAccountMutation(
    ownerId: string,
    intent: "unshare" | "restore",
    suppliedHash: string
): Promise<number> {
    const stateRef = accountMutationRef(ownerId);
    return db.runTransaction(async (transaction) => {
        const state = await transaction.get(stateRef);
        const revocation = await transaction.get(shareRevocationRef(ownerId));
        if (intent === "unshare") {
            if (retiredCapabilityCannotSupersedeRestoration(
                state.data()?.intent,
                state.data()?.capabilityHash,
                revocation.data()?.restoredCapabilityHash,
                suppliedHash
            )) {
                throw new StaleShareMutationError();
            }
        }
        const generation = (typeof state.data()?.generation === "number" ? state.data()!.generation : 0) + 1;
        transaction.set(stateRef, {
            generation,
            intent,
            capabilityHash: suppliedHash,
            updatedAt: FieldValue.serverTimestamp(),
        });
        return generation;
    });
}

async function deleteAllSnapshotsForOwnerAtGeneration(ownerId: string, generation: number): Promise<void> {
    const [recipes, profiles, collections] = await Promise.all([
        db.collection('shared_recipes').where('ownerId', '==', ownerId).get(),
        db.collection('shared_profiles').where('ownerId', '==', ownerId).get(),
        db.collection('shared_collections').where('ownerId', '==', ownerId).get(),
    ]);
    const references = [...recipes.docs, ...profiles.docs, ...collections.docs];
    for (let index = 0; index < references.length; index += 300) {
        const chunk = references.slice(index, index + 300);
        await db.runTransaction(async (transaction) => {
            const state = await transaction.get(accountMutationRef(ownerId));
            requireCurrentResourceMutation(state, generation);
            for (const document of chunk) {
                transaction.delete(document.ref);
            }
        });
    }
}

function resourceMutationRef(kind: "recipe" | "profile" | "collection", id: string): DocumentReference {
    return db.collection('share_mutation_states').doc(`${kind}_${id}`);
}

function resourcePrivacyRef(
    kind: "recipe" | "profile" | "collection",
    id: string,
    suppliedHash: string
): DocumentReference {
    // Keep one immutable denial record per retired capability. A later share
    // must not erase the evidence needed to stop an older, already-authorized
    // request that resumes after capability rotation.
    return db.collection("share_privacy_epochs")
        .doc(`${kind}_${id}`)
        .collection("revoked_capabilities")
        .doc(suppliedHash);
}

function resourcePrivacyRootRef(
    kind: "recipe" | "profile" | "collection",
    id: string
): DocumentReference {
    return db.collection("share_privacy_epochs").doc(`${kind}_${id}`);
}

function privacyEpochBlocksCapability(
    epoch: DocumentSnapshot
): boolean {
    return epoch.exists;
}

async function isResourcePrivacyBlocked(
    kind: "recipe" | "profile" | "collection",
    id: string
): Promise<boolean> {
    return (await resourcePrivacyRootRef(kind, id).get()).data()?.blocked === true;
}

async function beginResourceMutation(
    kind: "recipe" | "profile" | "collection",
    id: string,
    intent: "publish" | "unshare",
    suppliedHash: string
): Promise<number> {
    const stateRef = resourceMutationRef(kind, id);
    return db.runTransaction(async (transaction) => {
        const state = await transaction.get(stateRef);
        if (resourceMutationCannotSupersede(
            state.data()?.intent,
            state.data()?.capabilityHash,
            intent,
            suppliedHash
        )) {
            throw new StaleShareMutationError();
        }
        const currentGeneration = typeof state.data()?.generation === "number"
            ? state.data()!.generation as number
            : 0;
        const generation = currentGeneration + 1;
        transaction.set(stateRef, {
            generation,
            intent,
            capabilityHash: suppliedHash,
            updatedAt: FieldValue.serverTimestamp(),
        });
        return generation;
    });
}

export function resourceMutationCannotSupersede(
    currentIntent: unknown,
    currentCapabilityHash: unknown,
    nextIntent: "publish" | "unshare",
    nextCapabilityHash: string
): boolean {
    if (nextIntent === "publish") {
        return currentIntent === "unshare" && currentCapabilityHash === nextCapabilityHash;
    }
    return currentIntent === "publish" &&
        typeof currentCapabilityHash === "string" &&
        currentCapabilityHash !== nextCapabilityHash;
}

function platformForwardedClientAddress(req: Request): string {
    // Google appends the actual client and load-balancer addresses after any
    // caller-supplied XFF prefix. Key from that trusted two-hop suffix so a
    // spoofed leftmost value cannot mint unbounded Firestore buckets.
    const forwarded = req.headers["x-forwarded-for"];
    const value = Array.isArray(forwarded) ? forwarded[0] : forwarded;
    const hops = value?.split(",").map((hop) => hop.trim()).filter(Boolean) ?? [];
    const trustedSuffix = hops.length >= 2 ? hops.slice(-2).join(",") : null;
    return trustedSuffix || req.ip || req.socket.remoteAddress || "unknown";
}

export function isCurrentResourceMutationGeneration(
    stateData: Record<string, unknown> | undefined,
    generation: number
): boolean {
    return stateData?.generation === generation;
}

function requireCurrentResourceMutation(
    state: DocumentSnapshot,
    generation: number
): void {
    if (!isCurrentResourceMutationGeneration(state.data(), generation)) {
        throw new StaleShareMutationError();
    }
}

async function enforceMutationRateLimit(req: Request): Promise<boolean> {
    const now = Date.now();
    const windowMilliseconds = 60_000;
    const clientKey = createHash("sha256")
        .update(platformForwardedClientAddress(req), "utf8")
        .digest("hex");
    const limitRef = db.collection("share_rate_limits").doc(clientKey);
    return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(limitRef);
        const data = snapshot.data();
        const startedAt = typeof data?.startedAt === "number" ? data.startedAt : 0;
        const count = typeof data?.count === "number" ? data.count : 0;
        const next = now - startedAt >= windowMilliseconds
            ? { startedAt: now, count: 1 }
            : { startedAt, count: count + 1 };
        transaction.set(limitRef, {
            ...next,
            expiresAt: Timestamp.fromMillis(now + 86_400_000),
        });
        return next.count <= 300;
    });
}

async function enforcePublicReadRateLimit(req: Request): Promise<boolean> {
    const now = Date.now();
    const clientKey = createHash("sha256")
        .update(platformForwardedClientAddress(req), "utf8")
        .digest("hex");
    const limitRef = db.collection("share_read_rate_limits").doc(clientKey);
    return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(limitRef);
        const data = snapshot.data();
        const startedAt = typeof data?.startedAt === "number" ? data.startedAt : 0;
        const count = typeof data?.count === "number" ? data.count : 0;
        const next = now - startedAt >= 60_000
            ? { startedAt: now, count: 1 }
            : { startedAt, count: count + 1 };
        transaction.set(limitRef, {
            ...next,
            expiresAt: Timestamp.fromMillis(now + 86_400_000),
        });
        return next.count <= 120;
    });
}

function rejectRateLimitedMutation(res: { status(code: number): { json(body: unknown): unknown } }): void {
    res.status(429).json({ error: "Too many sharing requests. Please try again shortly." });
}

function rejectRateLimitedRead(res: { status(code: number): { json(body: unknown): unknown } }): void {
    res.status(429).json({ error: "Too many requests. Please try again shortly." });
}

// function generateShareId(): string {
//     const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
//     let result = '';
//     for (let i = 0; i < 8; i++) {
//         result += chars.charAt(Math.floor(Math.random() * chars.length));
//     }
//     return result;
// }
// 
// async function isShareIdUnique(collection: string, shareId: string): Promise<boolean> {
//     const doc = await db.collection(collection).doc(shareId).get();
//     return !doc.exists;
// }

// function createUniqueShareId(collection: string): Promise<string> {
//     let shareId = generateShareId();
//     let attempts = 0;
//     while (!(await isShareIdUnique(collection, shareId)) && attempts < 10) {
//         shareId = generateShareId();
//         attempts++;
//     }
//     if (attempts >= 10) {
//         throw new Error('Failed to generate unique share ID');
//     }
//     return shareId;
// }

// --- API Endpoints ---

const cloudAuthorizedHTTPOptions = {
    // Mutations are native-app/server calls; no browser origin needs access.
    cors: false,
    invoker: "public" as const,
    secrets: [cloudKitServerKeyID, cloudKitServerPrivateKey],
    maxInstances: 5,
    concurrency: 20,
    timeoutSeconds: 30,
};

const publicReadHTTPOptions = {
    cors: true,
    invoker: "public" as const,
    maxInstances: 10,
    concurrency: 40,
    timeoutSeconds: 30,
};

const cloudBackedPublicReadHTTPOptions = {
    ...publicReadHTTPOptions,
    secrets: [cloudKitServerKeyID, cloudKitServerPrivateKey],
};

const legacyMutationHTTPOptions = {
    cors: false,
    invoker: "public" as const,
    maxInstances: 1,
    concurrency: 20,
    timeoutSeconds: 10,
};

const upgradeRequired = onRequest(legacyMutationHTTPOptions, async (_req, res) => {
    res.set(publicSecurityHeaders());
    res.set("Cache-Control", "private, no-store, max-age=0");
    res.status(426).json({
        error: "This version of Cauldron can no longer publish web shares. Update the app to continue.",
    });
});

// Keep the legacy function names as cheap, explicit compatibility boundaries.
// Reusing them for the authenticated contract would turn an app update into a
// silent 400-response outage and leave no safe path to retire unauthenticated writes.
export const shareRecipe = upgradeRequired;
export const unshareRecipe = upgradeRequired;
export const shareProfile = upgradeRequired;
export const unshareProfile = upgradeRequired;
export const unshareAccount = upgradeRequired;
export const shareCollection = upgradeRequired;
export const unshareCollection = upgradeRequired;

// Share Recipe
export const shareRecipeV2 = onRequest(cloudAuthorizedHTTPOptions, async (req, res) => {
    if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed');
        return;
    }
    if (!await enforceMutationRateLimit(req)) {
        rejectRateLimitedMutation(res);
        return;
    }

    try {
        const sanitized = sanitizeRecipeShareInput(req.body ?? {});
        if (!sanitized.ok) {
            res.status(400).json({ error: sanitized.error });
            return;
        }
        const share = sanitized.value;
        if (!await verifyCloudKitAuthority(
            share.identityRecordName,
            share.ownerId,
            share.capability
        )) {
            throw new ShareAuthorizationError();
        }
        if (!await verifyCloudKitResourceAuthority(
            share.recipeId,
            "SharedRecipe",
            "ownerId",
            share.ownerId,
            share.identityRecordName
        )) {
            throw new ShareAuthorizationError();
        }
        const suppliedHash = capabilityHash(share.capability);
        const mutationGeneration = await beginResourceMutation(
            "recipe", share.recipeId, "publish", suppliedHash
        );

        const shareId = share.recipeId;
        const summaryData = {
            recipeId: share.recipeId,
            ownerId: share.ownerId,
            title: share.title,
            totalMinutes: share.totalMinutes,
            tags: share.tags,
            updatedAt: FieldValue.serverTimestamp(),
        };

        const docRef = db.collection('shared_recipes').doc(shareId);
        // Every mutation is checked against the capability currently registered
        // by the owner's iCloud identity, so rotating it revokes the old key.
        const published = await db.runTransaction(async (transaction) => {
            const revocation = await transaction.get(shareRevocationRef(share.ownerId));
            const privacyRoot = await transaction.get(resourcePrivacyRootRef("recipe", share.recipeId));
            const privacyEpoch = await transaction.get(resourcePrivacyRef("recipe", share.recipeId, suppliedHash));
            const mutationState = await transaction.get(resourceMutationRef("recipe", share.recipeId));
            const existing = await transaction.get(docRef);
            const existingData = existing.data() ?? {};
            requireCurrentResourceMutation(mutationState, mutationGeneration);
            if (revocationBlocksCapability(revocation, suppliedHash)) {
                throw new ShareAuthorizationError();
            }
            if (privacyEpochBlocksCapability(privacyEpoch)) {
                throw new ShareAuthorizationError();
            }
            if (existing.exists && existingData.ownerId !== share.ownerId) {
                throw new ShareAuthorizationError();
            }
            if (!existing.exists && !share.shouldCreate) {
                return false;
            }

            transaction.set(docRef, {
                ...summaryData,
                capabilityHash: suppliedHash,
                // The web snapshot is intentionally a non-sensitive pointer,
                // not a browser copy of the recipe. Delete legacy rich fields
                // whenever an older snapshot is refreshed.
                ...(existing.exists ? {
                    imageURL: FieldValue.delete(),
                    ingredientCount: FieldValue.delete(),
                    yields: FieldValue.delete(),
                    notes: FieldValue.delete(),
                    sourceTitle: FieldValue.delete(),
                    sourceURL: FieldValue.delete(),
                    authorName: FieldValue.delete(),
                    originalCreatorName: FieldValue.delete(),
                    ingredients: FieldValue.delete(),
                    steps: FieldValue.delete(),
                } : {}),
                ...(!existing.exists ? { createdAt: FieldValue.serverTimestamp() } : {}),
            }, { merge: true });
            if (privacyRoot.data()?.blocked === true) {
                transaction.set(privacyRoot.ref, { blocked: false, reopenedAt: FieldValue.serverTimestamp() }, { merge: true });
            }
            return true;
        });

        // Construct URL using the Hosting domain
        // New Format: /u/{username}/{recipeId} is handled by the client/rewrite,
        // but for the direct API response we can return the canonical URL
        // stored in the app or just the basic one.
        // The iOS app generates https://cauldron-f900a.web.app/u/{username}/{recipeId} locally.
        const shareUrl = `https://cauldron-f900a.web.app/recipe/${shareId}`;

        res.status(200).json(publishedShareResponse(shareId, shareUrl, published));
    } catch (error) {
        if (error instanceof StaleShareMutationError) {
            res.status(409).json({ error: 'A newer recipe sharing change superseded this request' });
            return;
        }
        if (error instanceof ShareAuthorizationError) {
            res.status(403).json({ error: 'Share capability or owner mismatch' });
            return;
        }
        logger.error('Error sharing recipe:', error);
        res.status(500).json({ error: 'Failed to create share link' });
    }
});

// Remove Recipe Share
// Kept separate from shareRecipe so publish and privacy-changing removal have
// explicit, independently testable contracts. Deleting a missing snapshot is
// intentionally successful, making client retries safe.
export const unshareRecipeV2 = onRequest(cloudAuthorizedHTTPOptions, async (req, res) => {
    if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed');
        return;
    }
    if (!await enforceMutationRateLimit(req)) {
        rejectRateLimitedMutation(res);
        return;
    }

    const sanitized = sanitizeRecipeUnshareInput(req.body ?? {});
    if (!sanitized.ok) {
        res.status(400).json({ error: sanitized.error });
        return;
    }
    const { recipeId, ownerId, identityRecordName, capability } = sanitized.value;

    try {
        if (!await verifyCloudKitAuthority(identityRecordName, ownerId, capability)) {
            throw new ShareAuthorizationError();
        }
        const suppliedHash = capabilityHash(capability);
        const mutationGeneration = await beginResourceMutation("recipe", recipeId, "unshare", suppliedHash);
        const docRef = db.collection('shared_recipes').doc(recipeId);
        await db.runTransaction(async (transaction) => {
            const mutationState = await transaction.get(resourceMutationRef("recipe", recipeId));
            const privacyRootRef = resourcePrivacyRootRef("recipe", recipeId);
            const privacyEpochRef = resourcePrivacyRef("recipe", recipeId, suppliedHash);
            const existing = await transaction.get(docRef);
            requireCurrentResourceMutation(mutationState, mutationGeneration);
            if (existing.exists && existing.data()?.ownerId !== ownerId) {
                throw new ShareAuthorizationError();
            }
            if (existing.exists) {
                transaction.delete(docRef);
            }
            transaction.set(privacyEpochRef, {
                ownerId,
                revokedCapabilityHash: suppliedHash,
                revokedAt: FieldValue.serverTimestamp(),
            });
            transaction.set(privacyRootRef, {
                ownerId,
                blocked: true,
                blockedAt: FieldValue.serverTimestamp(),
            }, { merge: true });
        });
        res.set('Cache-Control', 'no-store');
        res.status(200).json({ success: true });
    } catch (error) {
        if (error instanceof StaleShareMutationError) {
            res.status(409).json({ error: 'A newer recipe sharing change superseded this request' });
            return;
        }
        if (error instanceof ShareAuthorizationError) {
            res.status(403).json({ error: 'Share capability or owner mismatch' });
            return;
        }
        logger.error('Error removing recipe share:', error);
        res.status(500).json({ error: 'Failed to remove recipe share' });
    }
});

// Share Profile
export const shareProfileV2 = onRequest(cloudAuthorizedHTTPOptions, async (req, res) => {
    if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed');
        return;
    }
    if (!await enforceMutationRateLimit(req)) {
        rejectRateLimitedMutation(res);
        return;
    }

    try {
        const sanitized = sanitizeProfileShareInput(req.body ?? {});
        if (!sanitized.ok) {
            res.status(400).json({ error: sanitized.error });
            return;
        }
        const share = sanitized.value;
        const profileAuthority = await verifyCloudKitAuthority(
            share.identityRecordName,
            share.userId,
            share.capability,
            share.username
        );
        if (!profileAuthority || typeof profileAuthority.usernameClaimCreatedAt !== "number") {
            throw new ShareAuthorizationError();
        }
        const usernameClaimCreatedAt = profileAuthority.usernameClaimCreatedAt;
        const recipeCountSnapshot = await db.collection('shared_recipes')
            .where('ownerId', '==', share.userId)
            .count()
            .get();
        const suppliedHash = capabilityHash(share.capability);
        const mutationGeneration = await beginResourceMutation(
            "profile", share.userId, "publish", suppliedHash
        );

        const shareId = share.userId;
        const docRef = db.collection('shared_profiles').doc(shareId);

        const shareData = {
            userId: share.userId,
            ownerId: share.userId,
            username: share.username,
            displayName: share.displayName,
            profileEmoji: share.profileEmoji,
            profileColor: share.profileColor,
            recipeCount: recipeCountSnapshot.data().count,
            // Don't overwrite viewCount if it exists
        };

        // Always confirm the capability currently registered by this iCloud
        // identity so rotation revokes both publish and deletion authority.
        const usernameAliasRef = db.collection('shared_profiles').doc(share.username);
        const published = await db.runTransaction(async (transaction) => {
            const revocation = await transaction.get(shareRevocationRef(share.userId));
            const privacyRoot = await transaction.get(resourcePrivacyRootRef("profile", share.userId));
            const privacyEpoch = await transaction.get(resourcePrivacyRef("profile", share.userId, suppliedHash));
            const mutationState = await transaction.get(resourceMutationRef("profile", share.userId));
            const existing = await transaction.get(docRef);
            const usernameAlias = await transaction.get(usernameAliasRef);
            requireCurrentResourceMutation(mutationState, mutationGeneration);
            if (revocationBlocksCapability(revocation, suppliedHash)) {
                throw new ShareAuthorizationError();
            }
            if (privacyEpochBlocksCapability(privacyEpoch)) {
                throw new ShareAuthorizationError();
            }
            if (!existing.exists && !share.shouldCreate) {
                return false;
            }
            if (existing.exists && existing.data()?.ownerId !== share.userId) {
                throw new ShareAuthorizationError();
            }
            const aliasOwnerId = usernameAlias.data()?.ownerId;
            const aliasClaimCreatedAt = usernameAlias.data()?.usernameClaimCreatedAt;
            if (usernameAlias.exists && aliasOwnerId !== share.userId &&
                typeof aliasClaimCreatedAt === "number" &&
                aliasClaimCreatedAt >= usernameClaimCreatedAt) {
                throw new ShareAuthorizationError();
            }
            // CloudKit has already confirmed that this username currently belongs
            // to this user. Reassign a stale alias when a username is reused.
            transaction.set(docRef, {
                ...shareData,
                capabilityHash: suppliedHash,
                ...(existing.exists ? { profileImageURL: FieldValue.delete() } : {}),
                ...(!existing.exists ? { createdAt: FieldValue.serverTimestamp() } : {}),
                updatedAt: FieldValue.serverTimestamp(),
            }, { merge: true });
            transaction.set(usernameAliasRef, {
                ownerId: share.userId,
                userId: share.userId,
                redirectShareId: shareId,
                usernameClaimCreatedAt,
                updatedAt: FieldValue.serverTimestamp(),
            });
            if (privacyRoot.data()?.blocked === true) {
                transaction.set(privacyRoot.ref, { blocked: false, reopenedAt: FieldValue.serverTimestamp() }, { merge: true });
            }
            return true;
        });

        if (!published) {
            res.status(200).json(publishedShareResponse(
                shareId,
                `https://cauldron-f900a.web.app/profile/${shareId}`,
                false
            ));
            return;
        }

        // Remove aliases for usernames this owner no longer has. Usernames are
        // reusable in CloudKit, so retaining an old redirect would misroute the
        // next owner's profile and block them from publishing it.
        const ownerProfiles = await db.collection('shared_profiles').where('ownerId', '==', share.userId).get();
        const legacyProfiles = ownerProfiles.docs.filter((profileDoc) =>
            profileDoc.id !== shareId && profileDoc.id !== share.username
        );
        for (let index = 0; index < legacyProfiles.length; index += 400) {
            const profileChunk = legacyProfiles.slice(index, index + 400);
            await db.runTransaction(async (transaction) => {
                const revocation = await transaction.get(shareRevocationRef(share.userId));
                const mutationState = await transaction.get(resourceMutationRef("profile", share.userId));
                const currentProfiles = await Promise.all(
                    profileChunk.map((profileDoc) => transaction.get(profileDoc.ref))
                );
                if (revocationBlocksCapability(revocation, suppliedHash)) {
                    throw new ShareAuthorizationError();
                }
                requireCurrentResourceMutation(mutationState, mutationGeneration);
                for (const profileDoc of currentProfiles) {
                    if (!profileDoc.exists || profileDoc.data()?.ownerId !== share.userId) {
                        continue;
                    }
                    transaction.delete(profileDoc.ref);
                }
            });
        }

        const shareUrl = `https://cauldron-f900a.web.app/profile/${shareId}`;

        res.status(200).json(publishedShareResponse(shareId, shareUrl, true));
    } catch (error) {
        if (error instanceof StaleShareMutationError) {
            res.status(409).json({ error: 'A newer profile sharing change superseded this request' });
            return;
        }
        if (error instanceof ShareAuthorizationError) {
            res.status(403).json({ error: 'Share capability or owner mismatch' });
            return;
        }
        logger.error('Error sharing profile:', error);
        res.status(500).json({ error: 'Failed to create share link' });
    }
});

export const unshareProfileV2 = onRequest(cloudAuthorizedHTTPOptions, async (req, res) => {
    if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed');
        return;
    }
    if (!await enforceMutationRateLimit(req)) {
        rejectRateLimitedMutation(res);
        return;
    }

    const sanitized = sanitizeProfileUnshareInput(req.body ?? {});
    if (!sanitized.ok) {
        res.status(400).json({ error: sanitized.error });
        return;
    }
    const { userId, identityRecordName, capability } = sanitized.value;

    try {
        if (!await verifyCloudKitAuthority(identityRecordName, userId, capability)) {
            throw new ShareAuthorizationError();
        }
        const suppliedHash = capabilityHash(capability);
        const mutationGeneration = await beginResourceMutation("profile", userId, "unshare", suppliedHash);
        await db.runTransaction(async (transaction) => {
            const mutationState = await transaction.get(resourceMutationRef("profile", userId));
            requireCurrentResourceMutation(mutationState, mutationGeneration);
            transaction.set(resourcePrivacyRef("profile", userId, suppliedHash), {
                ownerId: userId,
                revokedCapabilityHash: suppliedHash,
                revokedAt: FieldValue.serverTimestamp(),
            });
            transaction.set(resourcePrivacyRootRef("profile", userId), {
                ownerId: userId,
                blocked: true,
                blockedAt: FieldValue.serverTimestamp(),
            }, { merge: true });
        });
        const ownerProfiles = await db.collection('shared_profiles').where('ownerId', '==', userId).get();
        for (let index = 0; index < ownerProfiles.docs.length; index += 400) {
            const profileChunk = ownerProfiles.docs.slice(index, index + 400);
            await db.runTransaction(async (transaction) => {
                const mutationState = await transaction.get(resourceMutationRef("profile", userId));
                const currentProfiles = await Promise.all(
                    profileChunk.map((profileDoc) => transaction.get(profileDoc.ref))
                );
                requireCurrentResourceMutation(mutationState, mutationGeneration);
                for (const profileDoc of currentProfiles) {
                    if (profileDoc.exists && profileDoc.data()?.ownerId === userId) {
                        transaction.delete(profileDoc.ref);
                    }
                }
            });
        }
        res.set('Cache-Control', 'no-store');
        res.status(200).json({ success: true });
    } catch (error) {
        if (error instanceof StaleShareMutationError) {
            res.status(409).json({ error: 'A newer profile sharing change superseded this request' });
            return;
        }
        if (error instanceof ShareAuthorizationError) {
            res.status(403).json({ error: 'Share capability or owner mismatch' });
            return;
        }
        logger.error('Error removing profile share:', error);
        res.status(500).json({ error: 'Failed to remove profile share' });
    }
});

export const unshareAccountV2 = onRequest(cloudAuthorizedHTTPOptions, async (req, res) => {
    if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed');
        return;
    }
    if (!await enforceMutationRateLimit(req)) {
        rejectRateLimitedMutation(res);
        return;
    }
    const sanitized = sanitizeAccountUnshareInput(req.body ?? {});
    if (!sanitized.ok) {
        res.status(400).json({ error: sanitized.error });
        return;
    }
    const { userId, identityRecordName, capability } = sanitized.value;

    try {
        if (!await verifyCloudKitAuthority(identityRecordName, userId, capability)) {
            throw new ShareAuthorizationError();
        }
        const suppliedHash = capabilityHash(capability);
        const accountGeneration = await beginAccountMutation(userId, "unshare", suppliedHash);
        await db.runTransaction(async (transaction) => {
            const state = await transaction.get(accountMutationRef(userId));
            requireCurrentResourceMutation(state, accountGeneration);
            transaction.set(shareRevocationRef(userId), {
                ownerId: userId,
                revokedCapabilityHash: suppliedHash,
                revokedAt: FieldValue.serverTimestamp(),
            });
        });
        await deleteAllSnapshotsForOwnerAtGeneration(userId, accountGeneration);
        res.set('Cache-Control', 'no-store');
        res.status(200).json({ success: true });
    } catch (error) {
        if (error instanceof StaleShareMutationError) {
            res.status(409).json({ error: 'A newer account sharing change superseded this request' });
            return;
        }
        if (error instanceof ShareAuthorizationError) {
            res.status(403).json({ error: 'CloudKit identity authorization failed' });
            return;
        }
        logger.error('Error removing account shares:', error);
        res.status(500).json({ error: 'Failed to remove account shares' });
    }
});

/// Re-enables publication only after the client has rotated the CloudKit-backed
/// capability. The durable revocation epoch remains in Firestore so a request
/// authorized under the retired credential can never commit after restoration.
export const restoreAccountSharingV2 = onRequest(cloudAuthorizedHTTPOptions, async (req, res) => {
    if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed');
        return;
    }
    if (!await enforceMutationRateLimit(req)) {
        rejectRateLimitedMutation(res);
        return;
    }
    const sanitized = sanitizeAccountUnshareInput(req.body ?? {});
    if (!sanitized.ok) {
        res.status(400).json({ error: sanitized.error });
        return;
    }
    const { userId, identityRecordName, capability } = sanitized.value;
    try {
        if (!await verifyCloudKitAuthority(identityRecordName, userId, capability)) {
            throw new ShareAuthorizationError();
        }
        const suppliedHash = capabilityHash(capability);
        const accountGeneration = await beginAccountMutation(userId, "restore", suppliedHash);
        await deleteAllSnapshotsForOwnerAtGeneration(userId, accountGeneration);
        await db.runTransaction(async (transaction) => {
            const state = await transaction.get(accountMutationRef(userId));
            const revocationRef = shareRevocationRef(userId);
            const revocation = await transaction.get(revocationRef);
            requireCurrentResourceMutation(state, accountGeneration);
            const revokedHash = revocation.data()?.revokedCapabilityHash;
            if (!revocation.exists || typeof revokedHash !== "string" || revokedHash === suppliedHash) {
                throw new ShareAuthorizationError();
            }
            transaction.set(revocationRef, {
                ownerId: userId,
                revokedCapabilityHash: revokedHash,
                restoredCapabilityHash: suppliedHash,
                restoredAt: FieldValue.serverTimestamp(),
            });
        });
        res.set('Cache-Control', 'no-store');
        res.status(200).json({ success: true });
    } catch (error) {
        if (error instanceof StaleShareMutationError) {
            res.status(409).json({ error: 'A newer account sharing change superseded this request' });
            return;
        }
        if (error instanceof ShareAuthorizationError) {
            res.status(403).json({ error: 'CloudKit identity authorization failed' });
            return;
        }
        logger.error('Error restoring account sharing:', error);
        res.status(500).json({ error: 'Failed to restore account sharing' });
    }
});

// Share Collection
export const shareCollectionV2 = onRequest(cloudAuthorizedHTTPOptions, async (req, res) => {
    if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed');
        return;
    }
    if (!await enforceMutationRateLimit(req)) {
        rejectRateLimitedMutation(res);
        return;
    }

    try {
        const sanitized = sanitizeCollectionShareInput(req.body ?? {});
        if (!sanitized.ok) {
            res.status(400).json({ error: sanitized.error });
            return;
        }
        const share = sanitized.value;
        if (!await verifyCloudKitAuthority(
            share.identityRecordName,
            share.ownerId,
            share.capability
        )) {
            throw new ShareAuthorizationError();
        }
        if (!await verifyCloudKitResourceAuthority(
            share.collectionId,
            "Collection",
            "userId",
            share.ownerId,
            share.identityRecordName
        )) {
            throw new ShareAuthorizationError();
        }
        const suppliedHash = capabilityHash(share.capability);
        const mutationGeneration = await beginResourceMutation(
            "collection", share.collectionId, "publish", suppliedHash
        );

        const shareId = share.collectionId;

        const shareData = {
            collectionId: share.collectionId,
            ownerId: share.ownerId,
            title: share.title,
            recipeCount: share.recipeCount,
            recipeIds: share.recipeIds,
        };

        const docRef = db.collection('shared_collections').doc(shareId);
        const published = await db.runTransaction(async (transaction) => {
            const revocation = await transaction.get(shareRevocationRef(share.ownerId));
            const privacyRoot = await transaction.get(resourcePrivacyRootRef("collection", share.collectionId));
            const privacyEpoch = await transaction.get(resourcePrivacyRef("collection", share.collectionId, suppliedHash));
            const mutationState = await transaction.get(resourceMutationRef("collection", share.collectionId));
            const existing = await transaction.get(docRef);
            requireCurrentResourceMutation(mutationState, mutationGeneration);
            if (revocationBlocksCapability(revocation, suppliedHash) ||
                privacyEpochBlocksCapability(privacyEpoch) ||
                (existing.exists && existing.data()?.ownerId !== share.ownerId)) {
                throw new ShareAuthorizationError();
            }
            if (!existing.exists && !share.shouldCreate) {
                return false;
            }
            transaction.set(docRef, {
                ...shareData,
                capabilityHash: suppliedHash,
                ...(existing.exists ? { coverImageURL: FieldValue.delete() } : {}),
                ...(!existing.exists ? { createdAt: FieldValue.serverTimestamp() } : {}),
                updatedAt: FieldValue.serverTimestamp(),
            }, { merge: true });
            if (privacyRoot.data()?.blocked === true) {
                transaction.set(privacyRoot.ref, { blocked: false, reopenedAt: FieldValue.serverTimestamp() }, { merge: true });
            }
            return true;
        });

        const shareUrl = `https://cauldron-f900a.web.app/collection/${shareId}`;

        res.status(200).json(publishedShareResponse(shareId, shareUrl, published));
    } catch (error) {
        if (error instanceof StaleShareMutationError) {
            res.status(409).json({ error: 'A newer collection sharing change superseded this request' });
            return;
        }
        if (error instanceof ShareAuthorizationError) {
            res.status(403).json({ error: 'Share capability or owner mismatch' });
            return;
        }
        logger.error('Error sharing collection:', error);
        res.status(500).json({ error: 'Failed to create share link' });
    }
});

export const unshareCollectionV2 = onRequest(cloudAuthorizedHTTPOptions, async (req, res) => {
    if (req.method !== 'POST') {
        res.status(405).send('Method Not Allowed');
        return;
    }
    if (!await enforceMutationRateLimit(req)) {
        rejectRateLimitedMutation(res);
        return;
    }
    const sanitized = sanitizeCollectionUnshareInput(req.body ?? {});
    if (!sanitized.ok) {
        res.status(400).json({ error: sanitized.error });
        return;
    }
    const { collectionId, ownerId, identityRecordName, capability } = sanitized.value;
    try {
        if (!await verifyCloudKitAuthority(identityRecordName, ownerId, capability)) {
            throw new ShareAuthorizationError();
        }
        const suppliedHash = capabilityHash(capability);
        const mutationGeneration = await beginResourceMutation(
            "collection", collectionId, "unshare", suppliedHash
        );
        const docRef = db.collection('shared_collections').doc(collectionId);
        await db.runTransaction(async (transaction) => {
            const mutationState = await transaction.get(resourceMutationRef("collection", collectionId));
            const privacyRootRef = resourcePrivacyRootRef("collection", collectionId);
            const privacyEpochRef = resourcePrivacyRef("collection", collectionId, suppliedHash);
            const existing = await transaction.get(docRef);
            requireCurrentResourceMutation(mutationState, mutationGeneration);
            if (existing.exists && existing.data()?.ownerId !== ownerId) {
                throw new ShareAuthorizationError();
            }
            if (existing.exists) {
                transaction.delete(docRef);
            }
            transaction.set(privacyEpochRef, {
                ownerId,
                revokedCapabilityHash: suppliedHash,
                revokedAt: FieldValue.serverTimestamp(),
            });
            transaction.set(privacyRootRef, {
                ownerId,
                blocked: true,
                blockedAt: FieldValue.serverTimestamp(),
            }, { merge: true });
        });
        res.set('Cache-Control', 'no-store');
        res.status(200).json({ success: true });
    } catch (error) {
        if (error instanceof StaleShareMutationError) {
            res.status(409).json({ error: 'A newer collection sharing change superseded this request' });
            return;
        }
        if (error instanceof ShareAuthorizationError) {
            res.status(403).json({ error: 'Share capability or owner mismatch' });
            return;
        }
        logger.error('Error removing collection share:', error);
        res.status(500).json({ error: 'Failed to remove collection share' });
    }
});

// Generic Data Fetcher
export const api = onRequest(publicReadHTTPOptions, async (req, res) => {
    res.set(publicSecurityHeaders());
    res.set("Cache-Control", "private, no-store, max-age=0");
    if (!await enforcePublicReadRateLimit(req)) {
        rejectRateLimitedRead(res);
        return;
    }
    // Handle routing manually for /api/data/:type/:shareId
    // Expected path: /data/recipe/12345678
    const rawPathParts = req.path.split('/').filter(p => p);
    const pathParts = rawPathParts[0] === "api" ? rawPathParts.slice(1) : rawPathParts;

    // Check if this is a data request
    if (pathParts[0] === 'data' && pathParts.length === 3) {
        const type = pathParts[1];
        const shareId = pathParts[2];

        if (req.method !== 'GET') {
            res.status(405).json({ error: 'Method not allowed' });
            return;
        }

        try {
            const collectionMap: { [key: string]: string } = {
                recipe: 'shared_recipes',
                profile: 'shared_profiles',
                collection: 'shared_collections',
            };

            const collectionName = collectionMap[type];
            if (!collectionName) {
                res.status(400).json({ error: 'Invalid share type' });
                return;
            }

            let doc = await db.collection(collectionName).doc(shareId).get();
            if (!doc.exists) {
                res.status(404).json({ error: 'Share not found' });
                return;
            }

            if (type === 'profile') {
                const redirectShareId = doc.data()?.redirectShareId;
                if (typeof redirectShareId === 'string' && isValidUUID(redirectShareId)) {
                    doc = await db.collection(collectionName).doc(redirectShareId).get();
                    if (!doc.exists) {
                        res.status(404).json({ error: 'Share not found' });
                        return;
                    }
                }
            }

            const rawData = doc.data() ?? {};
            if (await isShareRevoked(rawData.ownerId)) {
                res.status(404).json({ error: 'Share not found' });
                return;
            }
            const resourceId = type === "recipe" ? rawData.recipeId :
                type === "profile" ? rawData.userId : rawData.collectionId;
            if (typeof resourceId !== "string" || !isValidUUID(resourceId) ||
                await isResourcePrivacyBlocked(type as "recipe" | "profile" | "collection", resourceId)) {
                res.status(404).json({ error: 'Share not found' });
                return;
            }
            let publicData: Record<string, unknown>;
            if (type === "recipe") {
                const sanitized = sanitizeStoredRecipeShareInput(rawData);
                if (!sanitized.ok) {
                    res.status(404).json({ error: "Share not found" });
                    return;
                }
                publicData = {
                    recipeId: sanitized.value.recipeId,
                    ownerId: sanitized.value.ownerId,
                    title: sanitized.value.title,
                    totalMinutes: sanitized.value.totalMinutes,
                    tags: sanitized.value.tags,
                };
            } else if (type === "profile") {
                const sanitized = sanitizeStoredProfileShareInput(rawData);
                if (!sanitized.ok) {
                    res.status(404).json({ error: "Share not found" });
                    return;
                }
                const { identityRecordName: _identity, capability: _capability, shouldCreate: _create, ...snapshot } = sanitized.value;
                publicData = { ...snapshot, ownerId: sanitized.value.userId };
            } else {
                const sanitized = sanitizeStoredCollectionShareInput(rawData);
                if (!sanitized.ok) {
                    res.status(404).json({ error: "Share not found" });
                    return;
                }
                const { identityRecordName: _identity, capability: _capability, shouldCreate: _create, ...snapshot } = sanitized.value;
                publicData = snapshot;
            }
            if (type === 'profile' && isValidUUID(rawData.ownerId)) {
                const recipeCount = await db.collection('shared_recipes')
                    .where('ownerId', '==', rawData.ownerId)
                    .count()
                    .get();
                publicData.recipeCount = recipeCount.data().count;
            }
            res.status(200).json({
                success: true,
                data: publicData,
            });
        } catch (error) {
            logger.error('Error fetching share data:', error);
            res.status(500).json({ error: 'Failed to fetch share data' });
        }
        return;
    }

    // Handle legacy share endpoints if they come through /api prefix
    if (pathParts[0] === 'share') {
        if (pathParts[1] === 'recipe') {
            // Forward to shareRecipe function
            // Note: In a real deployment, we'd use rewrites, but for simplicity in this single function:
            // We can't easily invoke another function here without HTTP.
            // So we rely on firebase.json rewrites to map /api/share/recipe -> shareRecipe function directly
            res.status(404).send('Use specific function endpoints');
            return;
        }
    }

    res.status(404).send('Not Found');
});

// --- Preview Pages ---

// --- Preview Pages ---

export function generatePreviewHtml(
    title: string,
    description: string,
    imageURL: string | null,
    canonicalURL: string,
    appURL: string,
    downloadURL: string,
    avatarEmoji: string | null = null,
    avatarColor: string | null = null
): string {
    // Use default icon for meta tags if no specific image is available
    const safeTitle = escapeHtml(title);
    const safeDescription = escapeHtml(description);
    const safeCanonicalURL = escapeHtml(canonicalURL);
    const safeAppURL = escapeHtml(appURL);
    const safeDownloadURL = escapeHtml(downloadURL);
    const safeAvatarEmoji = avatarEmoji ? escapeHtml(avatarEmoji) : "";
    const safeAvatarColor = avatarColor && /^#[0-9a-f]{6}$/i.test(avatarColor)
        ? avatarColor
        : "#FF9933";
    const metaImageURL = safeImageURL(imageURL) || 'https://cauldron-f900a.web.app/social-card.png';
    const safeMetaImageURL = escapeHtml(metaImageURL);

    return `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${safeTitle} - Cauldron</title>
    <meta name="description" content="${safeDescription}">
    <link rel="canonical" href="${safeCanonicalURL}">

    <!-- Open Graph / Facebook -->
    <meta property="og:type" content="article">
    <meta property="og:title" content="${safeTitle}">
    <meta property="og:description" content="${safeDescription}">
    <meta property="og:image" content="${safeMetaImageURL}">
    <meta property="og:url" content="${safeCanonicalURL}">
    <meta property="og:site_name" content="Cauldron">

    <!-- Twitter -->
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="${safeTitle}">
    <meta name="twitter:description" content="${safeDescription}">
    <meta name="twitter:image" content="${safeMetaImageURL}">
    <meta name="twitter:app:name:iphone" content="Cauldron">
    <meta name="twitter:app:id:iphone" content="6754004943">

    <style>
        :root {
            --cauldron-orange: #FF9933;
            --bg-color: #F2F2F7;
            --card-bg: #FFFFFF;
            --text-primary: #000000;
            --text-secondary: #5F6368;
            --shadow-color: rgba(0,0,0,0.1);
            --border-color: rgba(0,0,0,0.05);
            --button-text: #2B1600;
            --secondary-button-bg: rgba(0, 0, 0, 0.05);
            --secondary-button-text: #A53E13;
        }

        @media (prefers-color-scheme: dark) {
            :root {
                --bg-color: #000000;
                --card-bg: #1C1C1E;
                --text-primary: #FFFFFF;
                --text-secondary: #B8B8BE;
                --shadow-color: rgba(0,0,0,0.5);
                --border-color: #333;
                --secondary-button-bg: rgba(255, 255, 255, 0.1);
                --secondary-button-text: #FFB083;
            }
        }

        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            background-color: var(--bg-color);
            color: var(--text-primary);
            min-height: 100vh;
            display: flex;
            align-items: flex-start;
            justify-content: center;
            padding: max(20px, env(safe-area-inset-top)) max(20px, env(safe-area-inset-right)) max(20px, env(safe-area-inset-bottom)) max(20px, env(safe-area-inset-left));
            transition: background-color 0.3s ease, color 0.3s ease;
        }

        .container {
            background: var(--card-bg);
            border-radius: 24px;
            padding: 40px;
            max-width: 480px;
            width: 100%;
            box-shadow: 0 20px 60px var(--shadow-color);
            text-align: center;
            border: 1px solid var(--border-color);
            transition: background-color 0.3s ease, border-color 0.3s ease;
            margin-block: auto;
        }

        .logo {
            width: 80px;
            height: 80px;
            margin: 0 auto 24px auto;
            background-size: contain;
            background-repeat: no-repeat;
            background-position: center;
            background-image: url('/icon-light.svg');
        }

        .logo.avatar {
            align-items: center;
            background: color-mix(in srgb, ${safeAvatarColor} 18%, transparent);
            border: 2px solid color-mix(in srgb, ${safeAvatarColor} 42%, transparent);
            border-radius: 50%;
            display: flex;
            font-size: 38px;
            justify-content: center;
        }

        @media (prefers-color-scheme: dark) {
            .logo {
                background-image: url('/icon-dark.svg');
            }
        }

        .preview-image {
            width: 100%;
            height: 320px;
            object-fit: cover;
            border-radius: 16px;
            margin-bottom: 24px;
            box-shadow: 0 8px 24px var(--shadow-color);
            background-color: var(--secondary-button-bg);
        }

        h1 {
            font-size: 28px;
            margin-bottom: 12px;
            color: var(--text-primary);
            font-weight: 700;
            line-height: 1.2;
        }

        .description {
            font-size: 17px;
            color: var(--text-secondary);
            margin-bottom: 32px;
            line-height: 1.5;
        }

        .button {
            display: block;
            width: 100%;
            background: var(--cauldron-orange);
            color: var(--button-text);
            padding: 16px;
            border-radius: 14px;
            text-decoration: none;
            font-weight: 600;
            font-size: 17px;
            margin-bottom: 12px;
            transition: transform 0.2s, opacity 0.2s;
            cursor: pointer;
            border: none;
        }

        .button:active {
            transform: scale(0.98);
            opacity: 0.9;
        }

        .button.secondary {
            background: var(--secondary-button-bg);
            color: var(--secondary-button-text);
        }
        @media (prefers-reduced-motion: reduce) { * { transition: none !important; } }
    </style>

</head>
<body>
    <div class="container">
        <div class="logo${safeAvatarEmoji ? " avatar" : ""}" aria-hidden="true">${safeAvatarEmoji}</div>
        
        ${metaImageURL !== 'https://cauldron-f900a.web.app/social-card.png' ? `<img src="${safeMetaImageURL}" alt="${safeTitle}" class="preview-image" onerror="this.style.display='none'">` : ''}
        
        <h1>${safeTitle}</h1>
        <p class="description">${safeDescription}</p>
        
        <a href="${safeAppURL}" class="button">Open in Cauldron</a>
        <a href="${safeDownloadURL}" class="button secondary">Download App</a>
    </div>
</body>
</html>
    `;
}

type RecipeIndexPageOptions = {
    handle?: string;
    title: string;
    description: string;
    canonicalURL: string;
    appURL: string;
    downloadURL: string;
    recipes: WebRecipeIndexItem[];
    totalRecipeCount: number;
    hasMoreRecipes?: boolean;
    openGraphType?: "profile" | "website";
    avatarEmoji?: string | null;
    avatarColor?: string | null;
};

function compactPageStyles(): string {
    return `<style>
        :root { color-scheme:light dark; --paper:#F6F1EA; --ink:#1C1C1E; --muted:#6E6E73; --accent:#FF9933; --accent-text:#995100; --soft:#FFFFFF; }
        @media (prefers-color-scheme:dark) { :root { --paper:#18120D; --ink:#F2F2F7; --muted:#AEAEB2; --accent:#FF9933; --accent-text:#FFB45F; --soft:#262220; } }
        * { box-sizing:border-box; }
        body { margin:0; min-height:100vh; background:var(--paper); color:var(--ink); font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif; -webkit-font-smoothing:antialiased; }
        .bar,main { width:min(960px,calc(100% - 64px)); margin-inline:auto; }
        .bar { min-height:82px; display:flex; align-items:center; }
        .brand { display:flex; align-items:center; gap:10px; }
        .brand picture,.brand img { width:32px; height:32px; display:block; }
        .brand span { font-family:"New York",ui-serif,"Iowan Old Style",Palatino,Georgia,serif; font-size:21px; font-weight:700; letter-spacing:-.02em; }
        main { margin-top:58px; margin-bottom:110px; }
        .intro { max-width:720px; }
        .identity { display:flex; align-items:center; gap:18px; }
        .identity-text { min-width:0; }
        .profile-avatar { width:58px; height:58px; flex:0 0 58px; display:grid; place-items:center; border-radius:50%; background:color-mix(in srgb,var(--avatar-color) 18%,transparent); font-size:28px; }
        h1 { margin:0; font-family:"New York",ui-serif,"Iowan Old Style",Palatino,Georgia,serif; font-size:clamp(44px,7vw,68px); line-height:1; letter-spacing:-.04em; overflow-wrap:anywhere; }
        .handle { margin:9px 0 0; color:var(--muted); font-size:14px; font-weight:600; }
        .description { max-width:48ch; margin:18px 0 0; color:var(--muted); font-size:16px; line-height:1.55; }
        .meta { display:flex; flex-wrap:wrap; gap:10px 16px; margin:22px 0 0; padding:0; color:var(--muted); list-style:none; font-size:13px; }
        .action { min-height:44px; width:max-content; margin-top:28px; display:inline-flex; align-items:center; padding:10px 16px; border-radius:999px; color:#2B1600; background:var(--accent); font-size:14px; font-weight:750; text-decoration:none; }
        .download-action { min-height:44px; width:max-content; margin:28px 0 0 14px; display:inline-flex; align-items:center; color:var(--muted); font-size:13px; font-weight:650; text-decoration:none; }
        .shelf { margin-top:68px; }
        .count { margin:0 0 18px; color:var(--muted); font-size:13px; font-weight:650; }
        .recipe-list { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:34px 20px; margin:0; padding:0; list-style:none; }
        .recipe-list li { min-width:0; }
        .recipe-row { display:block; color:inherit; text-decoration:none; }
        .recipe-media { position:relative; aspect-ratio:4/3; display:grid; place-items:center; overflow:hidden; border-radius:18px; background:color-mix(in srgb,var(--accent) 10%,var(--soft)); }
        .recipe-photo { width:100%; height:100%; display:block; object-fit:cover; transition:transform .24s ease; }
        .recipe-placeholder,.recipe-placeholder img { width:38px; height:38px; display:block; opacity:.7; }
        .recipe-copy { display:block; padding:12px 2px 0; }
        .recipe-name { display:block; font-family:"New York",ui-serif,"Iowan Old Style",Palatino,Georgia,serif; font-size:20px; font-weight:650; line-height:1.2; overflow-wrap:anywhere; }
        .recipe-meta { min-height:19px; display:flex; align-items:center; gap:9px; margin-top:7px; color:var(--muted); font-size:12px; font-weight:620; }
        .recipe-tag { --tag-color:#FF9933; --tag-color-dark:#FF9933; display:inline-flex; align-items:center; gap:4px; color:color-mix(in srgb,var(--tag-color) 72%,#3A210A); }
        @media (prefers-color-scheme:dark) { .recipe-tag { color:color-mix(in srgb,var(--tag-color-dark) 74%,white); } }
        .empty { margin:0; color:var(--muted); font-size:16px; }
        .compact-recipe { max-width:720px; }
        .compact-recipe .meta { margin-top:24px; }
        a:focus-visible { outline:3px solid color-mix(in srgb,var(--accent) 78%,white); outline-offset:4px; }
        @media (hover:hover) { .recipe-row:hover .recipe-name { color:var(--accent-text); } .recipe-row:hover .recipe-photo { transform:scale(1.025); } .action:hover { filter:brightness(.97); } }
        @media (max-width:760px) { .recipe-list { grid-template-columns:repeat(2,minmax(0,1fr)); } }
        @media (max-width:520px) { .bar,main { width:min(calc(100% - 32px),560px); } .bar { min-height:68px; } main { margin-top:30px; margin-bottom:72px; } .recipe-list { grid-template-columns:1fr; gap:28px; } .recipe-media { aspect-ratio:16/10; } .shelf { margin-top:58px; } .identity { align-items:flex-start; } }
        @media print { :root { --paper:#fff; --ink:#000; --muted:#444; --accent-text:#7A330E; } .bar,.action,.download-action { display:none; } main { width:100%; margin:0; } .shelf { margin-top:48px; } }
    </style>`;
}

function compactPageHead(title: string, description: string, canonicalURL: string, openGraphType: "profile" | "website" = "website"): string {
    const safeTitle = escapeHtml(title);
    const safeDescription = escapeHtml(description);
    const safeCanonicalURL = escapeHtml(canonicalURL);
    return `<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"><meta name="theme-color" content="#F6F1EA" media="(prefers-color-scheme: light)"><meta name="theme-color" content="#18120D" media="(prefers-color-scheme: dark)"><title>${safeTitle} · Cauldron</title><meta name="description" content="${safeDescription}"><link rel="canonical" href="${safeCanonicalURL}"><meta property="og:type" content="${openGraphType}"><meta property="og:title" content="${safeTitle}"><meta property="og:description" content="${safeDescription}"><meta property="og:image" content="https://cauldron-f900a.web.app/social-card.png"><meta property="og:url" content="${safeCanonicalURL}"><meta property="og:site_name" content="Cauldron"><meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="${safeTitle}"><meta name="twitter:description" content="${safeDescription}"><meta name="twitter:image" content="https://cauldron-f900a.web.app/social-card.png"><meta name="apple-itunes-app" content="app-id=6754004943, app-argument=${safeCanonicalURL}">${compactPageStyles()}`;
}

function compactBrandHeader(): string {
    return `<header class="bar"><div class="brand"><picture><source media="(prefers-color-scheme: dark)" srcset="/icon-small-dark.svg"><img src="/icon-small-light.svg" alt="" aria-hidden="true"></picture><span>Cauldron</span></div></header>`;
}

function appOpenFallbackScript(elementId: string, appURL: string): string {
    const safeElementId = JSON.stringify(elementId).replace(/</g, "\\u003c");
    const safeAppURL = JSON.stringify(appURL).replace(/</g, "\\u003c");
    // Do not automatically redirect to the App Store. iOS may keep Safari's
    // page visible briefly while presenting the system confirmation dialog;
    // a timer-based fallback then steals focus back from an installed app.
    // The page's explicit download action remains the unambiguous fallback.
    return `<script>(function(){var button=document.getElementById(${safeElementId});if(!button)return;var appURL=${safeAppURL};button.addEventListener("click",function(event){event.preventDefault();window.location.assign(appURL);});})();</script>`;
}

export function generatePublicStatusPageHtml(title: string, message: string): string {
    const safeTitle = escapeHtml(title);
    const safeMessage = escapeHtml(message);
    return `<!DOCTYPE html><html lang="en"><head>${compactPageHead(title, message, "https://cauldron-f900a.web.app/")}</head><body>${compactBrandHeader()}<main><article class="compact-recipe"><h1>${safeTitle}</h1><p class="description">${safeMessage}</p></article></main></body></html>`;
}

export function generateCompactRecipePageHtml(
    recipe: SanitizedRecipeShare,
    canonicalURL: string,
    appURL: string,
    downloadURL: string
): string {
    const description = `${recipe.title}, shared from Cauldron.`;
    const metadata = [
        recipe.totalMinutes ? `${recipe.totalMinutes} min` : null,
        ...recipe.tags.slice(0, 3),
    ].filter((value): value is string => Boolean(value));
    const metaHTML = metadata.map((value) => `<li>${escapeHtml(value)}</li>`).join("");
    return `<!DOCTYPE html><html lang="en"><head>${compactPageHead(recipe.title, description, canonicalURL)}</head><body>${compactBrandHeader()}<main><article class="compact-recipe"><h1>${escapeHtml(recipe.title)}</h1>${metaHTML ? `<ul class="meta" aria-label="Recipe details">${metaHTML}</ul>` : ""}<a class="action" id="openCompactRecipe" href="${escapeHtml(appURL)}">Open in Cauldron</a><a class="download-action" href="${escapeHtml(downloadURL)}">Get the app</a></article></main>${appOpenFallbackScript("openCompactRecipe", appURL)}</body></html>`;
}

function formatWebQuantityValue(value: number): string {
    const whole = Math.floor(value);
    const fraction = value - whole;
    const fractions: Array<[number, string]> = [
        [0.25, "¼"], [1 / 3, "⅓"], [0.5, "½"], [2 / 3, "⅔"], [0.75, "¾"],
    ];
    const match = fractions.find(([candidate]) => Math.abs(fraction - candidate) < 0.02);
    if (match) {
        return whole > 0 ? `${whole} ${match[1]}` : match[1];
    }
    return Math.abs(fraction) < 0.01 ? `${whole}` : value.toFixed(2).replace(/0+$/, "").replace(/\.$/, "");
}

function formatWebQuantity(quantity: WebRecipeQuantity): string {
    const unitNames: Record<string, [string, string]> = {
        tsp: ["teaspoon", "teaspoons"], tbsp: ["tablespoon", "tablespoons"],
        "fl oz": ["fluid ounce", "fluid ounces"], cup: ["cup", "cups"], pint: ["pint", "pints"],
        quart: ["quart", "quarts"], gallon: ["gallon", "gallons"], ml: ["ml", "ml"],
        L: ["liter", "liters"], oz: ["ounce", "ounces"], lb: ["pound", "pounds"],
        g: ["g", "g"], kg: ["kg", "kg"], piece: ["piece", "pieces"], pinch: ["pinch", "pinches"],
        dash: ["dash", "dashes"], whole: ["whole", "whole"], clove: ["clove", "cloves"],
        bunch: ["bunch", "bunches"], can: ["can", "cans"], package: ["package", "packages"],
    };
    const upper = quantity.upperValue;
    const amount = upper === null
        ? formatWebQuantityValue(quantity.value)
        : `${formatWebQuantityValue(quantity.value)}–${formatWebQuantityValue(upper)}`;
    const unit = unitNames[quantity.unit] ?? [quantity.unit, quantity.unit];
    const shouldPluralize = (upper ?? quantity.value) !== 1;
    return `${amount} ${unit[shouldPluralize ? 1 : 0]}`.trim();
}

export function recipeSocialImageURL(canonicalURL: string): string {
    return `${canonicalURL.replace(/\/$/, "")}/social-card.png`;
}

export function detectedImageContentType(bytes: Uint8Array): string | null {
    if (bytes.length >= 3 && bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) {
        return "image/jpeg";
    }
    if (bytes.length >= 8 &&
        bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47 &&
        bytes[4] === 0x0D && bytes[5] === 0x0A && bytes[6] === 0x1A && bytes[7] === 0x0A) {
        return "image/png";
    }
    if (bytes.length >= 12 &&
        Buffer.from(bytes.subarray(0, 4)).toString("ascii") === "RIFF" &&
        Buffer.from(bytes.subarray(8, 12)).toString("ascii") === "WEBP") {
        return "image/webp";
    }
    return null;
}

function recipePageHead(recipe: WebRecipeContent, description: string, canonicalURL: string): string {
    const title = escapeHtml(recipe.title);
    const safeDescription = escapeHtml(description);
    const safeCanonicalURL = escapeHtml(canonicalURL);
    // Never expose CloudKit's short-lived signed asset URL to social crawlers.
    // This stable same-origin endpoint refreshes the current public asset and
    // falls back to Cauldron's branded card when no compatible photo exists.
    const previewImage = escapeHtml(recipeSocialImageURL(canonicalURL));
    const previewImageAlt = escapeHtml(`${recipe.title} on Cauldron`);
    const structuredData = JSON.stringify({
        "@context": "https://schema.org",
        "@type": "Recipe",
        name: recipe.title,
        image: recipe.imageURL ? [recipe.imageURL] : undefined,
        recipeYield: recipe.yields ?? undefined,
        totalTime: recipe.totalMinutes ? `PT${recipe.totalMinutes}M` : undefined,
        recipeCategory: recipe.tags[0],
        keywords: recipe.tags.join(", "),
        recipeIngredient: recipe.ingredients.map((ingredient) => {
            const quantities = [ingredient.quantity, ...ingredient.additionalQuantities]
                .filter((quantity): quantity is WebRecipeQuantity => quantity !== null)
                .map(formatWebQuantity)
                .join(" + ");
            return [quantities, ingredient.name, ingredient.note ? `(${ingredient.note})` : null]
                .filter(Boolean).join(" ");
        }),
        recipeInstructions: recipe.steps.map((step) => ({ "@type": "HowToStep", text: step.text })),
    }).replace(/</g, "\\u003c");
    return `<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"><meta name="theme-color" content="#F6F1EA"><title>${title} · Cauldron</title><meta name="description" content="${safeDescription}"><link rel="canonical" href="${safeCanonicalURL}"><meta property="og:type" content="article"><meta property="og:title" content="${title}"><meta property="og:description" content="${safeDescription}"><meta property="og:image" content="${previewImage}"><meta property="og:image:secure_url" content="${previewImage}"><meta property="og:image:alt" content="${previewImageAlt}"><meta property="og:url" content="${safeCanonicalURL}"><meta property="og:site_name" content="Cauldron"><meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="${title}"><meta name="twitter:description" content="${safeDescription}"><meta name="twitter:image" content="${previewImage}"><meta name="twitter:image:alt" content="${previewImageAlt}"><meta name="apple-itunes-app" content="app-id=6754004943, app-argument=${safeCanonicalURL}"><script type="application/ld+json">${structuredData}</script>`;
}

export const recipeCategoryPresentation: Readonly<Record<string, Readonly<{
    emoji: string;
    light: string;
    dark: string;
}>>> = {
    Breakfast: { emoji: "🍳", light: "#FF9500", dark: "#FF9F0A" },
    Lunch: { emoji: "🥪", light: "#007AFF", dark: "#0A84FF" },
    Dinner: { emoji: "🍽️", light: "#AF52DE", dark: "#BF5AF2" },
    Dessert: { emoji: "🍰", light: "#FF2D55", dark: "#FF375F" },
    Snack: { emoji: "🍿", light: "#FFCC00", dark: "#FFD60A" },
    Drink: { emoji: "🍹", light: "#5856D6", dark: "#5E5CE6" },
    Appetizer: { emoji: "🥣", light: "#FF9500", dark: "#FF9F0A" },
    "Side Dish": { emoji: "🥗", light: "#34C759", dark: "#30D158" },
    Vegetarian: { emoji: "🥕", light: "#34C759", dark: "#30D158" },
    Vegan: { emoji: "🌱", light: "#66CC66", dark: "#66CC66" },
    "Gluten-Free": { emoji: "🌾", light: "#A2845E", dark: "#AC8E68" },
    Keto: { emoji: "🥑", light: "#FF3B30", dark: "#FF453A" },
    Paleo: { emoji: "🍖", light: "#FF9500", dark: "#FF9F0A" },
    Healthy: { emoji: "💪", light: "#00C7BE", dark: "#63E6E2" },
    "Low Carb": { emoji: "🥬", light: "#34C759", dark: "#30D158" },
    "High Protein": { emoji: "🍗", light: "#FF3B30", dark: "#FF453A" },
    Italian: { emoji: "🍝", light: "#CC3333", dark: "#CC3333" },
    Mexican: { emoji: "🌮", light: "#E6801A", dark: "#E6801A" },
    Asian: { emoji: "🥢", light: "#FF3B30", dark: "#FF453A" },
    Chinese: { emoji: "🥡", light: "#FF3B30", dark: "#FF453A" },
    Japanese: { emoji: "🍣", light: "#FF6666", dark: "#FF6666" },
    Jewish: { emoji: "🥯", light: "#007AFF", dark: "#0A84FF" },
    Thai: { emoji: "🍜", light: "#34C759", dark: "#30D158" },
    Indian: { emoji: "🍛", light: "#FF9500", dark: "#FF9F0A" },
    Greek: { emoji: "🥙", light: "#007AFF", dark: "#0A84FF" },
    "Middle Eastern": { emoji: "🧆", light: "#FF9500", dark: "#FF9F0A" },
    American: { emoji: "🍔", light: "#007AFF", dark: "#0A84FF" },
    French: { emoji: "🥐", light: "#5856D6", dark: "#5E5CE6" },
    "Quick & Easy": { emoji: "⚡️", light: "#FFCC00", dark: "#FFD60A" },
    "Comfort Food": { emoji: "🍲", light: "#A2845E", dark: "#AC8E68" },
    Baking: { emoji: "🥧", light: "#FF2D55", dark: "#FF375F" },
    "One Pot": { emoji: "🥘", light: "#FF9500", dark: "#FF9F0A" },
    "Air Fryer": { emoji: "♨️", light: "#8E8E93", dark: "#8E8E93" },
    "Budget Friendly": { emoji: "💰", light: "#34C759", dark: "#30D158" },
};

const recipeCategoryAliases: Readonly<Record<string, string>> = {
    veg: "Vegetarian", veggie: "Vegetarian",
    gf: "Gluten-Free", "gluten-free": "Gluten-Free",
    "low carb": "Low Carb", "high protein": "High Protein",
    bbq: "American", barbecue: "American",
    airfryer: "Air Fryer", "air-fryer": "Air Fryer",
    "one-pot": "One Pot", onepot: "One Pot",
    cheap: "Budget Friendly", budget: "Budget Friendly",
    fast: "Quick & Easy", quick: "Quick & Easy", easy: "Quick & Easy",
    bake: "Baking", baked: "Baking",
    "chinese food": "Chinese", "italian food": "Italian",
    "mexican food": "Mexican", "indian food": "Indian",
    "thai food": "Thai", "japanese food": "Japanese",
    "jewish food": "Jewish", matzah: "Jewish", bagel: "Jewish",
    "greek food": "Greek",
    starter: "Appetizer", apps: "Appetizer", soup: "Appetizer",
    side: "Side Dish", salad: "Side Dish",
};

export function canonicalRecipeCategoryName(rawTag: string): string | null {
    const normalized = rawTag.trim().toLocaleLowerCase("en-US");
    const directMatch = Object.keys(recipeCategoryPresentation).find(
        (name) => name.toLocaleLowerCase("en-US") === normalized
    );
    return directMatch ?? recipeCategoryAliases[normalized] ?? null;
}

export function generateRecipePageHtml(
    recipe: WebRecipeContent,
    canonicalURL: string,
    appURL: string,
    downloadURL: string,
    creator: WebRecipeCreator | null = null
): string {
    const description = `${recipe.title}: ${recipe.ingredients.length} ingredients and ${recipe.steps.length} steps, shared from Cauldron.`;
    const metadata = [
        recipe.totalMinutes ? { icon: "clock", value: `${recipe.totalMinutes} min` } : null,
        recipe.yields ? { icon: "people", value: recipe.yields } : null,
    ].filter((value): value is { icon: string; value: string } => Boolean(value));
    const metadataIcon = (icon: string) => {
        if (icon === "clock") {
            return `<svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="7.25"></circle><path d="M10 6v4.2l2.8 1.7"></path></svg>`;
        }
        return `<svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="7" cy="7" r="2.5"></circle><circle cx="14" cy="8" r="2"></circle><path d="M2.8 15c.5-2.8 2-4.2 4.4-4.2s4 1.4 4.5 4.2M12 12c2.8-.6 4.6.4 5.2 3"></path></svg>`;
    };
    const metaHTML = metadata.map(({ icon, value }) => `<li>${metadataIcon(icon)}<span>${escapeHtml(value)}</span></li>`).join("");
    const tagsHTML = recipe.tags.slice(0, 6).map((tag) => {
        const categoryName = canonicalRecipeCategoryName(tag);
        const presentation = (categoryName ? recipeCategoryPresentation[categoryName] : null) ?? {
            emoji: "",
            light: "#FF9933",
            dark: "#FF9933",
        };
        const style = `--tag-color:${presentation.light};--tag-color-dark:${presentation.dark}`;
        const displayName = categoryName ?? tag.trim();
        return `<li style="${style}">${presentation.emoji ? `<span aria-hidden="true">${presentation.emoji}</span>` : ""}${escapeHtml(displayName)}</li>`;
    }).join("");

    let ingredientSection: string | null = null;
    const ingredientsHTML = recipe.ingredients.map((ingredient) => {
        const section = ingredient.section && ingredient.section !== ingredientSection
            ? `<li class="section-label">${escapeHtml(ingredient.section)}</li>`
            : "";
        ingredientSection = ingredient.section;
        const quantity = [ingredient.quantity, ...ingredient.additionalQuantities]
            .filter((value): value is WebRecipeQuantity => value !== null)
            .map(formatWebQuantity)
            .join(" + ");
        return `${section}<li class="ingredient"><span class="ingredient-dot" aria-hidden="true"></span><span><span class="ingredient-amount">${escapeHtml(quantity)}</span>${quantity ? " " : ""}<strong>${escapeHtml(ingredient.name)}</strong>${ingredient.note ? `<small>${escapeHtml(ingredient.note)}</small>` : ""}</span></li>`;
    }).join("");

    let stepSection: string | null = null;
    const stepsHTML = recipe.steps.map((step, index) => {
        const section = step.section && step.section !== stepSection
            ? `<li class="method-section" role="presentation"><h3>${escapeHtml(step.section)}</h3></li>`
            : "";
        stepSection = step.section;
        return `${section}<li class="step"><span class="step-number" aria-hidden="true">${String(index + 1).padStart(2, "0")}</span><p>${escapeHtml(step.text)}</p></li>`;
    }).join("");
    const safeAppURL = escapeHtml(appURL);
    const creatorHTML = creator ? (() => {
        const avatar = creator.profileEmoji || Array.from(creator.displayName)[0] || "C";
        const avatarColor = creator.profileColor && /^#[0-9a-f]{6}$/i.test(creator.profileColor)
            ? creator.profileColor
            : "#FF9933";
        return `<a class="creator" href="/u/${encodeURIComponent(creator.username)}"><span class="creator-avatar" style="--avatar-color:${avatarColor}" aria-hidden="true">${escapeHtml(avatar)}</span><span class="creator-copy"><strong>${escapeHtml(creator.displayName)}</strong><small>@${escapeHtml(creator.username)}</small></span></a>`;
    })() : "";
    const ingredientsClass = recipe.ingredients.length <= 12 ? "ingredients-column sticky-eligible" : "ingredients-column";
    const safeCanonicalJSON = JSON.stringify(canonicalURL).replace(/</g, "\\u003c");

    return `<!DOCTYPE html><html lang="en"><head>${recipePageHead(recipe, description, canonicalURL)}<style>
        :root { color-scheme:light dark; --paper:#F6F1EA; --ink:#1C1C1E; --muted:#6E6E73; --accent:#FF9933; --accent-text:#995100; --soft:#FFFFFF; }
        @media (prefers-color-scheme:dark) { :root { --paper:#18120D; --ink:#F2F2F7; --muted:#AEAEB2; --accent:#FF9933; --accent-text:#FFB45F; --soft:#262220; } .tags li { color:var(--tag-color-dark); background:color-mix(in srgb,var(--tag-color-dark) 15%,transparent); } }
        * { box-sizing:border-box; }
        html { background:var(--paper); }
        body { margin:0; color:var(--ink); background:var(--paper); font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif; -webkit-font-smoothing:antialiased; }
        a { color:inherit; }
        .topbar { width:min(1180px,calc(100% - 64px)); min-height:82px; margin:auto; display:flex; align-items:center; }
        .brand { display:flex; align-items:center; gap:10px; text-decoration:none; }
        .brand-icon { width:32px; height:32px; display:grid; place-items:center; }
        .brand-icon img { display:block; width:32px; height:32px; object-fit:contain; }
        .brand-name { font-family:"New York",ui-serif,"Iowan Old Style",Palatino,Georgia,serif; font-size:21px; font-weight:700; letter-spacing:-.02em; }
        main { width:min(1180px,calc(100% - 64px)); margin:48px auto 120px; }
        .recipe-masthead { display:grid; grid-template-columns:minmax(0,1.42fr) minmax(320px,.78fr); gap:clamp(48px,7vw,96px); align-items:center; }
        .recipe-masthead.no-image { grid-template-columns:minmax(0,760px); min-height:360px; align-content:center; }
        .hero-media { min-width:0; }
        .hero-image { display:block; width:100%; aspect-ratio:5/4; max-height:720px; object-fit:cover; border-radius:14px; background:var(--soft); }
        .recipe-intro { padding:20px 0; }
        h1,h2,h3 { font-family:"New York",ui-serif,"Iowan Old Style",Palatino,Georgia,serif; }
        h1 { max-width:12ch; margin:0; font-size:clamp(46px,5.25vw,68px); line-height:1; letter-spacing:-.04em; overflow-wrap:anywhere; }
        .creator { width:max-content; max-width:100%; margin-top:26px; display:flex; align-items:center; gap:11px; text-decoration:none; }
        .creator-avatar { width:36px; height:36px; flex:0 0 36px; display:grid; place-items:center; border-radius:50%; background:color-mix(in srgb,var(--avatar-color) 18%,transparent); font-size:18px; }
        .creator-copy { min-width:0; display:flex; gap:6px; align-items:baseline; }
        .creator strong { font-size:14px; font-weight:700; }
        .creator small { color:var(--muted); font-size:12px; }
        .meta { display:flex; flex-wrap:wrap; gap:18px; margin:28px 0 0; padding:0; list-style:none; color:var(--muted); }
        .meta li { display:flex; align-items:center; gap:7px; font-size:13px; font-weight:600; }
        .meta svg { width:15px; height:15px; fill:none; stroke:var(--accent-text); stroke-width:1.8; stroke-linecap:round; stroke-linejoin:round; }
        .tags { display:flex; flex-wrap:wrap; gap:8px; margin:15px 0 0; padding:0; list-style:none; }
        .tags li { display:flex; gap:5px; align-items:center; min-height:28px; padding:5px 10px; border-radius:999px; color:var(--tag-color); background:color-mix(in srgb,var(--tag-color) 15%,transparent); font-size:12px; font-weight:600; }
        .recipe-actions { margin-top:34px; display:flex; flex-wrap:wrap; align-items:center; gap:18px; }
        .intro-action { min-height:44px; display:inline-flex; align-items:center; padding:10px 16px; border-radius:999px; color:#2B1600; background:var(--accent); font-size:14px; font-weight:750; text-decoration:none; }
        .download-action { min-height:44px; display:inline-flex; align-items:center; color:var(--muted); font-size:13px; font-weight:650; text-decoration:none; }
        .share-action { min-height:44px; display:inline-flex; align-items:center; padding:10px 0; border:0; color:var(--muted); background:none; font:inherit; font-size:13px; font-weight:650; cursor:pointer; }
        .share-action:hover { color:var(--ink); }
        .share-status { color:var(--muted); font-size:12px; }
        .recipe-body { display:grid; grid-template-columns:minmax(320px,.85fr) minmax(0,1.65fr); gap:clamp(58px,8vw,108px); margin-top:88px; align-items:start; }
        .ingredients-column { min-width:0; }
        .section-title { margin:0 0 30px; font-size:28px; letter-spacing:-.025em; }
        .ingredients { margin:0; padding:0; list-style:none; }
        .ingredient { width:100%; display:flex; align-items:flex-start; gap:10px; padding:8px 0; font-size:15px; line-height:1.5; }
        .ingredient > span:last-child { min-width:0; flex:1; overflow-wrap:anywhere; }
        .ingredient-dot { width:6px; height:6px; flex:0 0 6px; margin-top:8px; border-radius:50%; background:var(--accent); }
        .ingredient-amount { color:var(--muted); font-variant-numeric:tabular-nums; }
        .ingredient strong { font-weight:600; }
        .ingredient small { display:block; margin-top:2px; color:var(--muted); font-size:13px; }
        .section-label,.method-section { color:var(--accent-text); font-size:11px; font-weight:800; letter-spacing:.11em; text-transform:uppercase; }
        .section-label { padding:24px 0 5px; }
        .section-label:first-child { padding-top:0; }
        .method { max-width:720px; margin:0; padding:0; list-style:none; }
        .method-section { padding:30px 0 6px; }
        .method-section h3 { margin:0; color:inherit; font:inherit; overflow-wrap:anywhere; }
        .method-section:first-child { padding-top:0; }
        .step { display:grid; grid-template-columns:42px minmax(0,1fr); gap:16px; padding:0 0 26px; }
        .step-number { padding-top:4px; color:var(--accent-text); font-family:"New York",ui-serif,"Iowan Old Style",Palatino,Georgia,serif; font-size:13px; font-weight:800; font-variant-numeric:tabular-nums; }
        .step p { min-width:0; margin:0; font-size:17px; line-height:1.66; overflow-wrap:anywhere; }
        a:focus-visible,button:focus-visible { outline:3px solid color-mix(in srgb,var(--accent) 78%,white); outline-offset:4px; }
        @media (min-width:900px) and (min-height:720px) { .ingredients-column.sticky-eligible { position:sticky; top:32px; } }
        @media (max-width:820px) { .topbar,main { width:min(calc(100% - 32px),680px); } .topbar { min-height:68px; } main { margin:24px auto 80px; } .recipe-masthead { grid-template-columns:1fr; gap:30px; } .hero-image { aspect-ratio:4/3; border-radius:12px; } .recipe-intro { padding:0; } h1 { max-width:16ch; font-size:clamp(40px,11vw,56px); } .meta { margin-top:22px; } .recipe-actions { margin-top:28px; } .recipe-body { grid-template-columns:1fr; gap:58px; margin-top:72px; } .ingredients-column { position:static; } .method { max-width:none; } }
        @media (max-width:430px) { .brand-name { font-size:19px; } .brand-icon,.brand-icon img { width:30px; height:30px; } .creator-copy { flex-direction:column; gap:1px; align-items:flex-start; } }
        @media print { :root { --paper:#fff; --ink:#000; --muted:#444; --accent-text:#7A330E; } .topbar,.recipe-actions { display:none; } body { background:#fff; } main { width:100%; margin:0; } .recipe-masthead { grid-template-columns:42% 1fr; gap:32px; align-items:start; } .hero-image { max-height:360px; border-radius:0; } h1 { font-size:42px; } .recipe-body { grid-template-columns:34% 1fr; gap:44px; margin-top:48px; } .ingredients-column { position:static !important; } .step { break-inside:avoid; } }
    </style></head><body><header class="topbar"><div class="brand"><picture class="brand-icon"><source media="(prefers-color-scheme: dark)" srcset="/icon-small-dark.svg"><img src="/icon-small-light.svg" alt="" aria-hidden="true"></picture><span class="brand-name">Cauldron</span></div></header><main><article><section class="recipe-masthead${recipe.imageURL ? "" : " no-image"}">${recipe.imageURL ? `<div class="hero-media"><img class="hero-image" src="${escapeHtml(recipe.imageURL)}" alt="${escapeHtml(recipe.title)}" fetchpriority="high"></div>` : ""}<header class="recipe-intro"><h1>${escapeHtml(recipe.title)}</h1>${creatorHTML}${metaHTML ? `<ul class="meta" aria-label="Recipe details">${metaHTML}</ul>` : ""}${tagsHTML ? `<ul class="tags" aria-label="Recipe tags">${tagsHTML}</ul>` : ""}<div class="recipe-actions"><a class="intro-action" id="openRecipe" href="${safeAppURL}">Open in Cauldron</a><a class="download-action" href="${escapeHtml(downloadURL)}">Get the app</a><button class="share-action" id="shareRecipe" type="button">Share</button><span class="share-status" id="shareStatus" role="status" aria-live="polite"></span></div></header></section><div class="recipe-body"><aside class="${ingredientsClass}"><h2 class="section-title">Ingredients</h2><ul class="ingredients">${ingredientsHTML || `<li class="ingredient"><span></span><span>Ingredients are being prepared.</span></li>`}</ul></aside><section class="instructions-column" aria-labelledby="instructions-title"><h2 class="section-title" id="instructions-title">Instructions</h2><ol class="method">${stepsHTML || `<li class="step"><span class="step-number">1</span><p>Open this recipe in Cauldron for the instructions.</p></li>`}</ol></section></div></article></main><script>(function(){var button=document.getElementById("shareRecipe");var status=document.getElementById("shareStatus");var url=${safeCanonicalJSON};if(!button)return;button.addEventListener("click",async function(){try{if(navigator.share){await navigator.share({title:document.title,url:url});return;}await navigator.clipboard.writeText(url);button.textContent="Copied";if(status)status.textContent="Recipe link copied.";}catch(error){if(error&&error.name==="AbortError")return;if(status)status.textContent="Could not share this recipe.";}});})();</script>${appOpenFallbackScript("openRecipe", appURL)}</body></html>`;
}

export function renderCanonicalRecipePage(
    recipe: WebRecipeContent | null,
    creator: WebRecipeCreator | null,
    canonicalURL: string,
    appURL: string,
    downloadURL: string
): { status: number; html: string } {
    if (recipe && creator) {
        return {
            status: 200,
            html: generateRecipePageHtml(recipe, canonicalURL, appURL, downloadURL, creator),
        };
    }
    return {
        status: 404,
        html: generatePublicStatusPageHtml(
            "Recipe unavailable",
            "This recipe is no longer available on the web."
        ),
    };
}

export function generateCompactRecipeIndexPageHtml(options: RecipeIndexPageOptions): string {
    const safeAppURL = escapeHtml(options.appURL);
    const count = `${options.totalRecipeCount}${options.hasMoreRecipes ? "+" : ""}`;
    const noun = options.totalRecipeCount === 1 ? "recipe" : "recipes";
    const rows = options.recipes.map((recipe) => {
        const categoryName = recipe.tags.flatMap((tag) => {
            const category = canonicalRecipeCategoryName(tag);
            return category ? [category] : [];
        })[0] ?? null;
        const presentation = categoryName ? recipeCategoryPresentation[categoryName] : null;
        const verifiedImageURL = safeCloudKitAssetURL(recipe.imageURL);
        const media = verifiedImageURL
            ? `<img class="recipe-photo" src="${escapeHtml(verifiedImageURL)}" alt="" loading="lazy" decoding="async" referrerpolicy="no-referrer">`
            : `<picture class="recipe-placeholder"><source media="(prefers-color-scheme: dark)" srcset="/icon-small-dark.svg"><img src="/icon-small-light.svg" alt="" aria-hidden="true"></picture>`;
        const tag = presentation && categoryName
            ? `<span class="recipe-tag" style="--tag-color:${presentation.light};--tag-color-dark:${presentation.dark}"><span aria-hidden="true">${presentation.emoji}</span>${escapeHtml(categoryName)}</span>`
            : "";
        const time = recipe.totalMinutes ? `<span>${recipe.totalMinutes} min</span>` : "";
        const metadata = tag || time ? `<span class="recipe-meta">${tag}${time}</span>` : "";
        return `<li><a class="recipe-row" href="/recipe/${encodeURIComponent(recipe.recipeId)}"><span class="recipe-media">${media}</span><span class="recipe-copy"><span class="recipe-name">${escapeHtml(recipe.title)}</span>${metadata}</span></a></li>`;
    }).join("");
    const avatarColor = options.avatarColor && /^#[0-9a-f]{6}$/i.test(options.avatarColor)
        ? options.avatarColor
        : "#FF9933";
    const handleHTML = options.handle ? `<p class="handle">${escapeHtml(options.handle)}</p>` : "";
    const identity = options.avatarEmoji
        ? `<div class="identity"><span class="profile-avatar" style="--avatar-color:${avatarColor}" aria-hidden="true">${escapeHtml(options.avatarEmoji)}</span><div class="identity-text"><h1>${escapeHtml(options.title)}</h1>${handleHTML}</div></div>`
        : `<h1>${escapeHtml(options.title)}</h1>`;
    return `<!DOCTYPE html><html lang="en"><head>${compactPageHead(options.title, options.description, options.canonicalURL, options.openGraphType)}</head><body>${compactBrandHeader()}<main><section class="intro">${identity}<a class="action" id="openRecipeShelf" href="${safeAppURL}">Open in Cauldron</a><a class="download-action" href="${escapeHtml(options.downloadURL)}">Get the app</a></section><section class="shelf" aria-labelledby="recipe-count"><p class="count" id="recipe-count">${count} ${noun}</p>${rows ? `<ol class="recipe-list">${rows}</ol>` : `<p class="empty">No public recipes have been shared here yet.</p>`}</section></main>${appOpenFallbackScript("openRecipeShelf", options.appURL)}</body></html>`;
}

type InviteRequestLike = {
    query?: Record<string, unknown>;
    path?: string;
};

function normalizeReferralCode(rawCode: unknown): string | null {
    if (typeof rawCode !== "string") {
        return null;
    }

    const normalized = rawCode.toUpperCase().trim();
    if (!/^[A-Z0-9]{6}$/.test(normalized)) {
        return null;
    }

    return normalized;
}

function extractReferralCodeFromRequest(req: InviteRequestLike): string | null {
    const rawQueryCode = Array.isArray(req.query?.code) ? req.query?.code[0] : req.query?.code;
    const queryCode = normalizeReferralCode(rawQueryCode);
    if (queryCode) {
        return queryCode;
    }

    const pathParts = (req.path ?? "").split("/").filter(Boolean);
    if (pathParts.length >= 2 && pathParts[0].toLowerCase() === "invite") {
        return normalizeReferralCode(pathParts[1]);
    }

    if (pathParts.length === 1 && pathParts[0].toLowerCase() !== "invite") {
        return normalizeReferralCode(pathParts[0]);
    }

    return null;
}

export function generateInvitePreviewHtml(inviteCode: string | null): string {
    const hasValidCode = inviteCode !== null;
    const universalURL = hasValidCode
        ? `https://cauldron-f900a.web.app/invite/${inviteCode}`
        : "https://cauldron-f900a.web.app/invite";
    const appURL = hasValidCode
        ? `cauldron://invite?code=${inviteCode}`
        : "cauldron://invite";
    const appStoreURL = "https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943";
    const title = hasValidCode ? "You were invited to Cauldron" : "Cauldron Invite";
    const description = hasValidCode
        ? `Join Cauldron with invite code ${inviteCode} to connect with your friend instantly.`
        : "This invite link is invalid or expired. Ask your friend to send a new one.";
    const statusLine = hasValidCode
        ? "Use this code during sign up if needed:"
        : "Invite code could not be read from this link.";

    return `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${title}</title>
    <meta property="og:type" content="website">
    <meta property="og:title" content="${title}">
    <meta property="og:description" content="${description}">
    <meta property="og:image" content="https://cauldron-f900a.web.app/social-card.png">
    <meta property="og:url" content="${universalURL}">
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="${title}">
    <meta name="twitter:description" content="${description}">
    <meta name="twitter:image" content="https://cauldron-f900a.web.app/social-card.png">
    <meta name="apple-itunes-app" content="app-id=6754004943, app-argument=${universalURL}">
    <style>
        :root {
            --orange: #FF9933;
            --primary-bg: #FF9933;
            --primary-text: #1C1C1E;
            --bg: #F6F1EA;
            --card: #ffffff;
            --text: #1C1C1E;
            --subtext: #6E6E73;
        }

        @media (prefers-color-scheme: dark) {
            :root {
                --bg: #18120D;
                --card: #262220;
                --text: #F2F2F7;
                --subtext: #AEAEB2;
                --orange: #FF9933;
                --primary-bg: #FF9933;
                --primary-text: #1C1C1E;
            }
        }

        * { box-sizing: border-box; }

        body {
            margin: 0;
            min-height: 100vh;
            background: var(--bg);
            color: var(--text);
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }

        .card {
            width: 100%;
            max-width: 480px;
            border-radius: 24px;
            background: transparent;
            padding: 28px;
            text-align: center;
        }

        .logo {
            width: 72px;
            height: 72px;
            margin: 0 auto 20px;
            border-radius: 16px;
            background: rgba(255, 153, 51, 0.12);
            display: flex;
            align-items: center;
            justify-content: center;
        }

        .logo img {
            width: 44px;
            height: 44px;
        }

        h1 {
            margin: 0;
            font-size: 28px;
            line-height: 1.2;
        }

        p {
            margin: 10px 0 0;
            color: var(--subtext);
            line-height: 1.45;
        }

        .code-label {
            margin-top: 22px;
            color: var(--subtext);
            font-size: 13px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .code-chip {
            margin-top: 8px;
            font-size: 26px;
            font-weight: 700;
            letter-spacing: 2px;
            background: rgba(255, 153, 51, 0.12);
            color: var(--orange);
            border-radius: 14px;
            padding: 10px 14px;
            display: inline-block;
            min-width: 180px;
        }

        .button {
            margin-top: 14px;
            width: 100%;
            display: inline-flex;
            justify-content: center;
            align-items: center;
            text-decoration: none;
            border-radius: 14px;
            padding: 14px 16px;
            font-weight: 600;
            border: 0;
            cursor: pointer;
            font-size: 16px;
        }

        .button-primary {
            margin-top: 24px;
            background: var(--primary-bg);
            color: var(--primary-text);
        }

        .button-secondary {
            background: rgba(255, 153, 51, 0.16);
            color: var(--orange);
        }

        .sr-only { position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border: 0; }
    </style>
</head>
<body>
    <main class="card">
        <div class="logo">
            <picture><source media="(prefers-color-scheme: dark)" srcset="https://cauldron-f900a.web.app/icon-dark.svg"><img src="https://cauldron-f900a.web.app/icon-light.svg" alt="Cauldron"></picture>
        </div>
        <h1>${title}</h1>
        <p>${description}</p>

        <div class="code-label">${statusLine}</div>
        ${hasValidCode ? `<div class="code-chip" id="inviteCode">${inviteCode}</div>` : ""}
        ${hasValidCode ? `<button class="button button-secondary" id="copyCodeButton" type="button">Copy Code</button>` : ""}
        ${hasValidCode ? `<p class="sr-only" id="copyStatus" role="status" aria-live="polite"></p>` : ""}

        <button class="button button-primary" id="openAppButton" type="button">Open in Cauldron</button>
        <a class="button button-secondary" href="${appStoreURL}">Download Cauldron</a>
    </main>
    <script>
        (function() {
            var deepLink = ${JSON.stringify(appURL)};
            var inviteCode = ${JSON.stringify(inviteCode)};

            var openButton = document.getElementById("openAppButton");
            if (openButton) {
                openButton.addEventListener("click", function() {
                    window.location.assign(deepLink);
                });
            }

            var copyButton = document.getElementById("copyCodeButton");
            var copyStatus = document.getElementById("copyStatus");
            if (copyButton && inviteCode) {
                copyButton.addEventListener("click", async function() {
                    try {
                        await navigator.clipboard.writeText(inviteCode);
                        copyButton.textContent = "Copied";
                        if (copyStatus) copyStatus.textContent = "Invite code copied.";
                    } catch {
                        copyButton.textContent = "Copy Failed";
                        if (copyStatus) copyStatus.textContent = "Invite code could not be copied.";
                    }
                });
            }
        })();
    </script>
</body>
</html>
    `;
}

export const previewInvite = onRequest(cloudAuthorizedHTTPOptions, async (req, res) => {
    res.set(publicSecurityHeaders());
    if (!await enforcePublicReadRateLimit(req)) {
        rejectRateLimitedRead(res);
        return;
    }
    const inviteCode = extractReferralCodeFromRequest({
        query: req.query as Record<string, unknown>,
        path: req.path,
    });
    const activeInviteCode = inviteCode && await verifyCloudKitReferralCode(inviteCode)
        ? inviteCode
        : null;

    res.set("Cache-Control", "private, no-store, max-age=0");
    res.send(generateInvitePreviewHtml(activeInviteCode));
});

export const previewRecipe = onRequest(cloudBackedPublicReadHTTPOptions, async (req, res) => {
    res.set(publicSecurityHeaders());
    if (!await enforcePublicReadRateLimit(req)) {
        rejectRateLimitedRead(res);
        return;
    }
    res.set("Cache-Control", "private, no-store, max-age=0");
    const pathParts = req.path.split('/');
    const shareId = pathParts[pathParts.length - 1]; // Last part of path

    // Support for /u/{username}/{recipeId} format
    // In this case, shareId might be the username if we aren't careful, 
    // but the rewrite sends /recipe/** to this function so usually it's just /recipe/{id}
    // However, if we add a rewrite for /u/*/* -> previewRecipe, we need to handle it.

    // If path matches /u/username/recipeId
    // pathParts would be ['', 'u', 'username', 'recipeId']

    let recipeId = shareId;
    if (req.path.includes('/u/') && pathParts.length >= 4) {
        recipeId = pathParts[3]; // 0='', 1='u', 2='username', 3='recipeId'
    }

    if (!recipeId) {
        res.status(400).send(generatePublicStatusPageHtml("Invalid recipe link", "This shared recipe link is incomplete."));
        return;
    }

    try {
        const doc = await db.collection('shared_recipes').doc(recipeId).get();
        if (!doc.exists) {
            res.status(404).send(generatePublicStatusPageHtml("Recipe unavailable", "This recipe is no longer available on the web."));
            return;
        }

        const sanitized = sanitizeStoredRecipeShareInput(doc.data() ?? {});
        if (!sanitized.ok) {
            logger.error('Stored recipe share is invalid:', sanitized.error);
            res.status(404).send(generatePublicStatusPageHtml("Recipe unavailable", "This recipe is no longer available on the web."));
            return;
        }
        if (await isShareRevoked(sanitized.value.ownerId) ||
            await isResourcePrivacyBlocked("recipe", recipeId)) {
            res.status(404).send(generatePublicStatusPageHtml("Recipe unavailable", "This recipe is no longer available on the web."));
            return;
        }

        const canonicalURL = `https://cauldron-f900a.web.app/recipe/${encodeURIComponent(recipeId)}`;
        // Keep the custom scheme until the alternate Hosting-domain entitlement
        // has shipped broadly; older installed builds cannot claim that host.
        const appURL = `cauldron://import/recipe/${encodeURIComponent(recipeId)}`;
        const downloadURL = 'https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943';
        const [fullRecipe, creator] = await Promise.all([
            fetchPublicCloudKitRecipe(recipeId, sanitized.value.ownerId),
            fetchPublicCloudKitRecipeCreator(sanitized.value.ownerId),
        ]);

        const rendered = renderCanonicalRecipePage(
            fullRecipe,
            creator,
            canonicalURL,
            appURL,
            downloadURL
        );
        res.set("Cache-Control", "private, no-store, max-age=0");
        res.status(rendered.status).send(rendered.html);
    } catch (error) {
        logger.error('Error loading recipe preview:', error);
        res.set("Retry-After", "30");
        res.status(503).send(generatePublicStatusPageHtml("Recipe temporarily unavailable", "Please try opening this recipe again in a moment."));
    }
});

export const previewRecipeImage = onRequest(cloudBackedPublicReadHTTPOptions, async (req, res) => {
    res.set({
        "Cross-Origin-Resource-Policy": "cross-origin",
        "X-Content-Type-Options": "nosniff",
    });
    if (!await enforcePublicReadRateLimit(req)) {
        rejectRateLimitedRead(res);
        return;
    }

    // Hosting preserves the requested path, while direct function requests may
    // omit the `/recipe` prefix. Accept the single UUID segment in either form.
    const recipeId = req.path.split("/").filter(Boolean).find(isValidUUID) ?? null;
    const sendFallback = () => {
        res.set("Cache-Control", "public, max-age=300, s-maxage=1800, stale-while-revalidate=86400");
        res.redirect(302, "/social-card.png");
    };

    if (!recipeId || !isValidUUID(recipeId)) {
        sendFallback();
        return;
    }

    try {
        const doc = await db.collection("shared_recipes").doc(recipeId).get();
        if (!doc.exists) {
            sendFallback();
            return;
        }
        const sanitized = sanitizeStoredRecipeShareInput(doc.data() ?? {});
        if (!sanitized.ok ||
            await isShareRevoked(sanitized.value.ownerId) ||
            await isResourcePrivacyBlocked("recipe", recipeId)) {
            sendFallback();
            return;
        }

        const recipe = await fetchPublicCloudKitRecipe(recipeId, sanitized.value.ownerId);
        const assetURL = safeCloudKitAssetURL(recipe?.imageURL);
        if (!assetURL) {
            sendFallback();
            return;
        }

        const imageResponse = await fetch(assetURL, {
            signal: AbortSignal.timeout(CLOUDKIT_WEB_REQUEST_TIMEOUT_MS),
        });
        const declaredLength = Number(imageResponse.headers.get("content-length") ?? "0");
        if (!imageResponse.ok ||
            (declaredLength > 0 && declaredLength > SOCIAL_IMAGE_MAX_BYTES)) {
            sendFallback();
            return;
        }

        const bytes = Buffer.from(await imageResponse.arrayBuffer());
        const contentType = detectedImageContentType(bytes);
        if (!contentType || bytes.byteLength > SOCIAL_IMAGE_MAX_BYTES) {
            sendFallback();
            return;
        }

        res.set({
            "Cache-Control": "public, max-age=3600, s-maxage=21600, stale-while-revalidate=86400",
            "Content-Type": contentType,
            "Content-Length": String(bytes.byteLength),
        });
        if (req.method === "HEAD") {
            res.status(200).end();
            return;
        }
        res.status(200).send(bytes);
    } catch (error) {
        logger.warn("Recipe social image proxy fell back to the brand card", { recipeId, error });
        sendFallback();
    }
});

async function browsableRecipes(
    documents: DocumentSnapshot[],
    expectedOwnerId: string | null = null
): Promise<SanitizedRecipeShare[]> {
    const sanitized = documents.flatMap((document) => {
        if (!document.exists) {
            return [];
        }
        const result = sanitizeStoredRecipeShareInput(document.data() ?? {});
        if (!result.ok || result.value.recipeId !== document.id ||
            (expectedOwnerId && result.value.ownerId !== expectedOwnerId)) {
            return [];
        }
        return [result.value];
    });
    if (expectedOwnerId) {
        // The enclosing profile check already verifies the owner's account and
        // recipe unpublishing atomically removes the corresponding snapshot.
        return sanitized;
    }
    const ownerRevocations = new Map<string, boolean>();
    await Promise.all([...new Set(sanitized.map((recipe) => recipe.ownerId))].map(async (ownerId) => {
        ownerRevocations.set(ownerId, await isShareRevoked(ownerId));
    }));
    const visibility = await Promise.all(sanitized.map(async (recipe) => ({
        recipe,
        isBlocked: ownerRevocations.get(recipe.ownerId) === true ||
            await isResourcePrivacyBlocked("recipe", recipe.recipeId),
    })));
    return visibility
        .filter(({ isBlocked }) => !isBlocked)
        .map(({ recipe }) => recipe);
}

export const previewProfile = onRequest(cloudBackedPublicReadHTTPOptions, async (req, res) => {
    res.set(publicSecurityHeaders());
    res.set("Cache-Control", "private, no-store, max-age=0");
    if (!await enforcePublicReadRateLimit(req)) {
        rejectRateLimitedRead(res);
        return;
    }
    const pathParts = req.path.split('/');
    const shareId = pathParts[pathParts.length - 1];

    if (!shareId) {
        res.status(400).send(generatePublicStatusPageHtml("Invalid profile link", "This shared profile link is incomplete."));
        return;
    }

    // Support for /u/{username}
    // The rewrite maps /u/* -> previewProfile.
    // So shareId is the username.

    try {
        let doc = await db.collection('shared_profiles').doc(shareId).get();
        if (!doc.exists) {
            // Because we use username as ID, this is a direct lookup
            // If it fails, we might want to try to look up by user ID if shareId matches UUID format??
            // For now, assume username.
            res.status(404).send(generatePublicStatusPageHtml("Profile unavailable", "This profile is no longer shared on the web."));
            return;
        }

        const redirectShareId = doc.data()?.redirectShareId;
        if (typeof redirectShareId === 'string' && isValidUUID(redirectShareId)) {
            doc = await db.collection('shared_profiles').doc(redirectShareId).get();
            if (!doc.exists) {
                res.status(404).send(generatePublicStatusPageHtml("Profile unavailable", "This profile is no longer shared on the web."));
                return;
            }
        }

        const rawData = doc.data()!;
        const sanitized = sanitizeStoredProfileShareInput(rawData);
        if (!sanitized.ok || await isShareRevoked(rawData.ownerId) ||
            await isResourcePrivacyBlocked("profile", rawData.userId)) {
            res.status(404).send(generatePublicStatusPageHtml("Profile unavailable", "This profile is no longer shared on the web."));
            return;
        }
        const data = sanitized.value;
        const browsable: SanitizedRecipeShare[] = [];
        let profileCursor: QueryDocumentSnapshot | null = null;
        for (let page = 0; page < 4 && browsable.length < WEB_RECIPE_CARD_QUERY_LIMIT; page += 1) {
            let recipeQuery: Query = db.collection('shared_recipes')
                .where('ownerId', '==', data.userId)
                .limit(25);
            if (profileCursor) {
                recipeQuery = recipeQuery.startAfter(profileCursor);
            }
            const recipeSnapshot = await recipeQuery.get();
            browsable.push(...await browsableRecipes(recipeSnapshot.docs, data.userId));
            if (recipeSnapshot.size < 25) {
                break;
            }
            profileCursor = recipeSnapshot.docs[recipeSnapshot.docs.length - 1];
        }
        const hasMoreRecipes = browsable.length > MAX_WEB_RECIPE_CARDS;
        const recipes = browsable.slice(0, MAX_WEB_RECIPE_CARDS);
        recipes.sort((lhs, rhs) => lhs.title.localeCompare(rhs.title));
        const indexItems = await bestEffortRecipeIndexItems(recipes);
        const description = "A recipe shelf shared from Cauldron.";
        const canonicalURL = `https://cauldron-f900a.web.app/profile/${encodeURIComponent(data.userId)}`;
        const appURL = `cauldron://import/profile/${shareId}`;
        const downloadURL = 'https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943';

        res.set("Cache-Control", "private, no-store, max-age=0");
        res.send(generateCompactRecipeIndexPageHtml({
            handle: `@${data.username}`,
            title: data.displayName,
            description,
            canonicalURL,
            appURL,
            downloadURL,
            recipes: indexItems,
            totalRecipeCount: recipes.length,
            hasMoreRecipes,
            openGraphType: "profile",
            avatarEmoji: data.profileEmoji,
            avatarColor: data.profileColor,
        }));
    } catch (error) {
        logger.error('Error loading profile preview:', error);
        res.status(500).send(generatePublicStatusPageHtml("Profile temporarily unavailable", "Please try opening this profile again in a moment."));
    }
});

export const previewCollection = onRequest(cloudBackedPublicReadHTTPOptions, async (req, res) => {
    res.set(publicSecurityHeaders());
    res.set("Cache-Control", "private, no-store, max-age=0");
    if (!await enforcePublicReadRateLimit(req)) {
        rejectRateLimitedRead(res);
        return;
    }
    const pathParts = req.path.split('/');
    const shareId = pathParts[pathParts.length - 1];

    if (!shareId) {
        res.status(400).send(generatePublicStatusPageHtml("Invalid collection link", "This shared collection link is incomplete."));
        return;
    }

    try {
        const doc = await db.collection('shared_collections').doc(shareId).get();
        if (!doc.exists) {
            res.status(404).send(generatePublicStatusPageHtml("Collection unavailable", "This collection is no longer shared on the web."));
            return;
        }

        const rawData = doc.data()!;
        const sanitized = sanitizeStoredCollectionShareInput(rawData);
        if (!sanitized.ok || await isShareRevoked(rawData.ownerId) ||
            await isResourcePrivacyBlocked("collection", rawData.collectionId)) {
            res.status(404).send(generatePublicStatusPageHtml("Collection unavailable", "This collection is no longer shared on the web."));
            return;
        }
        const data = sanitized.value;
        const browsable: SanitizedRecipeShare[] = [];
        let collectionCursor = 0;
        while (collectionCursor < data.recipeIds.length && browsable.length < WEB_RECIPE_CARD_QUERY_LIMIT) {
            const candidateRecipeIds = data.recipeIds.slice(collectionCursor, collectionCursor + 25);
            const recipeDocuments = await db.getAll(
                ...candidateRecipeIds.map((recipeId) => db.collection('shared_recipes').doc(recipeId))
            );
            browsable.push(...await browsableRecipes(recipeDocuments));
            collectionCursor += candidateRecipeIds.length;
        }
        const hasMoreRecipes = browsable.length > MAX_WEB_RECIPE_CARDS || collectionCursor < data.recipeIds.length;
        const recipes = browsable.slice(0, MAX_WEB_RECIPE_CARDS);
        const recipeOrder = new Map(data.recipeIds.map((recipeId, index) => [recipeId, index]));
        recipes.sort((lhs, rhs) => (recipeOrder.get(lhs.recipeId) ?? Number.MAX_SAFE_INTEGER) -
            (recipeOrder.get(rhs.recipeId) ?? Number.MAX_SAFE_INTEGER));
        const indexItems = await bestEffortRecipeIndexItems(recipes);
        const description = "A recipe collection shared from Cauldron.";
        const canonicalURL = `https://cauldron-f900a.web.app/collection/${encodeURIComponent(shareId)}`;
        const appURL = `cauldron://import/collection/${shareId}`;
        const downloadURL = 'https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943';

        res.set("Cache-Control", "private, no-store, max-age=0");
        res.send(generateCompactRecipeIndexPageHtml({
            title: data.title,
            description,
            canonicalURL,
            appURL,
            downloadURL,
            recipes: indexItems,
            totalRecipeCount: recipes.length,
            hasMoreRecipes,
            openGraphType: "website",
        }));
    } catch (error) {
        logger.error('Error loading collection preview:', error);
        res.status(500).send(generatePublicStatusPageHtml("Collection temporarily unavailable", "Please try opening this collection again in a moment."));
    }
});
