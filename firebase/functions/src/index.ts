import { onRequest, Request } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import { getApps, initializeApp } from "firebase-admin/app";
import {
    DocumentReference,
    DocumentSnapshot,
    FieldValue,
    FieldPath,
    getFirestore,
    Query,
    QueryDocumentSnapshot,
    Timestamp,
} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { createHash, createSign, timingSafeEqual } from "node:crypto";

if (getApps().length === 0) initializeApp();
const db = getFirestore();
const cloudKitServerKeyID = defineSecret("CLOUDKIT_SERVER_KEY_ID");
const cloudKitServerPrivateKey = defineSecret("CLOUDKIT_SERVER_PRIVATE_KEY");
const CLOUDKIT_CONTAINER = "iCloud.Nadav.Cauldron";
export const PUBLIC_WEB_ORIGIN = "https://cauldronrecipes.com";
const OWNED_PUBLIC_IMAGE_HOSTS = new Set([
    "cauldronrecipes.com",
    "cauldron-f900a.web.app",
    "cauldron-f900a.firebaseapp.com",
]);

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
const CLOUDKIT_WEB_REQUEST_TIMEOUT_MS = 4_000;
const CLOUDKIT_WEB_MAX_ATTEMPTS = 2;
const CLOUDKIT_WEB_RETRY_DELAY_MS = 150;
const SOCIAL_IMAGE_MAX_BYTES = 10_000_000;
export const HOMEPAGE_CACHE_CONTROL = "private, no-store, max-age=0";
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
    relatedRecipeIds?: string[];
    relatedGraphReferenceId?: string;
    creatorDisplayName?: string;
    creatorUsername?: string;
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
    relatedRecipeIds: string[];
    relatedGraphReferenceId: string;
    imageURL: string | null;
};

export type WebRecipeCreator = {
    username: string;
    displayName: string;
    profileEmoji: string | null;
    profileColor: string | null;
    profileImageURL: string | null;
};

type WebProfileContent = WebRecipeCreator & {
    userId: string;
    usernameClaimCreatedAt: number;
    creatorRecordName: string;
};

type WebCollectionContent = {
    collectionId: string;
    ownerId: string;
    title: string;
    recipeIds: string[];
};

type RecipeShelfValidation = {
    items: WebRecipeIndexItem[];
    permanentlyInvalidRecipeIds: string[];
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

type SanitizedOwnerManifest = {
    ownerId: string;
    identityRecordName: string;
    capability: string;
    publicRecipeIds: string[];
    publicCollectionIds: string[];
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
        if (!OWNED_PUBLIC_IMAGE_HOSTS.has(parsed.hostname)) {
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

export function cloudKitQueryPayloadHasErrors(payload: CloudKitRecordsPayload): boolean {
    return typeof payload.serverErrorCode === "string" ||
        (payload.records ?? []).some((record) => typeof record.serverErrorCode === "string");
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
    return { username, displayName, profileEmoji, profileColor, profileImageURL: null };
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
    expectedOwnerId: string,
    expectedCreatorRecordName: string
): WebRecipeContent | null {
    const fields = record.fields ?? {};
    if (record.recordName !== expectedRecipeId || record.recordType !== "SharedRecipe" ||
        fields.recipeId?.value !== expectedRecipeId || fields.ownerId?.value !== expectedOwnerId ||
        fields.visibility?.value !== "public" ||
        record.created?.userRecordName !== expectedCreatorRecordName) {
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
    const relatedRecipeIds = decodeCloudKitJSONList(fields.relatedRecipeIdsData?.value)
        .filter(isValidUUID)
        .slice(0, 100);
    const originalRecipeId = fields.followsSourceUpdates?.value === 1 &&
        isValidUUID(fields.originalRecipeId?.value)
        ? fields.originalRecipeId.value
        : expectedRecipeId;

    return {
        recipeId: expectedRecipeId,
        ownerId: expectedOwnerId,
        title: title.value,
        yields: optionalPublicText(fields.yields?.value, 160),
        totalMinutes: optionalPositiveInteger(fields.totalMinutes?.value, 1440),
        tags: sanitizedTagList(tags),
        ingredients,
        steps,
        relatedRecipeIds,
        relatedGraphReferenceId: originalRecipeId,
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
    const canonicalOwner = await fetchCanonicalCloudKitProfile(ownerId);
    if (!canonicalOwner) {
        return null;
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
            return record ? sanitizeCloudKitRecipeForWeb(
                record,
                recipeId,
                ownerId,
                canonicalOwner.creatorRecordName
            ) : null;
        });
    } catch (error) {
        logger.warn("CloudKit web recipe lookup failed", { recipeId, error });
        throw error;
    }
}

export function sanitizeCloudKitCollectionForWeb(
    record: CloudKitRecordLike,
    expectedCollectionId: string,
    expectedOwnerId: string,
    expectedCreatorRecordName: string
): WebCollectionContent | null {
    const fields = record.fields ?? {};
    if (record.recordName !== expectedCollectionId || record.recordType !== "Collection" ||
        fields.collectionId?.value !== expectedCollectionId ||
        fields.userId?.value !== expectedOwnerId || fields.visibility?.value !== "public" ||
        record.created?.userRecordName !== expectedCreatorRecordName) {
        return null;
    }
    const title = requiredPublicText(fields.name?.value, "title", MAX_TITLE_LENGTH);
    if (!title.ok) {
        return null;
    }
    let recipeIds: string[] = [];
    if (typeof fields.recipeIds?.value === "string") {
        try {
            const decoded = JSON.parse(fields.recipeIds.value) as unknown;
            if (Array.isArray(decoded)) {
                recipeIds = decoded.filter(isValidUUID).slice(0, 500);
            }
        } catch {
            recipeIds = [];
        }
    }
    return {
        collectionId: expectedCollectionId,
        ownerId: expectedOwnerId,
        title: title.value,
        recipeIds,
    };
}

async function fetchPublicCloudKitCollection(
    collectionId: string,
    ownerId: string
): Promise<WebCollectionContent | null> {
    const keyID = cloudKitServerKeyID.value();
    const privateKey = cloudKitServerPrivateKey.value().replace(/\\n/g, "\n");
    const canonicalOwner = await fetchCanonicalCloudKitProfile(ownerId);
    if (!canonicalOwner) {
        return null;
    }
    return retryTransientCloudKitOperation(async () => {
        const subpath = `/database/1/${CLOUDKIT_CONTAINER}/production/public/records/lookup`;
        const body = JSON.stringify({ records: [{ recordName: collectionId }] });
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
            const message = `CloudKit web collection lookup returned ${response.status}`;
            throw isTransientCloudKitHTTPStatus(response.status)
                ? new RetryableCloudKitError(message)
                : new Error(message);
        }
        const payload = await response.json() as CloudKitRecordsPayload;
        const disposition = cloudKitRecordsPayloadDisposition(payload);
        if (disposition === "error") {
            const message = "CloudKit web collection lookup returned a record error";
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
        const collection = record
            ? sanitizeCloudKitCollectionForWeb(
                record,
                collectionId,
                ownerId,
                canonicalOwner.creatorRecordName
            )
            : null;
        if (!collection || !record) {
            return null;
        }
        const membershipRecipeIDs = await fetchPublicCloudKitCollectionMembershipRecipeIDs(
            collectionId,
            ownerId,
            canonicalOwner.creatorRecordName
        );
        return membershipRecipeIDs === null
            ? collection
            : { ...collection, recipeIds: membershipRecipeIDs };
    });
}

async function fetchPublicCloudKitCollectionMembershipRecipeIDs(
    collectionId: string,
    ownerId: string,
    expectedCreatorRecordName: string
): Promise<string[] | null> {
    const keyID = cloudKitServerKeyID.value();
    const privateKey = cloudKitServerPrivateKey.value().replace(/\\n/g, "\n");
    const subpath = `/database/1/${CLOUDKIT_CONTAINER}/production/public/records/query`;
    let continuationMarker: string | null = null;
    const records: CloudKitRecordLike[] = [];
    let pageCount = 0;
    do {
        pageCount += 1;
        if (pageCount > 3) {
            throw new Error("CloudKit collection membership query exceeded its safety cap");
        }
        const body = JSON.stringify(continuationMarker
            ? { continuationMarker }
            : {
                query: {
                    recordType: "CollectionMembership",
                    filterBy: [
                        {
                            fieldName: "collectionId",
                            comparator: "EQUALS",
                            fieldValue: { value: collectionId },
                        },
                        {
                            fieldName: "ownerId",
                            comparator: "EQUALS",
                            fieldValue: { value: ownerId },
                        },
                    ],
                },
                resultsLimit: 500,
            });
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
            const message = `CloudKit collection membership query returned ${response.status}`;
            throw isTransientCloudKitHTTPStatus(response.status)
                ? new RetryableCloudKitError(message)
                : new Error(message);
        }
        const payload = await response.json() as CloudKitRecordsPayload & {
            continuationMarker?: unknown;
        };
        if (cloudKitQueryPayloadHasErrors(payload)) {
            const message = "CloudKit collection membership query returned a record error";
            throw cloudKitRecordsPayloadIsRetryableError(payload)
                ? new RetryableCloudKitError(message)
                : new Error(message);
        }
        records.push(...(payload.records ?? []).filter((candidate) =>
            typeof candidate.serverErrorCode !== "string"
        ));
        continuationMarker = typeof payload.continuationMarker === "string"
            ? payload.continuationMarker
            : null;
    } while (continuationMarker);

    return resolveCloudKitCollectionMembershipRecipeIDs(
        records,
        collectionId,
        ownerId,
        expectedCreatorRecordName
    );
}

export function resolveCloudKitCollectionMembershipRecipeIDs(
    records: CloudKitRecordLike[],
    collectionId: string,
    ownerId: string,
    expectedCreatorRecordName: string | null
): string[] | null {
    if (records.length === 0 || expectedCreatorRecordName === null) return null;
    const newestByRecipeID = new Map<string, { active: boolean; sortOrder: number; updatedAt: number }>();
    for (const record of records) {
        const fields = record.fields ?? {};
        const recipeId = fields.recipeId?.value;
        const recordCreator = record.created?.userRecordName;
        if (record.recordType !== "CollectionMembership" ||
            fields.collectionId?.value !== collectionId ||
            fields.ownerId?.value !== ownerId ||
            !isValidUUID(recipeId) ||
            (expectedCreatorRecordName !== null && recordCreator !== expectedCreatorRecordName)) {
            continue;
        }
        const rawUpdatedAt = fields.updatedAt?.value;
        const updatedAt = typeof rawUpdatedAt === "number"
            ? rawUpdatedAt
            : typeof rawUpdatedAt === "string"
                ? Date.parse(rawUpdatedAt)
                : 0;
        const candidate = {
            active: fields.status?.value === "active",
            sortOrder: typeof fields.sortOrder?.value === "number" ? fields.sortOrder.value : 0,
            updatedAt: Number.isFinite(updatedAt) ? updatedAt : 0,
        };
        const existing = newestByRecipeID.get(recipeId);
        if (!existing || candidate.updatedAt > existing.updatedAt ||
            (candidate.updatedAt === existing.updatedAt && !candidate.active && existing.active)) {
            newestByRecipeID.set(recipeId, candidate);
        }
    }
    // An untrusted record must never make a legacy collection appear empty. Only
    // authoritative edges may opt a collection into the edge-based model.
    if (newestByRecipeID.size === 0) return null;
    return [...newestByRecipeID.entries()]
        .filter(([, edge]) => edge.active)
        .sort(([, lhs], [, rhs]) => lhs.sortOrder - rhs.sortOrder || lhs.updatedAt - rhs.updatedAt)
        .map(([recipeId]) => recipeId)
        .slice(0, 500);
}

async function fetchCanonicalCloudKitRecipesByOwner(
    ownerId: string,
    expectedCreatorRecordName: string
): Promise<{ recipes: WebRecipeContent[]; complete: boolean }> {
    const keyID = cloudKitServerKeyID.value();
    const privateKey = cloudKitServerPrivateKey.value().replace(/\\n/g, "\n");
    const subpath = `/database/1/${CLOUDKIT_CONTAINER}/production/public/records/query`;
    let continuationMarker: string | null = null;
    const recipes: WebRecipeContent[] = [];
    for (let page = 0; page < 5; page += 1) {
        const body = JSON.stringify(continuationMarker
            ? { continuationMarker }
            : {
                query: {
                    recordType: "SharedRecipe",
                    filterBy: [{
                        fieldName: "ownerId",
                        comparator: "EQUALS",
                        fieldValue: { value: ownerId },
                    }],
                },
                resultsLimit: 100,
            });
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
            const message = `CloudKit owner recipe query returned ${response.status}`;
            throw isTransientCloudKitHTTPStatus(response.status)
                ? new RetryableCloudKitError(message)
                : new Error(message);
        }
        const payload = await response.json() as CloudKitRecordsPayload & {
            continuationMarker?: unknown;
        };
        if (cloudKitQueryPayloadHasErrors(payload)) {
            const message = "CloudKit owner recipe query returned a record error";
            throw cloudKitRecordsPayloadIsRetryableError(payload)
                ? new RetryableCloudKitError(message)
                : new Error(message);
        }
        recipes.push(...canonicalOwnerRecipesFromCloudKitRecords(
            payload.records ?? [],
            ownerId,
            expectedCreatorRecordName
        ));
        continuationMarker = typeof payload.continuationMarker === "string"
            ? payload.continuationMarker
            : null;
        if (!continuationMarker) {
            return { recipes: hideRelatedWebRecipeReferences(recipes), complete: true };
        }
    }
    logger.warn("CloudKit owner recipe materialization reached its 500-recipe safety cap", { ownerId });
    return { recipes: hideRelatedWebRecipeReferences(recipes), complete: false };
}

export function hideRelatedWebRecipeReferences<Recipe extends {
    recipeId: string;
    relatedRecipeIds?: string[];
    relatedGraphReferenceId?: string;
}>(recipes: Recipe[]): Recipe[] {
    const relatedRecipeIds = new Set(recipes.flatMap((recipe) => recipe.relatedRecipeIds ?? []));
    const visibleRecipes = recipes.filter((recipe) =>
        !relatedRecipeIds.has(recipe.recipeId) &&
        (!recipe.relatedGraphReferenceId || !relatedRecipeIds.has(recipe.relatedGraphReferenceId))
    );
    // Legacy or cyclic graphs can reference every recipe. Match the native
    // safety behavior and preserve the owner's valid recipes rather than
    // publishing an empty profile and deleting every existing snapshot.
    return visibleRecipes.length === 0 ? recipes : visibleRecipes;
}

export function publicWebRecipeData(recipe: WebRecipeContent): Record<string, unknown> {
    const publicData: Record<string, unknown> = { ...recipe };
    delete publicData.relatedRecipeIds;
    delete publicData.relatedGraphReferenceId;
    return publicData;
}

export function canonicalOwnerRecipesFromCloudKitRecords(
    records: CloudKitRecordLike[],
    ownerId: string,
    expectedCreatorRecordName: string
): WebRecipeContent[] {
    return records.flatMap((record) => {
        if (record.created?.userRecordName !== expectedCreatorRecordName) {
            return [];
        }
        const recipeId = record.fields?.recipeId?.value;
        if (!isValidUUID(recipeId)) {
            return [];
        }
        const recipe = sanitizeCloudKitRecipeForWeb(
            record,
            recipeId,
            ownerId,
            expectedCreatorRecordName
        );
        return recipe ? [recipe] : [];
    });
}

export function recipeIndexItemsWithCloudKitImages(
    recipes: SanitizedRecipeShare[],
    records: CloudKitRecordLike[],
    canonicalCreatorRecordNamesByOwner: ReadonlyMap<string, string>
): WebRecipeIndexItem[] {
    const recordsByName = new Map(records.flatMap((record) =>
        typeof record.recordName === "string" && typeof record.serverErrorCode !== "string"
            ? [[record.recordName, record] as const]
            : []
    ));
    return recipes.flatMap((recipe): WebRecipeIndexItem[] => {
        const record = recordsByName.get(recipe.recipeId);
        const expectedCreatorRecordName = canonicalCreatorRecordNamesByOwner.get(recipe.ownerId);
        const canonical = record && expectedCreatorRecordName
            ? sanitizeCloudKitRecipeForWeb(
                record,
                recipe.recipeId,
                recipe.ownerId,
                expectedCreatorRecordName
            )
            : null;
        return canonical ? [{
            ...recipe,
            title: canonical.title,
            totalMinutes: canonical.totalMinutes,
            tags: canonical.tags,
            imageURL: canonical.imageURL,
            relatedRecipeIds: canonical.relatedRecipeIds,
            relatedGraphReferenceId: canonical.relatedGraphReferenceId,
        }] : [];
    });
}

async function fetchPublicCloudKitRecipeIndexItems(
    recipes: SanitizedRecipeShare[]
): Promise<RecipeShelfValidation> {
    if (recipes.length === 0) {
        return { items: [], permanentlyInvalidRecipeIds: [] };
    }
    const keyID = cloudKitServerKeyID.value();
    const privateKey = cloudKitServerPrivateKey.value().replace(/\\n/g, "\n");
    if (!keyID || !privateKey) {
        throw new Error("CloudKit web recipe credentials are unavailable");
    }
    const canonicalOwners: WebProfileContent[] = [];
    const ownerIds = [...new Set(recipes.map((recipe) => recipe.ownerId))];
    for (let index = 0; index < ownerIds.length; index += 4) {
        const ownerChunk = ownerIds.slice(index, index + 4);
        const results = await Promise.all(ownerChunk.map(async (ownerId) => {
            try {
                return await fetchCanonicalCloudKitProfile(ownerId);
            } catch (error) {
                logger.warn("CloudKit recipe shelf skipped an unavailable owner", { ownerId, error });
                return null;
            }
        }));
        canonicalOwners.push(...results.filter((owner): owner is WebProfileContent => owner !== null));
    }
    const canonicalCreatorRecordNamesByOwner = new Map(canonicalOwners.flatMap((owner) =>
        owner ? [[owner.userId, owner.creatorRecordName] as const] : []
    ));
    const canonicalOwnersByID = new Map(canonicalOwners.map((owner) => [owner.userId, owner] as const));
    const recipesWithValidatedOwners = recipes.filter((recipe) =>
        canonicalCreatorRecordNamesByOwner.has(recipe.ownerId)
    );
    if (recipesWithValidatedOwners.length === 0) {
        return { items: [], permanentlyInvalidRecipeIds: [] };
    }
    const subpath = `/database/1/${CLOUDKIT_CONTAINER}/production/public/records/lookup`;
    const body = JSON.stringify(cloudKitRecipeShelfLookupBody(recipesWithValidatedOwners));
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
    const records = payload.records ?? [];
    const canonicalItems = recipeIndexItemsWithCloudKitImages(
        recipesWithValidatedOwners,
        records,
        canonicalCreatorRecordNamesByOwner
    ).map((recipe) => {
        const owner = canonicalOwnersByID.get(recipe.ownerId);
        return owner ? {
            ...recipe,
            creatorDisplayName: owner.displayName,
            creatorUsername: owner.username,
        } : recipe;
    });
    const items = hideRelatedWebRecipeReferences(canonicalItems);
    return {
        items,
        permanentlyInvalidRecipeIds: permanentlyInvalidRecipeShelfIDs(
            recipesWithValidatedOwners.map((recipe) => recipe.recipeId),
            records,
            canonicalItems.map((item) => item.recipeId)
        ),
    };
}

export function permanentlyInvalidRecipeShelfIDs(
    requestedRecipeIds: string[],
    records: Array<Pick<CloudKitRecordLike, "recordName" | "serverErrorCode">>,
    canonicalRecipeIds: string[]
): string[] {
    const validIDs = new Set(canonicalRecipeIds);
    const permanentFailures = new Set(records.flatMap((record) => {
        const code = typeof record.serverErrorCode === "string"
            ? record.serverErrorCode.toUpperCase()
            : null;
        const recordName = typeof record.recordName === "string" ? record.recordName : null;
        return recordName && (code === "UNKNOWN_ITEM" ||
            (code === null && !validIDs.has(recordName)))
            ? [recordName]
            : [];
    }));
    return requestedRecipeIds.filter((recipeId) => permanentFailures.has(recipeId));
}

export function cloudKitRecipeShelfLookupBody(
    recipes: Array<Pick<SanitizedRecipeShare, "recipeId">>
): Readonly<{ records: Array<{ recordName: string }>; desiredKeys: string[] }> {
    return {
        records: recipes.map((recipe) => ({ recordName: recipe.recipeId })),
        desiredKeys: [
            "recipeId",
            "ownerId",
            "visibility",
            "title",
            "totalMinutes",
            "tagsData",
            "imageAsset",
            "relatedRecipeIdsData",
            "originalRecipeId",
            "followsSourceUpdates",
        ],
    };
}

async function bestEffortRecipeIndexItems(
    recipes: SanitizedRecipeShare[],
    deadlineMilliseconds?: number
): Promise<RecipeShelfValidation> {
    try {
        const request = fetchPublicCloudKitRecipeIndexItems(recipes);
        if (!deadlineMilliseconds) {
            return await request;
        }
        let timer: NodeJS.Timeout | undefined;
        try {
            return await Promise.race([
                request,
                new Promise<RecipeShelfValidation>((_, reject) => {
                    timer = setTimeout(
                        () => reject(new Error("CloudKit recipe shelf validation deadline exceeded")),
                        deadlineMilliseconds
                    );
                }),
            ]);
        } finally {
            if (timer) clearTimeout(timer);
        }
    } catch (error) {
        logger.warn("CloudKit recipe shelf validation is temporarily unavailable", { error });
        // Firebase is only a derived index. Never emit a link that CloudKit has
        // not confirmed during this response; doing so creates dead profile and
        // collection cards when an old snapshot outlives its canonical record.
        return { items: [], permanentlyInvalidRecipeIds: [] };
    }
}

function stableHomepageScore(value: string): number {
    return createHash("sha256").update(value).digest().readUInt32BE(0);
}

/** A daily ring position in the UUID index, independent of recipe age. */
export function homepageArchivePivot(rotationKey: string): string {
    const hash = createHash("sha256").update(`archive:${rotationKey}`).digest("hex");
    const uuid = `${hash.slice(0, 8)}-${hash.slice(8, 12)}-${hash.slice(12, 16)}-${hash.slice(16, 20)}-${hash.slice(20, 32)}`;
    // Existing snapshots can use either UUID case. Sample both key ranges.
    return parseInt(hash.slice(32, 34), 16) % 2 === 0 ? uuid.toUpperCase() : uuid;
}

export async function loadHomepageRecipeDocuments(collection: Query, rotationKey: string): Promise<{
    recent: QueryDocumentSnapshot[]; archive: QueryDocumentSnapshot[];
}> {
    const pivot = homepageArchivePivot(rotationKey);
    const archiveQuery = collection.orderBy(FieldPath.documentId());
    const [recent, tail] = await Promise.all([
        collection.orderBy("updatedAt", "desc").limit(24).get(),
        archiveQuery.startAt(pivot).limit(36).get(),
    ]);
    const head = tail.docs.length < 36
        ? await archiveQuery.endBefore(pivot).limit(36 - tail.docs.length).get()
        : null;
    return { recent: recent.docs, archive: [...tail.docs, ...(head?.docs ?? [])] };
}

/** Alternate fresh/archive choices, preferring underrepresented owners/categories. */
export function selectHomepageRecipeMix<T extends SanitizedRecipeShare>(
    recent: T[], archive: T[], rotationKey: string, maximumRecipes = 12
): T[] {
    const unique = new Map([...archive, ...recent].map((recipe) => [recipe.recipeId, recipe]));
    const recentIDs = new Set(recent.map((recipe) => recipe.recipeId));
    const owners = new Map<string, number>();
    const categories = new Map<string, number>();
    const result: T[] = [];
    const recipeCategories = (recipe: T) => [...new Set((recipe.tags ?? [])
        .map(canonicalRecipeCategoryName).filter((name): name is string => name !== null))];
    const categoryCount = (recipe: T) => Math.min(...(recipeCategories(recipe).length
        ? recipeCategories(recipe) : ["uncategorized"]).map((name) => categories.get(name) ?? 0));
    while (unique.size && result.length < maximumRecipes) {
        const remaining = [...unique.values()];
        const diverse = remaining.filter((recipe) => (owners.get(recipe.ownerId) ?? 0) < 2);
        const eligible = diverse.length ? diverse : remaining;
        const wantRecent = result.length % 2 === 0;
        const preferred = eligible.filter((recipe) => recentIDs.has(recipe.recipeId) === wantRecent);
        const pool = preferred.length ? preferred : eligible;
        pool.sort((lhs, rhs) => (owners.get(lhs.ownerId) ?? 0) - (owners.get(rhs.ownerId) ?? 0) ||
            categoryCount(lhs) - categoryCount(rhs) ||
            stableHomepageScore(`${rotationKey}:${lhs.recipeId}`) - stableHomepageScore(`${rotationKey}:${rhs.recipeId}`) ||
            lhs.recipeId.localeCompare(rhs.recipeId));
        const selected = pool[0];
        result.push(selected);
        unique.delete(selected.recipeId);
        owners.set(selected.ownerId, (owners.get(selected.ownerId) ?? 0) + 1);
        const names = recipeCategories(selected);
        for (const name of names.length ? names : ["uncategorized"]) categories.set(name, (categories.get(name) ?? 0) + 1);
    }
    return result;
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
            const imageRecordName = canonicalProfileImageRecordName(
                creator.profileEmoji,
                canonicalRecord.fields?.cloudProfileImageRecordName?.value
            );
            const profileImageURL = typeof imageRecordName === "string"
                ? await fetchPublicCloudKitProfileImage(imageRecordName, ownerId).catch((error) => {
                    logger.warn("CloudKit creator image lookup failed", { ownerId, error });
                    return null;
                })
                : null;
            return { ...creator, profileImageURL };
        });
        return identity;
    } catch (error) {
        logger.warn("CloudKit web recipe creator lookup failed", { ownerId, error });
        throw error;
    }
}

async function fetchPublicCloudKitProfileImage(
    recordName: string,
    ownerId: string
): Promise<string | null> {
    if (recordName !== `profileImage_${ownerId}`) {
        return null;
    }
    const keyID = cloudKitServerKeyID.value();
    const privateKey = cloudKitServerPrivateKey.value().replace(/\\n/g, "\n");
    const subpath = `/database/1/${CLOUDKIT_CONTAINER}/production/public/records/lookup`;
    const body = JSON.stringify({
        records: [{ recordName }],
        desiredKeys: ["userId", "imageAsset"],
    });
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
        throw new Error(`CloudKit profile image lookup returned ${response.status}`);
    }
    const payload = await response.json() as CloudKitRecordsPayload;
    const record = payload.records?.find((candidate) =>
        candidate.recordName === recordName && typeof candidate.serverErrorCode !== "string"
    );
    if (record?.recordType !== "ProfileImage" || record.fields?.userId?.value !== ownerId) {
        return null;
    }
    const asset = record.fields?.imageAsset?.value;
    const assetRecord = asset && typeof asset === "object" && !Array.isArray(asset)
        ? asset as Record<string, unknown>
        : null;
    const assetSize = typeof assetRecord?.size === "number" ? assetRecord.size : null;
    return assetSize !== null && assetSize <= 10_000_000
        ? safeCloudKitAssetURL(assetRecord?.downloadURL)
        : null;
}

async function queryCanonicalCloudKitProfileByOwner(ownerId: string): Promise<WebProfileContent | null> {
    const keyID = cloudKitServerKeyID.value();
    const privateKey = cloudKitServerPrivateKey.value().replace(/\\n/g, "\n");
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
        const message = `CloudKit profile lookup returned ${response.status}`;
        throw isTransientCloudKitHTTPStatus(response.status)
            ? new RetryableCloudKitError(message)
            : new Error(message);
    }
    const payload = await response.json() as CloudKitRecordsPayload;
    if (cloudKitQueryPayloadHasErrors(payload)) {
        const message = "CloudKit profile lookup returned a record error";
        throw cloudKitRecordsPayloadIsRetryableError(payload)
            ? new RetryableCloudKitError(message)
            : new Error(message);
    }
    const records = (payload.records ?? []).filter((record) =>
        typeof record.serverErrorCode !== "string"
    );
    const canonicalRecord = canonicalCloudKitOwnerRecord(records, ownerId);
    const creator = canonicalCloudKitRecipeCreator(records, ownerId);
    if (!canonicalRecord || !creator) {
        return null;
    }
    const usernameClaimCreatedAt = await verifyCloudKitUsernameClaim(
        creator.username,
        ownerId,
        canonicalRecord
    );
    if (usernameClaimCreatedAt === null) {
        return null;
    }
    const imageRecordName = canonicalProfileImageRecordName(
        creator.profileEmoji,
        canonicalRecord.fields?.cloudProfileImageRecordName?.value
    );
    const profileImageURL = typeof imageRecordName === "string"
        ? await fetchPublicCloudKitProfileImage(imageRecordName, ownerId).catch((error) => {
            logger.warn("CloudKit profile image lookup failed", { ownerId, error });
            return null;
        })
        : null;
    const creatorRecordName = canonicalRecord.created?.userRecordName;
    if (typeof creatorRecordName !== "string") {
        return null;
    }
    return { ...creator, userId: ownerId, usernameClaimCreatedAt, creatorRecordName, profileImageURL };
}

export function canonicalProfileImageRecordName(
    profileEmoji: unknown,
    cloudImageRecordName: unknown
): string | null {
    // Match the native canonical avatar rule: a surviving explicit emoji is
    // the user's intent after an interrupted legacy transition, so stale photo
    // metadata must not win on the web.
    if (typeof profileEmoji === "string" && profileEmoji.trim().length > 0) {
        return null;
    }
    return typeof cloudImageRecordName === "string" && cloudImageRecordName.length > 0
        ? cloudImageRecordName
        : null;
}

export function profileShareRequestMatchesCanonicalUsername(
    requestedShareId: string,
    canonicalUsername: string
): boolean {
    return uuidPattern.test(requestedShareId) ||
        requestedShareId.toLocaleLowerCase() === canonicalUsername.toLocaleLowerCase();
}

export function canonicalProfileURL(username: string): string {
    return `${PUBLIC_WEB_ORIGIN}/u/${encodeURIComponent(username.toLocaleLowerCase())}`;
}

export function canonicalProfileRedirectURL(
    requestedShareId: string,
    canonicalUsername: string
): string | null {
    return requestedShareId === canonicalUsername
        ? null
        : canonicalProfileURL(canonicalUsername);
}

async function ownerIDForCloudKitUsername(username: string): Promise<string | null> {
    const normalized = username.toLocaleLowerCase();
    if (!usernamePattern.test(normalized)) {
        return null;
    }
    const keyID = cloudKitServerKeyID.value();
    const privateKey = cloudKitServerPrivateKey.value().replace(/\\n/g, "\n");
    const subpath = `/database/1/${CLOUDKIT_CONTAINER}/production/public/records/lookup`;
    const body = JSON.stringify({ records: [{ recordName: `username_${normalized}` }] });
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
        throw new Error(`CloudKit username lookup returned ${response.status}`);
    }
    const payload = await response.json() as CloudKitRecordsPayload;
    const claim = payload.records?.find((record) =>
        record.recordName === `username_${normalized}` &&
        record.recordType === "UsernameClaim" &&
        typeof record.serverErrorCode !== "string"
    );
    const ownerId = claim?.fields?.userId?.value;
    return isValidUUID(ownerId) && claim?.fields?.username?.value === normalized
        ? ownerId
        : null;
}

async function fetchCanonicalCloudKitProfile(reference: string): Promise<WebProfileContent | null> {
    const ownerId = isValidUUID(reference)
        ? reference
        : await ownerIDForCloudKitUsername(reference);
    return ownerId ? queryCanonicalCloudKitProfileByOwner(ownerId) : null;
}

async function materializeCanonicalProfile(profile: WebProfileContent): Promise<void> {
    if (await isShareRevoked(profile.userId) ||
        await isResourcePrivacyBlocked("profile", profile.userId)) {
        return;
    }
    const profileRef = db.collection("shared_profiles").doc(profile.userId);
    const aliasRef = db.collection("shared_profiles").doc(profile.username);
    await db.runTransaction(async (transaction) => {
        const [revocation, privacyRoot, existingProfile, existingAlias] = await Promise.all([
            transaction.get(shareRevocationRef(profile.userId)),
            transaction.get(resourcePrivacyRootRef("profile", profile.userId)),
            transaction.get(profileRef),
            transaction.get(aliasRef),
        ]);
        if (revocation.exists && typeof revocation.data()?.restoredCapabilityHash !== "string") {
            return;
        }
        if (privacyRoot.data()?.blocked === true) {
            return;
        }
        const aliasOwner = existingAlias.data()?.ownerId;
        const aliasClaimCreatedAt = existingAlias.data()?.usernameClaimCreatedAt;
        if (existingAlias.exists && aliasOwner !== profile.userId &&
            typeof aliasClaimCreatedAt === "number" &&
            aliasClaimCreatedAt >= profile.usernameClaimCreatedAt) {
            return;
        }
        const canonicalProfileFields = {
            userId: profile.userId,
            ownerId: profile.userId,
            username: profile.username,
            displayName: profile.displayName,
            profileEmoji: profile.profileImageURL ? null : profile.profileEmoji,
            profileColor: profile.profileColor,
        };
        const existingProfileData = existingProfile.data();
        const profileChanged = !existingProfile.exists || Object.entries(canonicalProfileFields)
            .some(([key, value]) => existingProfileData?.[key] !== value);
        if (profileChanged) {
            transaction.set(profileRef, {
                ...canonicalProfileFields,
                updatedAt: FieldValue.serverTimestamp(),
            }, { merge: true });
        }
        const canonicalAliasFields = {
            ownerId: profile.userId,
            userId: profile.userId,
            redirectShareId: profile.userId,
            usernameClaimCreatedAt: profile.usernameClaimCreatedAt,
        };
        const existingAliasData = existingAlias.data();
        const aliasChanged = !existingAlias.exists || Object.entries(canonicalAliasFields)
            .some(([key, value]) => existingAliasData?.[key] !== value);
        if (aliasChanged) {
            transaction.set(aliasRef, {
                ...canonicalAliasFields,
                updatedAt: FieldValue.serverTimestamp(),
            });
        }
    });
}

async function materializeCanonicalRecipeSummaries(
    ownerId: string,
    expectedCreatorRecordName: string
): Promise<void> {
    if (await isShareRevoked(ownerId)) {
        return;
    }
    const stateRef = db.collection("share_maintenance").doc(`owner_recipes_${ownerId}`);
    const state = await stateRef.get();
    const lastMaterializedAt = state.data()?.lastMaterializedAt?.toMillis?.();
    if (typeof lastMaterializedAt === "number" && Date.now() - lastMaterializedAt < 6 * 60 * 60 * 1_000) {
        return;
    }

    // Never reconcile deletions from an incomplete or transient CloudKit read.
    // Retrying here keeps temporary service failures from becoming destructive
    // changes to the public snapshot index.
    const canonical = await retryTransientCloudKitOperation(() =>
        fetchCanonicalCloudKitRecipesByOwner(ownerId, expectedCreatorRecordName)
    );
    const blocked = new Set<string>();
    for (let index = 0; index < canonical.recipes.length; index += 100) {
        const chunk = canonical.recipes.slice(index, index + 100);
        const privacy = await db.getAll(...chunk.map((recipe) =>
            resourcePrivacyRootRef("recipe", recipe.recipeId)
        ));
        privacy.forEach((snapshot, privacyIndex) => {
            if (snapshot.data()?.blocked === true) {
                blocked.add(chunk[privacyIndex].recipeId);
            }
        });
    }
    const publishable = canonical.recipes.filter((recipe) => !blocked.has(recipe.recipeId));
    const canonicalIDs = new Set(publishable.map((recipe) => recipe.recipeId));
    const existing = await db.collection("shared_recipes").where("ownerId", "==", ownerId).get();

    const existingByID = new Map(existing.docs.map((document) => [document.id, document] as const));
    type MaterializationMutation = {
        kind: "upsert" | "delete";
        recipeId: string;
        recipe?: WebRecipeContent;
        observedUpdateTime: number | null;
    };
    const operations: MaterializationMutation[] = publishable.flatMap((recipe) => {
        const existingDocument = existingByID.get(recipe.recipeId);
        const existingData = existingDocument?.data();
        const unchanged = existingDocument?.exists === true &&
            existingData?.recipeId === recipe.recipeId &&
            existingData?.ownerId === ownerId &&
            existingData?.title === recipe.title &&
            existingData?.totalMinutes === recipe.totalMinutes &&
            Array.isArray(existingData?.tags) &&
            existingData.tags.length === recipe.tags.length &&
            existingData.tags.every((tag: unknown, index: number) => tag === recipe.tags[index]);
        if (unchanged) {
            return [];
        }
        return [{
            kind: "upsert" as const,
            recipeId: recipe.recipeId,
            recipe,
            observedUpdateTime: existingDocument?.updateTime?.toMillis() ?? null,
        }];
    });
    if (canonical.complete) {
        operations.push(...existing.docs
            .filter((document) => !canonicalIDs.has(document.id))
            .map((document) => ({
                kind: "delete" as const,
                recipeId: document.id,
                observedUpdateTime: document.updateTime?.toMillis() ?? null,
            })));
    }
    for (let index = 0; index < operations.length; index += 75) {
        const chunk = operations.slice(index, index + 75);
        await db.runTransaction(async (transaction) => {
            const targetRefs = chunk.map((operation) =>
                db.collection("shared_recipes").doc(operation.recipeId)
            );
            const privacyRefs = chunk.map((operation) =>
                resourcePrivacyRootRef("recipe", operation.recipeId)
            );
            const [revocation, targets, privacy] = await Promise.all([
                transaction.get(shareRevocationRef(ownerId)),
                Promise.all(targetRefs.map((ref) => transaction.get(ref))),
                Promise.all(privacyRefs.map((ref) => transaction.get(ref))),
            ]);
            if (revocation.exists && typeof revocation.data()?.restoredCapabilityHash !== "string") {
                return;
            }
            chunk.forEach((operation, operationIndex) => {
                const target = targets[operationIndex];
                const targetUpdateTime = target.updateTime?.toMillis() ?? null;
                if (targetUpdateTime !== operation.observedUpdateTime) {
                    return;
                }
                if (operation.kind === "delete") {
                    if (target.exists && target.data()?.ownerId === ownerId) {
                        transaction.delete(target.ref);
                    }
                    return;
                }
                const recipe = operation.recipe;
                if (!recipe || privacy[operationIndex].data()?.blocked === true ||
                    (target.exists && target.data()?.ownerId !== ownerId)) {
                    return;
                }
                transaction.set(target.ref, {
                    recipeId: recipe.recipeId,
                    ownerId,
                    title: recipe.title,
                    totalMinutes: recipe.totalMinutes,
                    tags: recipe.tags,
                    updatedAt: FieldValue.serverTimestamp(),
                }, { merge: true });
            });
        });
    }
    await db.runTransaction(async (transaction) => {
        const revocation = await transaction.get(shareRevocationRef(ownerId));
        if (revocation.exists && typeof revocation.data()?.restoredCapabilityHash !== "string") {
            return;
        }
        transaction.set(stateRef, {
            lastMaterializedAt: FieldValue.serverTimestamp(),
            recipeCount: publishable.length,
            complete: canonical.complete,
        }, { merge: true });
    });
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

function sanitizedUUIDList(value: unknown, maximumCount = MAX_RECIPE_IDS_PER_COLLECTION): string[] {
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
        if (ids.length >= maximumCount) {
            break;
        }
    }

    return ids;
}

export function sanitizeOwnerManifestInput(
    input: Record<string, unknown>
): ValidationResult<SanitizedOwnerManifest> {
    if (!isValidUUID(input.ownerId)) {
        return { ok: false, error: "ownerId must be a UUID" };
    }
    const capability = sanitizedCapability(input.capability);
    const identityRecordName = sanitizedRecordName(input.identityRecordName);
    if (!capability || !identityRecordName) {
        return { ok: false, error: "a valid management capability is required" };
    }
    const publicRecipeIds = sanitizedUUIDList(input.publicRecipeIds, 5_000);
    const publicCollectionIds = sanitizedUUIDList(input.publicCollectionIds, 2_000);
    if ((Array.isArray(input.publicRecipeIds) && publicRecipeIds.length !== input.publicRecipeIds.length) ||
        (Array.isArray(input.publicCollectionIds) && publicCollectionIds.length !== input.publicCollectionIds.length)) {
        return { ok: false, error: "public manifests must contain unique UUIDs" };
    }
    if (!Array.isArray(input.publicRecipeIds) || !Array.isArray(input.publicCollectionIds)) {
        return { ok: false, error: "public manifests are required" };
    }
    return {
        ok: true,
        value: {
            ownerId: input.ownerId,
            identityRecordName,
            capability,
            publicRecipeIds,
            publicCollectionIds,
        },
    };
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

export function revocationCreatorMatches(
    revokedIdentityRecordName: unknown,
    suppliedIdentityRecordName: string
): boolean {
    return typeof revokedIdentityRecordName === "string" &&
        revokedIdentityRecordName === suppliedIdentityRecordName;
}

export function restorationRevocationIsValid(
    revocationExists: boolean,
    revokedCapabilityHash: unknown,
    revokedIdentityRecordName: unknown,
    suppliedCapabilityHash: string,
    suppliedIdentityRecordName: string
): boolean {
    return revocationExists &&
        typeof revokedCapabilityHash === "string" &&
        revokedCapabilityHash !== suppliedCapabilityHash &&
        revocationCreatorMatches(revokedIdentityRecordName, suppliedIdentityRecordName);
}

async function beginAccountMutation(
    ownerId: string,
    intent: "unshare" | "restore",
    suppliedHash: string,
    identityRecordName?: string
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
        } else if (!identityRecordName || !restorationRevocationIsValid(
            revocation.exists,
            revocation.data()?.revokedCapabilityHash,
            revocation.data()?.identityRecordName,
            suppliedHash,
            identityRecordName
        )) {
            throw new ShareAuthorizationError();
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

function ownerManifestStateRef(ownerId: string): DocumentReference {
    return db.collection("share_owner_manifest_states").doc(ownerId);
}

export function ownerManifestStateMatches(
    state: Record<string, unknown> | undefined,
    generation: number,
    suppliedHash: string
): boolean {
    return state?.generation === generation && state?.capabilityHash === suppliedHash;
}

async function beginOwnerManifestReconciliation(
    ownerId: string,
    suppliedHash: string,
    manifestHash: string
): Promise<number> {
    const stateRef = ownerManifestStateRef(ownerId);
    return db.runTransaction(async (transaction) => {
        const [state, revocation] = await Promise.all([
            transaction.get(stateRef),
            transaction.get(shareRevocationRef(ownerId)),
        ]);
        if (revocationBlocksCapability(revocation, suppliedHash)) {
            throw new ShareAuthorizationError();
        }
        const generation = (typeof state.data()?.generation === "number"
            ? state.data()!.generation
            : 0) + 1;
        transaction.set(stateRef, {
            generation,
            capabilityHash: suppliedHash,
            manifestHash,
            updatedAt: FieldValue.serverTimestamp(),
        });
        return generation;
    });
}

async function canonicalPublicResourceIDs(
    kind: "recipe" | "collection",
    candidates: Array<{ id: string; ownerId: string }>
): Promise<Set<string>> {
    const keyID = cloudKitServerKeyID.value();
    const privateKey = cloudKitServerPrivateKey.value().replace(/\\n/g, "\n");
    const valid = new Set<string>();
    const canonicalOwners = await Promise.all([...new Set(candidates.map((candidate) => candidate.ownerId))]
        .map((ownerId) => fetchCanonicalCloudKitProfile(ownerId)));
    const canonicalCreatorRecordNamesByOwner = new Map(canonicalOwners.flatMap((owner) =>
        owner ? [[owner.userId, owner.creatorRecordName] as const] : []
    ));
    for (let index = 0; index < candidates.length; index += 150) {
        const chunk = candidates.slice(index, index + 150);
        const payload = await retryTransientCloudKitOperation(async () => {
            const subpath = `/database/1/${CLOUDKIT_CONTAINER}/production/public/records/lookup`;
            const body = JSON.stringify({ records: chunk.map((candidate) => ({ recordName: candidate.id })) });
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
                const message = `CloudKit manifest validation returned ${response.status}`;
                throw isTransientCloudKitHTTPStatus(response.status)
                    ? new RetryableCloudKitError(message)
                    : new Error(message);
            }
            const value = await response.json() as CloudKitRecordsPayload;
            if (cloudKitRecordsPayloadDisposition(value) === "error") {
                const message = "CloudKit manifest validation returned a record error";
                throw cloudKitRecordsPayloadIsRetryableError(value)
                    ? new RetryableCloudKitError(message)
                    : new Error(message);
            }
            const nonMissingRecordError = (value.records ?? []).find((record) => {
                const code = typeof record.serverErrorCode === "string"
                    ? record.serverErrorCode.toUpperCase()
                    : null;
                return code !== null && !missingCloudKitRecordCodes.has(code);
            });
            if (nonMissingRecordError) {
                const retryable = typeof nonMissingRecordError.serverErrorCode === "string" &&
                    transientCloudKitRecordCodes.has(nonMissingRecordError.serverErrorCode.toUpperCase());
                const message = "CloudKit manifest validation returned a per-record error";
                throw retryable ? new RetryableCloudKitError(message) : new Error(message);
            }
            return value;
        });
        const recordsByName = new Map((payload.records ?? []).flatMap((record) =>
            typeof record.recordName === "string" && typeof record.serverErrorCode !== "string"
                ? [[record.recordName, record] as const]
                : []
        ));
        for (const candidate of chunk) {
            const record = recordsByName.get(candidate.id);
            const expectedCreatorRecordName = canonicalCreatorRecordNamesByOwner.get(candidate.ownerId);
            const canonical = record && expectedCreatorRecordName && (kind === "recipe"
                ? sanitizeCloudKitRecipeForWeb(
                    record,
                    candidate.id,
                    candidate.ownerId,
                    expectedCreatorRecordName
                )
                : sanitizeCloudKitCollectionForWeb(
                    record,
                    candidate.id,
                    candidate.ownerId,
                    expectedCreatorRecordName
                ));
            if (canonical) {
                valid.add(candidate.id);
            }
        }
    }
    return valid;
}

async function deleteSnapshotsAbsentFromOwnerManifest(
    kind: "recipe" | "collection",
    ownerId: string,
    desiredIDs: Set<string>,
    generation: number,
    suppliedHash: string
): Promise<number> {
    const collectionName = kind === "recipe" ? "shared_recipes" : "shared_collections";
    const idField = kind === "recipe" ? "recipeId" : "collectionId";
    const snapshot = await db.collection(collectionName).where("ownerId", "==", ownerId).get();
    const absentCandidates = snapshot.docs.filter((document) => !desiredIDs.has(document.id));
    // The app manifest can race a newer device. Preserve canonical roots that
    // are missing from this device, while allowing canonical related children
    // to disappear from the derived web index. The owner query uses the same
    // graph reduction as native profile shelves; incomplete queries fail safe
    // to the per-record preservation check.
    const absentResources = absentCandidates.flatMap((document) => {
        const owner = document.data()?.ownerId;
        return typeof owner === "string" ? [{ id: document.id, ownerId: owner }] : [];
    });
    let stillCanonical: Set<string>;
    if (kind === "recipe" && absentResources.length > 0) {
        const canonicalOwner = await fetchCanonicalCloudKitProfile(ownerId);
        if (canonicalOwner) {
            const canonicalRecipes = await fetchCanonicalCloudKitRecipesByOwner(
                ownerId,
                canonicalOwner.creatorRecordName
            );
            stillCanonical = canonicalRecipes.complete
                ? new Set(canonicalRecipes.recipes.map((recipe) => recipe.recipeId))
                : await canonicalPublicResourceIDs(kind, absentResources);
        } else {
            stillCanonical = new Set();
        }
    } else {
        stillCanonical = await canonicalPublicResourceIDs(kind, absentResources);
    }
    const stale = absentCandidates.filter((document) => !stillCanonical.has(document.id));
    let deleted = 0;
    for (let index = 0; index < stale.length; index += 250) {
        const chunk = stale.slice(index, index + 250);
        deleted += await db.runTransaction(async (transaction) => {
            const [state, revocation, ...currentDocuments] = await Promise.all([
                transaction.get(ownerManifestStateRef(ownerId)),
                transaction.get(shareRevocationRef(ownerId)),
                ...chunk.map((document) => transaction.get(document.ref)),
            ]);
            if (!ownerManifestStateMatches(state.data(), generation, suppliedHash)) {
                throw new StaleShareMutationError();
            }
            if (revocationBlocksCapability(revocation, suppliedHash)) {
                throw new ShareAuthorizationError();
            }
            let transactionDeletes = 0;
            currentDocuments.forEach((document, documentIndex) => {
                const observed = chunk[documentIndex];
                if (!document.exists ||
                    document.data()?.ownerId !== ownerId ||
                    document.data()?.[idField] !== document.id ||
                    document.updateTime?.toMillis() !== observed.updateTime?.toMillis() ||
                    desiredIDs.has(document.id)) {
                    return;
                }
                transaction.delete(document.ref);
                transactionDeletes += 1;
            });
            return transactionDeletes;
        });
    }
    return deleted;
}

export const reconcileOwnerPublicWebV2 = onRequest(cloudAuthorizedHTTPOptions, async (req, res) => {
    if (req.method !== "POST") {
        res.status(405).send("Method Not Allowed");
        return;
    }
    if (!await enforceMutationRateLimit(req)) {
        rejectRateLimitedMutation(res);
        return;
    }
    try {
        const sanitized = sanitizeOwnerManifestInput(req.body ?? {});
        if (!sanitized.ok) {
            res.status(400).json({ error: sanitized.error });
            return;
        }
        const manifest = sanitized.value;
        if (!await verifyCloudKitAuthority(
            manifest.identityRecordName,
            manifest.ownerId,
            manifest.capability
        )) {
            throw new ShareAuthorizationError();
        }
        const suppliedHash = capabilityHash(manifest.capability);
        const manifestHash = createHash("sha256").update(JSON.stringify({
            recipes: [...manifest.publicRecipeIds].sort(),
            collections: [...manifest.publicCollectionIds].sort(),
        })).digest("hex");
        const generation = await beginOwnerManifestReconciliation(
            manifest.ownerId,
            suppliedHash,
            manifestHash
        );
        const [existingRecipeSnapshots, existingCollectionSnapshots] = await Promise.all([
            db.collection("shared_recipes").where("ownerId", "==", manifest.ownerId).get(),
            db.collection("shared_collections").where("ownerId", "==", manifest.ownerId).get(),
        ]);
        const existingRecipeIDs = new Set(existingRecipeSnapshots.docs.map((document) => document.id));
        const existingCollectionIDs = new Set(existingCollectionSnapshots.docs.map((document) => document.id));
        const missingRecipeIds = manifest.publicRecipeIds.filter((id) => !existingRecipeIDs.has(id));
        const missingCollectionIds = manifest.publicCollectionIds.filter((id) => !existingCollectionIDs.has(id));
        const deletedRecipes = await deleteSnapshotsAbsentFromOwnerManifest(
            "recipe",
            manifest.ownerId,
            new Set(manifest.publicRecipeIds),
            generation,
            suppliedHash
        );
        const deletedCollections = await deleteSnapshotsAbsentFromOwnerManifest(
            "collection",
            manifest.ownerId,
            new Set(manifest.publicCollectionIds),
            generation,
            suppliedHash
        );
        res.status(200).json({
            success: true,
            manifestHash,
            deletedRecipes,
            deletedCollections,
            missingRecipeIds,
            missingCollectionIds,
        });
    } catch (error) {
        if (error instanceof StaleShareMutationError) {
            res.status(409).json({ error: "A newer public manifest superseded this request" });
            return;
        }
        if (error instanceof ShareAuthorizationError) {
            res.status(403).json({ error: "Share capability or owner mismatch" });
            return;
        }
        logger.error("Error reconciling public owner manifest", error);
        res.status(500).json({ error: "Failed to reconcile public web content" });
    }
});

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
        const shareUrl = `${PUBLIC_WEB_ORIGIN}/recipe/${shareId}`;

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
                canonicalProfileURL(share.username),
                false
            ));
            return;
        }

        // Historical alias documents intentionally remain in place. CloudKit
        // preserves the matching UsernameClaim for the life of the account, so
        // an old /u/{username} URL can safely redirect to the current handle.
        const shareUrl = canonicalProfileURL(share.username);

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
                identityRecordName,
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
        const accountGeneration = await beginAccountMutation(
            userId,
            "restore",
            suppliedHash,
            identityRecordName
        );
        await deleteAllSnapshotsForOwnerAtGeneration(userId, accountGeneration);
        await db.runTransaction(async (transaction) => {
            const state = await transaction.get(accountMutationRef(userId));
            const revocationRef = shareRevocationRef(userId);
            const revocation = await transaction.get(revocationRef);
            requireCurrentResourceMutation(state, accountGeneration);
            const revokedHash = revocation.data()?.revokedCapabilityHash;
            if (!restorationRevocationIsValid(
                revocation.exists,
                revokedHash,
                revocation.data()?.identityRecordName,
                suppliedHash,
                identityRecordName
            )) {
                throw new ShareAuthorizationError();
            }
            transaction.set(revocationRef, {
                ownerId: userId,
                identityRecordName,
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

        const shareUrl = `${PUBLIC_WEB_ORIGIN}/collection/${shareId}`;

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

async function deleteSnapshotIfUnchanged(
    collectionName: string,
    snapshot: DocumentSnapshot,
    expectedOwnerId: string
): Promise<void> {
    const updateTimeMillis = snapshot.updateTime?.toMillis();
    if (typeof updateTimeMillis !== "number") {
        return;
    }
    await db.runTransaction(async (transaction) => {
        const current = await transaction.get(db.collection(collectionName).doc(snapshot.id));
        if (current.exists && current.data()?.ownerId === expectedOwnerId &&
            current.updateTime?.toMillis() === updateTimeMillis) {
            transaction.delete(current.ref);
        }
    });
}

// Generic Data Fetcher
export const api = onRequest(cloudBackedPublicReadHTTPOptions, async (req, res) => {
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
            if (!doc.exists && type === "profile") {
                const canonicalProfile = await fetchCanonicalCloudKitProfile(shareId);
                if (canonicalProfile) {
                    await materializeCanonicalProfile(canonicalProfile);
                    doc = await db.collection(collectionName).doc(
                        isValidUUID(shareId) ? shareId : canonicalProfile.username
                    ).get();
                }
            }
            if (!doc.exists) {
                res.status(404).json({ error: 'Share not found' });
                return;
            }

            const requestedProfileDocument = type === "profile" ? doc : null;
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
                const canonicalRecipe = await fetchPublicCloudKitRecipe(
                    sanitized.value.recipeId,
                    sanitized.value.ownerId
                );
                if (!canonicalRecipe) {
                    await deleteSnapshotIfUnchanged(collectionName, doc, sanitized.value.ownerId);
                    res.status(404).json({ error: "Share not found" });
                    return;
                }
                publicData = publicWebRecipeData(canonicalRecipe);
            } else if (type === "profile") {
                const sanitized = sanitizeStoredProfileShareInput(rawData);
                if (!sanitized.ok) {
                    res.status(404).json({ error: "Share not found" });
                    return;
                }
                const canonicalProfile = await fetchCanonicalCloudKitProfile(sanitized.value.userId);
                if (!canonicalProfile) {
                    if (requestedProfileDocument) {
                        await deleteSnapshotIfUnchanged(
                            collectionName,
                            requestedProfileDocument,
                            sanitized.value.userId
                        );
                    }
                    res.status(404).json({ error: "Share not found" });
                    return;
                }
                const requestedAliasOwnerId = uuidPattern.test(shareId) ||
                    shareId.toLocaleLowerCase() === canonicalProfile.username.toLocaleLowerCase()
                    ? sanitized.value.userId
                    : await ownerIDForCloudKitUsername(shareId);
                if (requestedAliasOwnerId !== sanitized.value.userId) {
                    if (requestedProfileDocument) {
                        await deleteSnapshotIfUnchanged(
                            collectionName,
                            requestedProfileDocument,
                            sanitized.value.userId
                        );
                    }
                    res.status(404).json({ error: "Share not found" });
                    return;
                }
                await materializeCanonicalProfile(canonicalProfile);
                publicData = {
                    userId: canonicalProfile.userId,
                    ownerId: canonicalProfile.userId,
                    username: canonicalProfile.username,
                    displayName: canonicalProfile.displayName,
                    profileImageURL: canonicalProfile.profileImageURL,
                };
            } else {
                const sanitized = sanitizeStoredCollectionShareInput(rawData);
                if (!sanitized.ok) {
                    res.status(404).json({ error: "Share not found" });
                    return;
                }
                const canonicalCollection = await fetchPublicCloudKitCollection(
                    sanitized.value.collectionId,
                    sanitized.value.ownerId
                );
                if (!canonicalCollection) {
                    await deleteSnapshotIfUnchanged(collectionName, doc, sanitized.value.ownerId);
                    res.status(404).json({ error: "Share not found" });
                    return;
                }
                publicData = {
                    collectionId: canonicalCollection.collectionId,
                    ownerId: canonicalCollection.ownerId,
                    title: canonicalCollection.title,
                    recipeCount: canonicalCollection.recipeIds.length,
                    recipeIds: canonicalCollection.recipeIds,
                };
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
    const fallbackImageURL = `${PUBLIC_WEB_ORIGIN}/social-card.png`;
    const metaImageURL = safeImageURL(imageURL) || fallbackImageURL;
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
        
        ${metaImageURL !== fallbackImageURL ? `<img src="${safeMetaImageURL}" alt="${safeTitle}" class="preview-image" onerror="this.style.display='none'">` : ''}
        
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
    avatarImageURL?: string | null;
};

function compactPageStyles(): string {
    return `<style>
        :root { color-scheme:light dark; --paper:#F6F1EA; --ink:#241A14; --muted:#756A62; --accent:#E6801A; --accent-text:#995100; --surface:#FFFFFF; --separator:#E5DDD2; --control:rgba(255,255,255,.72); }
        @media (prefers-color-scheme:dark) { :root { --paper:#18120D; --ink:#F8F0E8; --muted:#B5AAA2; --accent:#F09837; --accent-text:#FFB45F; --surface:#262220; --separator:#39332F; --control:rgba(49,44,40,.7); } }
        * { box-sizing:border-box; }
        html { background:var(--paper); }
        body { margin:0; min-height:100svh; background:var(--paper); color:var(--ink); font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif; -webkit-font-smoothing:antialiased; text-rendering:optimizeLegibility; }
        main,.site-footer { width:min(1120px,calc(100% - 48px)); margin-inline:auto; }
        .action { min-height:42px; display:inline-flex; align-items:center; justify-content:center; padding:9px 14px; border:1px solid color-mix(in srgb,var(--separator) 82%,transparent); border-radius:999px; background:var(--control); color:var(--ink); box-shadow:0 1px 0 rgba(255,255,255,.24) inset,0 5px 18px rgba(37,25,17,.06); -webkit-backdrop-filter:blur(20px) saturate(180%); backdrop-filter:blur(20px) saturate(180%); font-size:13px; font-weight:500; text-decoration:none; }
        main { margin-top:46px; margin-bottom:104px; }
        .intro { max-width:720px; }
        .identity { display:flex; align-items:center; gap:18px; }
        .identity-text { min-width:0; }
        .profile-avatar { width:58px; height:58px; flex:0 0 58px; display:grid; place-items:center; overflow:hidden; border-radius:50%; background:color-mix(in srgb,var(--avatar-color) 18%,transparent); font-size:27px; }
        .profile-avatar img { width:100%; height:100%; display:block; object-fit:cover; }
        h1 { margin:0; font-family:"New York",ui-serif,"Iowan Old Style",Palatino,Georgia,serif; font-size:clamp(40px,6vw,60px); font-weight:500; line-height:1.02; letter-spacing:-.035em; overflow-wrap:anywhere; }
        .handle { margin:8px 0 0; color:var(--muted); font-size:14px; font-weight:400; }
        .description { max-width:48ch; margin:18px 0 0; color:var(--muted); font-size:16px; line-height:1.55; }
        .meta { display:flex; flex-wrap:wrap; gap:10px 16px; margin:22px 0 0; padding:0; color:var(--muted); list-style:none; font-size:13px; }
        .action { width:max-content; margin-top:26px; background:var(--accent); color:#28160A; border-color:transparent; }
        .download-action { min-height:42px; width:max-content; margin:26px 0 0 12px; display:inline-flex; align-items:center; color:var(--muted); font-size:13px; font-weight:400; text-decoration:none; }
        .shelf { margin-top:62px; }
        .count { margin:0 0 18px; color:var(--muted); font-size:13px; font-weight:400; }
        .recipe-list { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:36px 18px; margin:0; padding:0; list-style:none; }
        .recipe-list li { min-width:0; }
        .recipe-row { display:block; color:inherit; text-decoration:none; }
        .recipe-media { position:relative; aspect-ratio:4/3; display:grid; place-items:center; overflow:hidden; border-radius:16px; background:color-mix(in srgb,var(--accent) 8%,var(--surface)); }
        .recipe-photo { width:100%; height:100%; grid-area:1/1; display:block; object-fit:cover; transition:transform .24s ease; }
        .recipe-placeholder { grid-area:1/1; }
        .recipe-placeholder,.recipe-placeholder img { width:38px; height:38px; display:block; opacity:.72; }
        .recipe-copy { display:block; padding:11px 2px 0; }
        .recipe-name { display:-webkit-box; min-height:2.4em; overflow:hidden; font-family:"New York",ui-serif,"Iowan Old Style",Palatino,Georgia,serif; font-size:19px; font-weight:500; line-height:1.2; overflow-wrap:anywhere; -webkit-box-orient:vertical; -webkit-line-clamp:2; }
        .recipe-meta { min-height:19px; display:flex; align-items:center; gap:9px; margin-top:6px; color:var(--muted); font-size:12px; font-weight:400; }
        .recipe-tag { --tag-color:#FF9933; --tag-color-dark:#FF9933; display:inline-flex; align-items:center; gap:4px; color:color-mix(in srgb,var(--tag-color) 40%,#3A210A); }
        @media (prefers-color-scheme:dark) { .recipe-tag { color:color-mix(in srgb,var(--tag-color-dark) 55%,white); } }
        .empty { margin:0; color:var(--muted); font-size:16px; }
        .compact-recipe { max-width:720px; }
        .compact-recipe .meta { margin-top:24px; }
        .site-footer { display:flex; justify-content:space-between; gap:20px; padding:24px 0 30px; border-top:1px solid var(--separator); color:var(--muted); font-size:12px; }
        .site-footer nav { display:flex; gap:18px; }
        .site-footer a { color:inherit; text-decoration:none; }
        a:focus-visible { outline:3px solid color-mix(in srgb,var(--accent) 78%,white); outline-offset:4px; }
        @media (hover:hover) { .recipe-row:hover .recipe-name,.site-footer a:hover { color:var(--accent-text); } .recipe-row:hover .recipe-photo { transform:scale(1.018); } .action:hover,.bar-store:hover { filter:brightness(.98); } }
        @media (max-width:760px) { .recipe-list { grid-template-columns:repeat(2,minmax(0,1fr)); } }
        @media (max-width:520px) { main,.site-footer { width:min(calc(100% - 32px),560px); } main { margin-top:28px; margin-bottom:72px; } .recipe-list { gap:30px 12px; } .shelf { margin-top:52px; } .identity { align-items:flex-start; } .recipe-name { font-size:17px; } .site-footer { align-items:flex-start; flex-direction:column-reverse; } }
        @media print { :root { --paper:#fff; --ink:#000; --muted:#444; --accent-text:#7A330E; } .bar,.action,.download-action,.site-footer { display:none; } main { width:100%; margin:0; } .shelf { margin-top:48px; } }
    </style>`;
}

function faviconHeadLinks(): string {
    return `<link rel="icon" href="/favicon.svg" type="image/svg+xml"><link rel="alternate icon" href="/favicon.ico" sizes="any"><link rel="apple-touch-icon" href="/apple-touch-icon.png">`;
}

function compactPageHead(title: string, description: string, canonicalURL: string, openGraphType: "profile" | "website" = "website"): string {
    const safeTitle = escapeHtml(title);
    const safeDescription = escapeHtml(description);
    const safeCanonicalURL = escapeHtml(canonicalURL);
    return `<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"><meta name="theme-color" content="#F6F1EA" media="(prefers-color-scheme: light)"><meta name="theme-color" content="#18120D" media="(prefers-color-scheme: dark)">${faviconHeadLinks()}<title>${safeTitle} · Cauldron</title><meta name="description" content="${safeDescription}"><link rel="canonical" href="${safeCanonicalURL}"><meta property="og:type" content="${openGraphType}"><meta property="og:title" content="${safeTitle}"><meta property="og:description" content="${safeDescription}"><meta property="og:image" content="${PUBLIC_WEB_ORIGIN}/social-card.png"><meta property="og:url" content="${safeCanonicalURL}"><meta property="og:site_name" content="Cauldron"><meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="${safeTitle}"><meta name="twitter:description" content="${safeDescription}"><meta name="twitter:image" content="${PUBLIC_WEB_ORIGIN}/social-card.png"><meta name="apple-itunes-app" content="app-id=6754004943, app-argument=${safeCanonicalURL}">${compactPageStyles()}${publicHeaderStyles()}`;
}

function publicHeaderStyles(): string {
    return `<style data-cauldron-header>
        .site-header { height:82px; min-height:82px; width:100%; margin:0; padding:0; color:#241A14; }
        .site-header-inner { width:min(1220px,calc(100% - 48px)); height:100%; margin-inline:auto; display:flex; align-items:center; justify-content:space-between; gap:20px; }
        .site-brand { display:inline-flex; align-items:center; gap:10px; color:inherit; text-decoration:none; }
        .site-brand picture,.site-brand img { display:block; width:34px; height:34px; object-fit:contain; }
        .site-brand span { font-family:"New York",ui-serif,"Iowan Old Style",Georgia,serif; font-size:20px; font-weight:500; letter-spacing:-.015em; }
        .site-store { min-height:44px; display:inline-flex; align-items:center; justify-content:center; flex-shrink:0; padding:9px 14px; border:1px solid rgba(229,221,210,.82); border-radius:999px; background:rgba(255,255,255,.72); color:inherit; box-shadow:0 1px 0 rgba(255,255,255,.24) inset,0 5px 18px rgba(37,25,17,.05); -webkit-backdrop-filter:blur(20px) saturate(180%); backdrop-filter:blur(20px) saturate(180%); font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif; font-size:13px; font-weight:500; text-decoration:none; }
        .site-header a:focus-visible { outline:3px solid #E6801A; outline-offset:4px; }
        @media(max-width:700px) { .site-header { height:70px; min-height:70px; } .site-header-inner { width:calc(100% - 32px); } }
        @media(prefers-color-scheme:dark) { .site-header { color:#F8F0E8; } .site-store { border-color:rgba(57,51,47,.82); background:rgba(49,44,40,.7); } }
        @media print { .site-header { display:none; } }
    </style>`;
}

function compactBrandHeader(): string {
    return `<header class="site-header"><div class="site-header-inner"><a class="site-brand" href="/" aria-label="Cauldron home"><picture><source media="(prefers-color-scheme: dark)" srcset="/icon-small-dark.svg"><img src="/icon-small-light.svg" alt="" aria-hidden="true"></picture><span>Cauldron</span></a><a class="site-store" href="https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943">Get Cauldron</a></div></header>`;
}

function compactPageFooter(): string {
    return `<footer class="site-footer"><span>© ${new Date().getUTCFullYear()} Nadav Avital</span><nav aria-label="Footer"><a href="https://www.nadavavital.com/apps/support/?app=Cauldron">Support</a><a href="https://www.nadavavital.com/cauldron/privacy-policy/">Privacy</a></nav></footer>`;
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
    return `<!DOCTYPE html><html lang="en"><head>${compactPageHead(title, message, `${PUBLIC_WEB_ORIGIN}/`)}</head><body>${compactBrandHeader()}<main><article class="compact-recipe"><h1>${safeTitle}</h1><p class="description">${safeMessage}</p></article></main>${compactPageFooter()}</body></html>`;
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
    return `<!DOCTYPE html><html lang="en"><head>${compactPageHead(recipe.title, description, canonicalURL)}</head><body>${compactBrandHeader()}<main><article class="compact-recipe"><h1>${escapeHtml(recipe.title)}</h1>${metaHTML ? `<ul class="meta" aria-label="Recipe details">${metaHTML}</ul>` : ""}<a class="action" id="openCompactRecipe" href="${escapeHtml(appURL)}">Open in Cauldron</a><a class="download-action" href="${escapeHtml(downloadURL)}">Get the app</a></article></main>${compactPageFooter()}${appOpenFallbackScript("openCompactRecipe", appURL)}</body></html>`;
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
    return `<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"><meta name="theme-color" content="#F6F1EA">${faviconHeadLinks()}<title>${title} · Cauldron</title><meta name="description" content="${safeDescription}"><link rel="canonical" href="${safeCanonicalURL}"><meta property="og:type" content="article"><meta property="og:title" content="${title}"><meta property="og:description" content="${safeDescription}"><meta property="og:image" content="${previewImage}"><meta property="og:image:secure_url" content="${previewImage}"><meta property="og:image:alt" content="${previewImageAlt}"><meta property="og:url" content="${safeCanonicalURL}"><meta property="og:site_name" content="Cauldron"><meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="${title}"><meta name="twitter:description" content="${safeDescription}"><meta name="twitter:image" content="${previewImage}"><meta name="twitter:image:alt" content="${previewImageAlt}"><meta name="apple-itunes-app" content="app-id=6754004943, app-argument=${safeCanonicalURL}"><script type="application/ld+json">${structuredData}</script>`;
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
        const imageURL = safeCloudKitAssetURL(creator.profileImageURL);
        const avatarHTML = imageURL
            ? `<span class="creator-avatar" aria-hidden="true"><img src="${escapeHtml(imageURL)}" alt="" referrerpolicy="no-referrer"></span>`
            : `<span class="creator-avatar" style="--avatar-color:${avatarColor}" aria-hidden="true">${escapeHtml(avatar)}</span>`;
        return `<a class="creator" href="/u/${encodeURIComponent(creator.username)}">${avatarHTML}<span class="creator-copy"><strong>${escapeHtml(creator.displayName)}</strong><small>@${escapeHtml(creator.username)}</small></span></a>`;
    })() : "";
    const ingredientsClass = recipe.ingredients.length <= 12 ? "ingredients-column sticky-eligible" : "ingredients-column";
    const safeCanonicalJSON = JSON.stringify(canonicalURL).replace(/</g, "\\u003c");

    return `<!DOCTYPE html><html lang="en"><head>${recipePageHead(recipe, description, canonicalURL)}<style>
        :root { color-scheme:light dark; --paper:#F6F1EA; --ink:#1C1C1E; --muted:#6E6E73; --accent:#FF9933; --accent-text:#995100; --soft:#FFFFFF; }
        @media (prefers-color-scheme:dark) { :root { --paper:#18120D; --ink:#F2F2F7; --muted:#AEAEB2; --accent:#FF9933; --accent-text:#FFB45F; --soft:#262220; } .tags li { color:#FFD3A1; background:color-mix(in srgb,var(--tag-color-dark) 15%,transparent); } }
        * { box-sizing:border-box; }
        html { background:var(--paper); }
        body { margin:0; color:var(--ink); background:var(--paper); font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif; -webkit-font-smoothing:antialiased; }
        a { color:inherit; }
        .intro-action { border:1px solid color-mix(in srgb,var(--soft) 70%,transparent); box-shadow:0 1px 0 rgba(255,255,255,.22) inset,0 5px 18px rgba(37,25,17,.06); -webkit-backdrop-filter:blur(20px) saturate(180%); backdrop-filter:blur(20px) saturate(180%); }
        main { width:min(1180px,calc(100% - 64px)); margin:48px auto 120px; }
        .recipe-masthead { display:grid; grid-template-columns:minmax(0,1.42fr) minmax(320px,.78fr); gap:clamp(48px,7vw,96px); align-items:center; }
        .recipe-masthead.no-image { grid-template-columns:minmax(0,760px); min-height:360px; align-content:center; }
        .hero-media { min-width:0; }
        .hero-image { display:block; width:100%; aspect-ratio:5/4; max-height:720px; object-fit:cover; border-radius:14px; background:var(--soft); }
        .recipe-intro { padding:20px 0; }
        h1,h2,h3 { font-family:"New York",ui-serif,"Iowan Old Style",Palatino,Georgia,serif; }
        h1 { max-width:12ch; margin:0; font-size:clamp(44px,5.1vw,66px); font-weight:500; line-height:1.02; letter-spacing:-.038em; overflow-wrap:anywhere; }
        .creator { width:max-content; max-width:100%; margin-top:26px; display:flex; align-items:center; gap:11px; text-decoration:none; }
        .creator-avatar { width:36px; height:36px; flex:0 0 36px; display:grid; place-items:center; border-radius:50%; background:color-mix(in srgb,var(--avatar-color) 18%,transparent); font-size:18px; }
        .creator-copy { min-width:0; display:flex; gap:6px; align-items:baseline; }
        .creator strong { font-size:14px; font-weight:500; }
        .creator small { color:var(--muted); font-size:12px; }
        .meta { display:flex; flex-wrap:wrap; gap:18px; margin:28px 0 0; padding:0; list-style:none; color:var(--muted); }
        .meta li { display:flex; align-items:center; gap:7px; font-size:13px; font-weight:400; }
        .meta svg { width:15px; height:15px; fill:none; stroke:var(--accent-text); stroke-width:1.8; stroke-linecap:round; stroke-linejoin:round; }
        .tags { display:flex; flex-wrap:wrap; gap:8px; margin:15px 0 0; padding:0; list-style:none; }
        .tags li { display:flex; gap:5px; align-items:center; min-height:28px; padding:5px 10px; border-radius:999px; color:#5B3517; background:color-mix(in srgb,var(--tag-color) 15%,transparent); font-size:12px; font-weight:500; }
        .recipe-actions { margin-top:34px; display:flex; flex-wrap:wrap; align-items:center; gap:18px; }
        .intro-action { min-height:44px; display:inline-flex; align-items:center; padding:10px 16px; border-radius:999px; color:#2B1600; background:var(--accent); font-size:14px; font-weight:500; text-decoration:none; }
        .download-action { min-height:44px; display:inline-flex; align-items:center; color:var(--muted); font-size:13px; font-weight:400; text-decoration:none; }
        .share-action { min-height:44px; display:inline-flex; align-items:center; padding:10px 0; border:0; color:var(--muted); background:none; font:inherit; font-size:13px; font-weight:400; cursor:pointer; }
        .share-action:hover { color:var(--ink); }
        .share-status { color:var(--muted); font-size:12px; }
        .recipe-body { display:grid; grid-template-columns:minmax(320px,.85fr) minmax(0,1.65fr); gap:clamp(58px,8vw,108px); margin-top:88px; align-items:start; }
        .ingredients-column { min-width:0; }
        .section-title { margin:0 0 28px; font-size:27px; font-weight:500; letter-spacing:-.022em; }
        .ingredients { margin:0; padding:0; list-style:none; }
        .ingredient { width:100%; display:flex; align-items:flex-start; gap:10px; padding:8px 0; font-size:15px; line-height:1.5; }
        .ingredient > span:last-child { min-width:0; flex:1; overflow-wrap:anywhere; }
        .ingredient-dot { width:6px; height:6px; flex:0 0 6px; margin-top:8px; border-radius:50%; background:var(--accent); }
        .ingredient-amount { color:var(--muted); font-variant-numeric:tabular-nums; }
        .ingredient strong { font-weight:500; }
        .ingredient small { display:block; margin-top:2px; color:var(--muted); font-size:13px; }
        .section-label,.method-section { color:var(--accent-text); font-size:11px; font-weight:600; letter-spacing:.08em; text-transform:uppercase; }
        .section-label { padding:24px 0 5px; }
        .section-label:first-child { padding-top:0; }
        .method { max-width:720px; margin:0; padding:0; list-style:none; }
        .method-section { padding:30px 0 6px; }
        .method-section h3 { margin:0; color:inherit; font:inherit; overflow-wrap:anywhere; }
        .method-section:first-child { padding-top:0; }
        .step { display:grid; grid-template-columns:42px minmax(0,1fr); gap:16px; padding:0 0 26px; }
        .step-number { padding-top:4px; color:var(--accent-text); font-family:"New York",ui-serif,"Iowan Old Style",Palatino,Georgia,serif; font-size:13px; font-weight:600; font-variant-numeric:tabular-nums; }
        .step p { min-width:0; margin:0; font-size:17px; line-height:1.66; overflow-wrap:anywhere; }
        .site-footer { width:min(1180px,calc(100% - 64px)); margin:0 auto; display:flex; justify-content:space-between; gap:20px; padding:24px 0 30px; border-top:1px solid color-mix(in srgb,var(--muted) 22%,transparent); color:var(--muted); font-size:12px; }
        .site-footer nav { display:flex; gap:18px; }
        .site-footer a { color:inherit; text-decoration:none; }
        a:focus-visible,button:focus-visible { outline:3px solid color-mix(in srgb,var(--accent) 78%,white); outline-offset:4px; }
        @media (min-width:900px) and (min-height:720px) { .ingredients-column.sticky-eligible { position:sticky; top:32px; } }
        @media (max-width:820px) { main,.site-footer { width:min(calc(100% - 32px),680px); } main { margin:24px auto 80px; } .recipe-masthead { grid-template-columns:1fr; gap:30px; } .hero-image { aspect-ratio:4/3; border-radius:12px; } .recipe-intro { padding:0; } h1 { max-width:16ch; font-size:clamp(38px,10.5vw,54px); } .meta { margin-top:22px; } .recipe-actions { margin-top:28px; } .recipe-body { grid-template-columns:1fr; gap:58px; margin-top:72px; } .ingredients-column { position:static; } .method { max-width:none; } .site-footer { align-items:flex-start; flex-direction:column-reverse; } }
        @media (max-width:430px) { .creator-copy { flex-direction:column; gap:1px; align-items:flex-start; } }
        @media print { :root { --paper:#fff; --ink:#000; --muted:#444; --accent-text:#7A330E; } .topbar,.recipe-actions { display:none; } body { background:#fff; } main { width:100%; margin:0; } .recipe-masthead { grid-template-columns:42% 1fr; gap:32px; align-items:start; } .hero-image { max-height:360px; border-radius:0; } h1 { font-size:42px; } .recipe-body { grid-template-columns:34% 1fr; gap:44px; margin-top:48px; } .ingredients-column { position:static !important; } .step { break-inside:avoid; } }
    </style>${publicHeaderStyles()}</head><body>${compactBrandHeader()}<main><article><section class="recipe-masthead${recipe.imageURL ? "" : " no-image"}">${recipe.imageURL ? `<div class="hero-media"><img class="hero-image" src="${escapeHtml(recipe.imageURL)}" alt="${escapeHtml(recipe.title)}" fetchpriority="high"></div>` : ""}<header class="recipe-intro"><h1>${escapeHtml(recipe.title)}</h1>${creatorHTML}${metaHTML ? `<ul class="meta" aria-label="Recipe details">${metaHTML}</ul>` : ""}${tagsHTML ? `<ul class="tags" aria-label="Recipe tags">${tagsHTML}</ul>` : ""}<div class="recipe-actions"><a class="intro-action" id="openRecipe" href="${safeAppURL}">Open in Cauldron</a><a class="download-action" href="${escapeHtml(downloadURL)}">Get the app</a><button class="share-action" id="shareRecipe" type="button">Share</button><span class="share-status" id="shareStatus" role="status" aria-live="polite"></span></div></header></section><div class="recipe-body"><aside class="${ingredientsClass}"><h2 class="section-title">Ingredients</h2><ul class="ingredients">${ingredientsHTML || `<li class="ingredient"><span></span><span>Ingredients are being prepared.</span></li>`}</ul></aside><section class="instructions-column" aria-labelledby="instructions-title"><h2 class="section-title" id="instructions-title">Instructions</h2><ol class="method">${stepsHTML || `<li class="step"><span class="step-number">1</span><p>Open this recipe in Cauldron for the instructions.</p></li>`}</ol></section></div></article></main>${compactPageFooter()}<script>(function(){var button=document.getElementById("shareRecipe");var status=document.getElementById("shareStatus");var url=${safeCanonicalJSON};if(!button)return;button.addEventListener("click",async function(){try{if(navigator.share){await navigator.share({title:document.title,url:url});return;}await navigator.clipboard.writeText(url);button.textContent="Copied";if(status)status.textContent="Recipe link copied.";}catch(error){if(error&&error.name==="AbortError")return;if(status)status.textContent="Could not share this recipe.";}});})();</script>${appOpenFallbackScript("openRecipe", appURL)}</body></html>`;
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
        const placeholder = `<picture class="recipe-placeholder"><source media="(prefers-color-scheme: dark)" srcset="/icon-small-dark.svg"><img src="/icon-small-light.svg" alt="" aria-hidden="true"></picture>`;
        const media = verifiedImageURL
            ? `${placeholder}<img class="recipe-photo" src="${escapeHtml(verifiedImageURL)}" alt="" loading="lazy" decoding="async" referrerpolicy="no-referrer" onerror="this.remove()">`
            : placeholder;
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
    const avatarImageURL = safeCloudKitAssetURL(options.avatarImageURL);
    const avatarHTML = avatarImageURL
        ? `<span class="profile-avatar" aria-hidden="true"><img src="${escapeHtml(avatarImageURL)}" alt="" referrerpolicy="no-referrer"></span>`
        : options.avatarEmoji
            ? `<span class="profile-avatar" style="--avatar-color:${avatarColor}" aria-hidden="true">${escapeHtml(options.avatarEmoji)}</span>`
            : "";
    const identity = avatarHTML
        ? `<div class="identity">${avatarHTML}<div class="identity-text"><h1>${escapeHtml(options.title)}</h1>${handleHTML}</div></div>`
        : `<h1>${escapeHtml(options.title)}</h1>`;
    return `<!DOCTYPE html><html lang="en"><head>${compactPageHead(options.title, options.description, options.canonicalURL, options.openGraphType)}</head><body>${compactBrandHeader()}<main><section class="intro">${identity}<a class="action" id="openRecipeShelf" href="${safeAppURL}">Open in Cauldron</a><a class="download-action" href="${escapeHtml(options.downloadURL)}">Get the app</a></section><section class="shelf" aria-labelledby="recipe-count"><p class="count" id="recipe-count">${count} ${noun}</p>${rows ? `<ol class="recipe-list">${rows}</ol>` : `<p class="empty">No public recipes have been shared here yet.</p>`}</section></main>${compactPageFooter()}${appOpenFallbackScript("openRecipeShelf", options.appURL)}</body></html>`;
}

export function generateHomePageHtml(recipes: WebRecipeIndexItem[]): string {
    const visibleRecipes = recipes.flatMap((recipe) => {
        const imageURL = safeCloudKitAssetURL(recipe.imageURL);
        if (!imageURL) return [];
        const categoryNames = [...new Set(recipe.tags
            .map(canonicalRecipeCategoryName)
            .filter((name): name is string => name !== null))];
        const categoryName = categoryNames[0] ?? null;
        const category = categoryName ? recipeCategoryPresentation[categoryName] : null;
        return [{ recipe, imageURL, categoryNames, categoryName, category }];
    }).slice(0, 12);

    const categoryCounts = new Map<string, number>();
    visibleRecipes.forEach(({ categoryNames }) => {
        categoryNames.forEach((name) => categoryCounts.set(name, (categoryCounts.get(name) ?? 0) + 1));
    });
    const categories = [...categoryCounts.keys()]
        .sort((lhs, rhs) => (categoryCounts.get(rhs) ?? 0) - (categoryCounts.get(lhs) ?? 0) || lhs.localeCompare(rhs))
        .slice(0, 6);
    const filters = categories.map((name) => {
        const presentation = recipeCategoryPresentation[name];
        return `<button type="button" data-filter="${escapeHtml(name)}" aria-pressed="false"><span aria-hidden="true">${presentation.emoji}</span>${escapeHtml(name)}</button>`;
    }).join("");

    const recipeRows = visibleRecipes.map(({ recipe, imageURL, categoryNames, categoryName, category }, index) => {
        const tag = category && categoryName
            ? `<span class="recipe-tag" style="--tag-color:${category.light};--tag-color-dark:${category.dark}"><span aria-hidden="true">${category.emoji}</span>${escapeHtml(categoryName)}</span>`
            : "";
        const time = recipe.totalMinutes ? `<span>${recipe.totalMinutes} min</span>` : "";
        const creator = recipe.creatorDisplayName
            ? `<span class="creator-name">${escapeHtml(recipe.creatorDisplayName)}</span>`
            : "";
        const metadata = creator || tag || time
            ? `<span class="recipe-meta">${creator}${tag}${time}</span>`
            : "";
        const loading = index === 0 ? `fetchpriority="high"` : `loading="lazy" decoding="async"`;
        return `<li class="discovery-card" data-categories="${escapeHtml(JSON.stringify(categoryNames))}"><a href="/recipe/${encodeURIComponent(recipe.recipeId)}"><span class="recipe-media"><img src="${escapeHtml(imageURL)}" alt="${escapeHtml(recipe.title)}" ${loading} referrerpolicy="no-referrer" onerror="this.closest('.discovery-card').hidden=true;this.closest('.discovery-card').dataset.imageError='true';if(window.cauldronRecipeImageFailed)window.cauldronRecipeImageFailed(this)"></span><span class="recipe-copy"><span class="recipe-title">${escapeHtml(recipe.title)}</span>${metadata}</span></a></li>`;
    }).join("");

    const shelf = recipeRows
        ? `<section class="discovery" aria-labelledby="recipes-title"><div class="discovery-head"><h1 id="recipes-title">Recipes</h1>${filters ? `<nav class="filters" aria-label="Recipe categories"><button class="selected" type="button" data-filter="" aria-pressed="true">All</button>${filters}</nav>` : ""}</div><ol class="discovery-grid">${recipeRows}</ol><p class="no-results" role="status" hidden>No recipes in this category today.</p></section>`
        : `<section class="empty" aria-labelledby="recipes-title"><h1 id="recipes-title">Recipes</h1><a href="https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943">Open Cauldron</a></section>`;
    const year = new Date().getUTCFullYear();
    return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><title>Cauldron Recipes</title><meta name="description" content="Recipes shared from Cauldron."><meta name="theme-color" content="#F6F1EA" media="(prefers-color-scheme:light)"><meta name="theme-color" content="#18120D" media="(prefers-color-scheme:dark)"><link rel="canonical" href="${PUBLIC_WEB_ORIGIN}/"><link rel="icon" type="image/svg+xml" href="/favicon.svg"><link rel="alternate icon" href="/favicon.ico"><link rel="apple-touch-icon" href="/apple-touch-icon.png"><meta property="og:type" content="website"><meta property="og:site_name" content="Cauldron"><meta property="og:title" content="Cauldron Recipes"><meta property="og:description" content="Recipes shared from Cauldron."><meta property="og:url" content="${PUBLIC_WEB_ORIGIN}/"><meta property="og:image" content="${PUBLIC_WEB_ORIGIN}/social-card.png"><meta name="twitter:card" content="summary_large_image"><meta name="twitter:image" content="${PUBLIC_WEB_ORIGIN}/social-card.png"><meta name="apple-itunes-app" content="app-id=6754004943, app-argument=${PUBLIC_WEB_ORIGIN}/"><script type="application/ld+json">${JSON.stringify({ "@context": "https://schema.org", "@type": "SoftwareApplication", name: "Cauldron", applicationCategory: "LifestyleApplication", operatingSystem: "iOS, iPadOS, macOS", url: `${PUBLIC_WEB_ORIGIN}/`, downloadUrl: "https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943" }).replace(/</g, "\\u003c")}</script><style>
    :root{color-scheme:light dark;--paper:#f6f1ea;--ink:#251b15;--muted:#766b63;--accent:#e6801a;--surface:#fff;--separator:#e4dbd0;--control:rgba(255,255,255,.7)}
    *{box-sizing:border-box}
    html{background:var(--paper)}
    body{min-height:100svh;margin:0;background:radial-gradient(circle at 12% 0,color-mix(in srgb,var(--accent) 7%,transparent),transparent 28rem),var(--paper);color:var(--ink);font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility}
    a{color:inherit}.page{width:calc(100% - 48px);max-width:1220px;min-height:calc(100svh - 82px);margin:auto;display:grid;grid-template-rows:1fr auto}
    .filters button{border:1px solid color-mix(in srgb,var(--separator) 82%,transparent);background:var(--control);box-shadow:0 1px 0 rgba(255,255,255,.24) inset,0 5px 18px rgba(37,25,17,.05);-webkit-backdrop-filter:blur(20px) saturate(180%);backdrop-filter:blur(20px) saturate(180%)}
    main{min-width:0;padding:42px 0 92px}.discovery{min-width:0}.discovery-head{display:flex;align-items:end;justify-content:space-between;gap:28px;margin-bottom:30px}
    h1{margin:0;font-family:"New York",ui-serif,"Iowan Old Style",Georgia,serif;font-size:clamp(42px,5.2vw,62px);font-weight:500;letter-spacing:-.042em;line-height:.96}
    .filters{display:flex;gap:7px;max-width:min(70%,760px);padding:4px;overflow:auto;scrollbar-width:none}.filters::-webkit-scrollbar{display:none}
    .filters button{min-height:36px;display:inline-flex;align-items:center;gap:5px;padding:7px 11px;border-radius:999px;color:var(--muted);font:inherit;font-size:12px;white-space:nowrap;cursor:pointer}.filters button.selected{border-color:transparent;background:var(--ink);color:var(--paper)}
    .discovery-grid{display:grid;grid-template-columns:repeat(12,minmax(0,1fr));grid-auto-flow:row dense;gap:38px 18px;margin:0;padding:0;list-style:none}
    .discovery-card{min-width:0;grid-column:span 3}.discovery-card>a{display:block;text-decoration:none}.recipe-media{position:relative;aspect-ratio:4/3;display:block;overflow:hidden;border-radius:16px;background:color-mix(in srgb,var(--surface) 74%,var(--separator))}.recipe-media img{position:absolute;inset:0;width:100%;height:100%;display:block;object-fit:cover;transition:transform .35s cubic-bezier(.2,.8,.2,1)}
    .recipe-copy{display:block}.recipe-title{display:-webkit-box;min-height:2.4em;margin-top:11px;overflow:hidden;font-family:"New York",ui-serif,"Iowan Old Style",Georgia,serif;font-size:19px;font-weight:500;letter-spacing:-.014em;line-height:1.2;-webkit-box-orient:vertical;-webkit-line-clamp:2}
    .recipe-meta{display:flex;min-height:20px;align-items:center;gap:8px;margin-top:6px;overflow:hidden;color:var(--muted);font-size:11px;white-space:nowrap}.creator-name{overflow:hidden;text-overflow:ellipsis}.creator-name:not(:last-child)::after{content:"·";margin-left:8px}.recipe-tag{display:inline-flex;align-items:center;gap:4px;color:color-mix(in srgb,var(--tag-color) 64%,var(--ink))}
    .discovery-card:first-child{grid-column:1/span 7;grid-row:1/span 2}.discovery-card:first-child>a{height:100%;display:flex;flex-direction:column}.discovery-card:first-child .recipe-media{min-height:420px;flex:1;aspect-ratio:auto;border-radius:20px}.discovery-card:first-child .recipe-title{min-height:auto;font-size:clamp(28px,3.1vw,42px);line-height:1.04;letter-spacing:-.032em}.discovery-card:first-child .recipe-meta{font-size:12px}
    .discovery-card:nth-child(2),.discovery-card:nth-child(3){grid-column:8/span 5}.discovery-card:nth-child(2)>a,.discovery-card:nth-child(3)>a{min-height:191px;display:grid;grid-template-columns:minmax(0,46%) minmax(0,1fr);align-items:center;gap:20px}.discovery-card:nth-child(2) .recipe-media,.discovery-card:nth-child(3) .recipe-media{height:100%;aspect-ratio:auto}.discovery-card:nth-child(2) .recipe-title,.discovery-card:nth-child(3) .recipe-title{margin-top:0;font-size:clamp(20px,2vw,28px);line-height:1.08;letter-spacing:-.024em}
    .discovery-grid.uniform .discovery-card{grid-column:span 3;grid-row:auto}.discovery-grid.uniform .discovery-card>a{height:auto;min-height:0;display:block}.discovery-grid.uniform .recipe-media{min-height:0;height:auto;aspect-ratio:4/3;border-radius:16px}.discovery-grid.uniform .recipe-title{min-height:2.4em;margin-top:11px;font-size:19px;line-height:1.2;letter-spacing:-.014em}.discovery-grid.uniform .recipe-meta{font-size:11px}
    .discovery-card[hidden]{display:none}.discovery-card>a:hover .recipe-media img{transform:scale(1.018)}.discovery-card>a:hover .recipe-title{color:var(--accent)}
    .no-results{margin:44px 0 0;color:var(--muted);font-size:14px}.empty a{display:inline-flex;margin-top:24px;padding:10px 14px;border-radius:999px;background:var(--accent);color:#2b1600;font-size:13px;font-weight:500;text-decoration:none}
    footer{display:flex;align-items:center;justify-content:space-between;gap:20px;padding:24px 0 30px;border-top:1px solid var(--separator);color:var(--muted);font-size:12px}footer nav{display:flex;gap:18px}footer a{text-decoration:none}footer a:hover{color:var(--ink)}
    a:focus-visible,button:focus-visible{outline:3px solid color-mix(in srgb,var(--accent) 55%,transparent);outline-offset:4px}
    @media(max-width:980px){.discovery-head{align-items:flex-start;flex-direction:column}.filters{max-width:100%;width:100%;margin-left:-4px}.discovery-grid{grid-template-columns:repeat(6,minmax(0,1fr))}.discovery-card:first-child{grid-column:span 6;grid-row:auto}.discovery-card:first-child .recipe-media{min-height:0;aspect-ratio:16/10}.discovery-card:nth-child(2),.discovery-card:nth-child(3){grid-column:span 3}.discovery-card:nth-child(2)>a,.discovery-card:nth-child(3)>a{min-height:0;display:block}.discovery-card:nth-child(2) .recipe-media,.discovery-card:nth-child(3) .recipe-media{height:auto;aspect-ratio:4/3}.discovery-card:nth-child(2) .recipe-title,.discovery-card:nth-child(3) .recipe-title{min-height:2.2em;margin-top:11px}.discovery-card{grid-column:span 2}.discovery-grid.uniform .discovery-card{grid-column:span 2}}
    @media(max-width:700px){.page{width:calc(100% - 32px);max-width:620px;min-height:calc(100svh - 70px)}main{padding:30px 0 72px}.discovery-head{gap:20px;margin-bottom:22px}.discovery-grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:30px 12px}.discovery-card,.discovery-card:nth-child(2),.discovery-card:nth-child(3),.discovery-grid.uniform .discovery-card{grid-column:span 1}.discovery-card:first-child{grid-column:span 2}.discovery-card:first-child .recipe-media{aspect-ratio:4/3;border-radius:16px}.discovery-card:first-child .recipe-title{font-size:30px}.discovery-card:nth-child(2) .recipe-title,.discovery-card:nth-child(3) .recipe-title,.discovery-grid.uniform .recipe-title,.recipe-title{font-size:17px}.recipe-meta{min-height:0;align-items:flex-start;flex-direction:column;gap:4px;white-space:normal}.creator-name:not(:last-child)::after{display:none}footer{align-items:flex-start;flex-direction:column-reverse}}
    @media(prefers-reduced-motion:reduce){*{scroll-behavior:auto!important;transition:none!important}}
    @media(prefers-color-scheme:dark){:root{--paper:#18120d;--ink:#f8f0e8;--muted:#b5aaa2;--accent:#f09837;--surface:#262220;--separator:#39332f;--control:rgba(49,44,40,.7)}body{background:radial-gradient(circle at 12% 0,rgba(240,152,55,.065),transparent 28rem),var(--paper)}.recipe-tag{color:color-mix(in srgb,var(--tag-color-dark) 72%,var(--ink))}}
    </style>${publicHeaderStyles()}</head><body>${compactBrandHeader()}<div class="page"><main>${shelf}</main><footer><span>© ${year} Nadav Avital</span><nav aria-label="Footer"><a href="https://www.nadavavital.com/apps/support/?app=Cauldron">Support</a><a href="https://www.nadavavital.com/cauldron/privacy-policy/">Privacy</a></nav></footer></div><script>(function(){var grid=document.querySelector(".discovery-grid");var buttons=Array.from(document.querySelectorAll("[data-filter]"));var cards=Array.from(document.querySelectorAll(".discovery-card"));var empty=document.querySelector(".no-results");function update(filter){var count=0;cards.forEach(function(card){var failed=card.dataset.imageError==="true";var matches=!filter||JSON.parse(card.getAttribute("data-categories")||"[]").includes(filter);card.hidden=failed||!matches;if(!card.hidden)count+=1;});if(grid)grid.classList.toggle("uniform",Boolean(filter)||Boolean(cards[0]&&cards[0].hidden));if(empty)empty.hidden=count!==0;}window.cauldronRecipeImageFailed=function(image){var card=image.closest(".discovery-card");if(card)card.dataset.imageError="true";var selected=document.querySelector("[data-filter].selected");update(selected?selected.getAttribute("data-filter")||"":"");};buttons.forEach(function(button){button.addEventListener("click",function(){var filter=button.getAttribute("data-filter")||"";buttons.forEach(function(item){var selected=item===button;item.classList.toggle("selected",selected);item.setAttribute("aria-pressed",String(selected));});update(filter);});});update("");})();</script></body></html>`;
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
        ? `${PUBLIC_WEB_ORIGIN}/invite/${inviteCode}`
        : `${PUBLIC_WEB_ORIGIN}/invite`;
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
    <meta property="og:image" content="${PUBLIC_WEB_ORIGIN}/social-card.png">
    <meta property="og:url" content="${universalURL}">
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="${title}">
    <meta name="twitter:description" content="${description}">
    <meta name="twitter:image" content="${PUBLIC_WEB_ORIGIN}/social-card.png">
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
        body { display:block; padding:0; }
        .card { margin:48px auto 80px; width:min(480px,calc(100% - 32px)); padding:0; }
    </style>
    ${faviconHeadLinks()}
    ${publicHeaderStyles()}
</head>
<body>
    ${compactBrandHeader()}
    <main class="card">
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

async function fetchCloudKitProfileBackfillPage(
    continuationMarker: string | null
): Promise<{ ownerIds: string[]; continuationMarker: string | null }> {
    const keyID = cloudKitServerKeyID.value();
    const privateKey = cloudKitServerPrivateKey.value().replace(/\\n/g, "\n");
    const subpath = `/database/1/${CLOUDKIT_CONTAINER}/production/public/records/query`;
    const body = JSON.stringify(continuationMarker
        ? { continuationMarker }
        : { query: { recordType: "User" }, resultsLimit: 25 });
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
        const message = `CloudKit profile backfill returned ${response.status}`;
        throw isTransientCloudKitHTTPStatus(response.status)
            ? new RetryableCloudKitError(message)
            : new Error(message);
    }
    const payload = await response.json() as CloudKitRecordsPayload & {
        records?: CloudKitRecordLike[];
        continuationMarker?: unknown;
    };
    if (cloudKitQueryPayloadHasErrors(payload)) {
        const message = "CloudKit profile backfill returned a record error";
        throw cloudKitRecordsPayloadIsRetryableError(payload)
            ? new RetryableCloudKitError(message)
            : new Error(message);
    }
    const ownerIds = [...new Set((payload.records ?? []).flatMap((record) => {
        const ownerId = record.fields?.userId?.value;
        return record.recordType === "User" && isValidUUID(ownerId)
            ? [ownerId]
            : [];
    }))];
    return {
        ownerIds,
        continuationMarker: typeof payload.continuationMarker === "string"
            ? payload.continuationMarker
            : null,
    };
}

export function profileBackfillFailureState(
    retryCounts: Record<string, number>,
    failedOwnerIds: string[],
    ownerId: string,
    maxAttempts = 3
): {
    attempt: number;
    shouldRetry: boolean;
    retryCounts: Record<string, number>;
    failedOwnerIds: string[];
} {
    const attempt = (retryCounts[ownerId] ?? 0) + 1;
    if (attempt >= maxAttempts) {
        const nextRetryCounts = { ...retryCounts };
        delete nextRetryCounts[ownerId];
        return {
            attempt,
            shouldRetry: false,
            retryCounts: nextRetryCounts,
            failedOwnerIds: [
                ...failedOwnerIds.filter((failedOwnerId) => failedOwnerId !== ownerId),
                ownerId,
            ].slice(-100),
        };
    }
    return {
        attempt,
        shouldRetry: true,
        retryCounts: { ...retryCounts, [ownerId]: attempt },
        failedOwnerIds,
    };
}

export const backfillPublicProfiles = onSchedule({
    schedule: "every 2 hours",
    timeZone: "Etc/UTC",
    secrets: [cloudKitServerKeyID, cloudKitServerPrivateKey],
    timeoutSeconds: 300,
    maxInstances: 1,
}, async () => {
    const stateRef = db.collection("share_maintenance").doc("public_profile_backfill");
    const state = await stateRef.get();
    const stateData = state.data();
    const previousMarker = typeof stateData?.continuationMarker === "string"
        ? stateData.continuationMarker as string
        : null;
    let pendingOwnerIds = Array.isArray(stateData?.pendingOwnerIds)
        ? stateData.pendingOwnerIds.filter((value: unknown): value is string => isValidUUID(value))
        : [];
    let nextContinuationMarker = typeof stateData?.nextContinuationMarker === "string"
        ? stateData.nextContinuationMarker as string
        : null;
    let retryCounts = stateData?.retryCounts && typeof stateData.retryCounts === "object"
        ? Object.fromEntries(Object.entries(stateData.retryCounts as Record<string, unknown>)
            .filter(([ownerId, count]) => isValidUUID(ownerId) &&
                typeof count === "number" && Number.isInteger(count) && count > 0)) as Record<string, number>
        : {};
    let failedOwnerIds = Array.isArray(stateData?.failedOwnerIds)
        ? stateData.failedOwnerIds.filter((value: unknown): value is string => isValidUUID(value))
        : [];
    if (pendingOwnerIds.length === 0) {
        const page = await retryTransientCloudKitOperation(() =>
            fetchCloudKitProfileBackfillPage(previousMarker)
        );
        pendingOwnerIds = page.ownerIds;
        nextContinuationMarker = page.continuationMarker;
    }
    let materialized = 0;
    let unprocessedOwnerIds = pendingOwnerIds;
    const retryOwnerIds: string[] = [];
    const ownerIdsThisRun = pendingOwnerIds.slice(0, 12);
    for (let index = 0; index < ownerIdsThisRun.length; index += 4) {
        const chunk = ownerIdsThisRun.slice(index, index + 4);
        unprocessedOwnerIds = unprocessedOwnerIds.slice(chunk.length);
        const results = await Promise.all(chunk.map(async (ownerId) => {
            try {
                const profile = await retryTransientCloudKitOperation(() =>
                    queryCanonicalCloudKitProfileByOwner(ownerId)
                );
                if (!profile || await isShareRevoked(ownerId) ||
                    await isResourcePrivacyBlocked("profile", ownerId)) {
                    return { ownerId, retry: false, materialized: false };
                }
                await materializeCanonicalProfile(profile);
                await materializeCanonicalRecipeSummaries(ownerId, profile.creatorRecordName);
                delete retryCounts[ownerId];
                failedOwnerIds = failedOwnerIds.filter((failedOwnerId) => failedOwnerId !== ownerId);
                return { ownerId, retry: false, materialized: true };
            } catch (error) {
                const failureState = profileBackfillFailureState(
                    retryCounts,
                    failedOwnerIds,
                    ownerId
                );
                retryCounts = failureState.retryCounts;
                failedOwnerIds = failureState.failedOwnerIds;
                if (!failureState.shouldRetry) {
                    logger.error("Automatic public profile backfill skipped a persistently failing profile", {
                        ownerId,
                        attempt: failureState.attempt,
                        error,
                    });
                    return { ownerId, retry: false, materialized: false };
                }
                logger.warn("Automatic public profile backfill will retry a failed profile", {
                    ownerId,
                    attempt: failureState.attempt,
                    error,
                });
                return { ownerId, retry: true, materialized: false };
            }
        }));
        materialized += results.filter((result) => result.materialized).length;
        retryOwnerIds.push(...results.filter((result) => result.retry).map((result) => result.ownerId));
        pendingOwnerIds = [...unprocessedOwnerIds, ...retryOwnerIds];
        const pageComplete = pendingOwnerIds.length === 0;
        await stateRef.set({
            continuationMarker: pageComplete ? nextContinuationMarker : previousMarker,
            nextContinuationMarker: pageComplete ? FieldValue.delete() : nextContinuationMarker,
            pendingOwnerIds: pageComplete ? FieldValue.delete() : pendingOwnerIds,
            retryCounts,
            failedOwnerIds,
            lastRunAt: FieldValue.serverTimestamp(),
            lastMaterializedCount: materialized,
        }, { merge: true });
    }
    if (ownerIdsThisRun.length === 0) {
        await stateRef.set({
            continuationMarker: nextContinuationMarker,
            nextContinuationMarker: FieldValue.delete(),
            pendingOwnerIds: FieldValue.delete(),
            retryCounts,
            failedOwnerIds,
            lastRunAt: FieldValue.serverTimestamp(),
            lastMaterializedCount: 0,
        }, { merge: true });
    }
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

        const canonicalURL = `${PUBLIC_WEB_ORIGIN}/recipe/${encodeURIComponent(recipeId)}`;
        // Keep the custom scheme until the custom-domain entitlement has shipped
        // broadly; older installed builds cannot claim the new canonical host.
        const appURL = `cauldron://import/recipe/${encodeURIComponent(recipeId)}`;
        const downloadURL = 'https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943';
        const [fullRecipe, creator] = await Promise.all([
            fetchPublicCloudKitRecipe(recipeId, sanitized.value.ownerId),
            fetchPublicCloudKitRecipeCreator(sanitized.value.ownerId),
        ]);
        if (!fullRecipe) {
            await deleteSnapshotIfUnchanged("shared_recipes", doc, sanitized.value.ownerId);
        }

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
        const visibility = await Promise.all(sanitized.map(async (recipe) => ({
            recipe,
            isBlocked: await isResourcePrivacyBlocked("recipe", recipe.recipeId),
        })));
        return visibility
            .filter(({ isBlocked }) => !isBlocked)
            .map(({ recipe }) => recipe);
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

type ObservedRecipeSnapshot = {
    recipeId: string;
    ownerId: string;
    updateTimeMillis: number;
};

async function cleanupPermanentlyInvalidRecipeSnapshots(
    snapshots: ObservedRecipeSnapshot[],
    invalidRecipeIds: string[]
): Promise<void> {
    const invalid = new Set(invalidRecipeIds);
    const candidates = snapshots.filter((snapshot) => invalid.has(snapshot.recipeId));
    await Promise.all(candidates.map(async (candidate) => {
        const ref = db.collection("shared_recipes").doc(candidate.recipeId);
        await db.runTransaction(async (transaction) => {
            const current = await transaction.get(ref);
            if (!current.exists ||
                current.data()?.ownerId !== candidate.ownerId ||
                current.updateTime?.toMillis() !== candidate.updateTimeMillis) {
                return;
            }
            transaction.delete(ref);
        });
    }));
}

/** The exact read-only discovery pipeline used by production and local QA. */
export async function loadHomepageRecipeShelf(now = new Date()): Promise<{
    validation: RecipeShelfValidation;
    observed: ObservedRecipeSnapshot[];
}> {
    const rotationKey = now.toISOString().slice(0, 10);
    const pools = await loadHomepageRecipeDocuments(db.collection("shared_recipes"), rotationKey);
    const recentIDs = new Set(pools.recent.map((document) => document.id));
    const documents = [...new Map([...pools.archive, ...pools.recent].map((doc) => [doc.id, doc])).values()];
    const summaries = await browsableRecipes(documents);
    const candidates = selectHomepageRecipeMix(
        summaries.filter((recipe) => recentIDs.has(recipe.recipeId)),
        summaries.filter((recipe) => !recentIDs.has(recipe.recipeId)), rotationKey, 24
    );
    const validation = await bestEffortRecipeIndexItems(candidates, 6_000);
    // Repeat selection after authoritative validation: stale images/tags must not
    // determine the final balance, and missing images must not consume slots.
    const pictured = validation.items.filter((recipe) => safeCloudKitAssetURL(recipe.imageURL));
    validation.items = selectHomepageRecipeMix(
        pictured.filter((recipe) => recentIDs.has(recipe.recipeId)),
        pictured.filter((recipe) => !recentIDs.has(recipe.recipeId)), rotationKey
    );
    logger.info("Homepage discovery health", { candidates: candidates.length,
        displayed: validation.items.length, creators: new Set(validation.items.map((item) => item.ownerId)).size,
        archiveDisplayed: validation.items.filter((item) => !recentIDs.has(item.recipeId)).length });
    if (validation.items.length === 0) logger.warn("Homepage discovery has no validated recipe images");
    const observed = documents.flatMap((document): ObservedRecipeSnapshot[] => {
        const ownerId = document.data()?.ownerId;
        const updateTimeMillis = document.updateTime?.toMillis();
        return typeof ownerId === "string" && typeof updateTimeMillis === "number"
            ? [{ recipeId: document.id, ownerId, updateTimeMillis }]
            : [];
    });
    return { validation, observed };
}

export const previewHome = onRequest(cloudBackedPublicReadHTTPOptions, async (req, res) => {
    res.set(publicSecurityHeaders());
    if (!await enforcePublicReadRateLimit(req)) {
        rejectRateLimitedRead(res);
        return;
    }
    try {
        const { validation, observed } = await loadHomepageRecipeShelf();
        await cleanupPermanentlyInvalidRecipeSnapshots(
            observed,
            validation.permanentlyInvalidRecipeIds
        );
        res.set("Cache-Control", HOMEPAGE_CACHE_CONTROL);
        res.status(200).send(generateHomePageHtml(validation.items));
    } catch (error) {
        logger.warn("Homepage recipe shelf is unavailable; serving the product page", { error });
        res.set("Cache-Control", HOMEPAGE_CACHE_CONTROL);
        res.status(200).send(generateHomePageHtml([]));
    }
});

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
            const canonicalProfile = await fetchCanonicalCloudKitProfile(shareId);
            if (!canonicalProfile ||
                await isShareRevoked(canonicalProfile.userId) ||
                await isResourcePrivacyBlocked("profile", canonicalProfile.userId)) {
                res.status(404).send(generatePublicStatusPageHtml("Profile unavailable", "This profile is no longer shared on the web."));
                return;
            }
            await materializeCanonicalProfile(canonicalProfile);
            doc = await db.collection('shared_profiles').doc(canonicalProfile.userId).get();
            if (!doc.exists) {
                res.status(404).send(generatePublicStatusPageHtml("Profile unavailable", "This profile is no longer shared on the web."));
                return;
            }
        }

        const requestedProfileDocument = doc;
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
        const canonicalProfile = await fetchCanonicalCloudKitProfile(data.userId);
        if (!canonicalProfile) {
            await deleteSnapshotIfUnchanged(
                "shared_profiles",
                requestedProfileDocument,
                data.userId
            );
            res.status(404).send(generatePublicStatusPageHtml("Profile unavailable", "This profile is no longer shared on the web."));
            return;
        }
        const requestedAliasOwnerId = uuidPattern.test(shareId) ||
            shareId.toLocaleLowerCase() === canonicalProfile.username.toLocaleLowerCase()
            ? data.userId
            : await ownerIDForCloudKitUsername(shareId);
        if (requestedAliasOwnerId !== data.userId) {
            await deleteSnapshotIfUnchanged(
                "shared_profiles",
                requestedProfileDocument,
                data.userId
            );
            res.status(404).send(generatePublicStatusPageHtml("Profile unavailable", "This profile is no longer shared on the web."));
            return;
        }
        await materializeCanonicalProfile(canonicalProfile);
        const canonicalURL = canonicalProfileURL(canonicalProfile.username);
        const redirectURL = canonicalProfileRedirectURL(shareId, canonicalProfile.username);
        if (redirectURL) {
            res.redirect(308, redirectURL);
            return;
        }
        const browsable: SanitizedRecipeShare[] = [];
        const observedSnapshots: ObservedRecipeSnapshot[] = [];
        let profileCursor: QueryDocumentSnapshot | null = null;
        let profileSourceExhausted = false;
        for (let page = 0; page < 4; page += 1) {
            let recipeQuery: Query = db.collection('shared_recipes')
                .where('ownerId', '==', data.userId)
                .limit(25);
            if (profileCursor) {
                recipeQuery = recipeQuery.startAfter(profileCursor);
            }
            const recipeSnapshot = await recipeQuery.get();
            observedSnapshots.push(...recipeSnapshot.docs.flatMap((recipeDocument) => {
                const ownerId = recipeDocument.data()?.ownerId;
                const updateTimeMillis = recipeDocument.updateTime?.toMillis();
                return typeof ownerId === "string" && typeof updateTimeMillis === "number"
                    ? [{ recipeId: recipeDocument.id, ownerId, updateTimeMillis }]
                    : [];
            }));
            browsable.push(...await browsableRecipes(recipeSnapshot.docs, data.userId));
            if (recipeSnapshot.size < 25) {
                profileSourceExhausted = true;
                break;
            }
            profileCursor = recipeSnapshot.docs[recipeSnapshot.docs.length - 1];
        }
        browsable.sort((lhs, rhs) => lhs.title.localeCompare(rhs.title));
        const validation = await bestEffortRecipeIndexItems(browsable);
        const recipes = validation.items.slice(0, MAX_WEB_RECIPE_CARDS);
        const hasMoreRecipes = validation.items.length > MAX_WEB_RECIPE_CARDS || !profileSourceExhausted;
        await cleanupPermanentlyInvalidRecipeSnapshots(
            observedSnapshots,
            validation.permanentlyInvalidRecipeIds
        );
        const description = "A recipe shelf shared from Cauldron.";
        const appURL = `cauldron://import/profile/${shareId}`;
        const downloadURL = 'https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943';

        res.set("Cache-Control", "private, no-store, max-age=0");
        res.send(generateCompactRecipeIndexPageHtml({
            handle: `@${canonicalProfile.username}`,
            title: canonicalProfile.displayName,
            description,
            canonicalURL,
            appURL,
            downloadURL,
            recipes,
            totalRecipeCount: validation.items.length,
            hasMoreRecipes,
            openGraphType: "profile",
            avatarEmoji: canonicalProfile.profileImageURL ? null : canonicalProfile.profileEmoji,
            avatarColor: canonicalProfile.profileColor,
            avatarImageURL: canonicalProfile.profileImageURL,
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
        const storedData = sanitized.value;
        const canonicalCollection = await fetchPublicCloudKitCollection(
            storedData.collectionId,
            storedData.ownerId
        );
        if (!canonicalCollection) {
            await deleteSnapshotIfUnchanged("shared_collections", doc, storedData.ownerId);
            res.status(404).send(generatePublicStatusPageHtml("Collection unavailable", "This collection is no longer shared on the web."));
            return;
        }
        const data = {
            ...storedData,
            title: canonicalCollection.title,
            recipeIds: canonicalCollection.recipeIds,
            recipeCount: canonicalCollection.recipeIds.length,
        };
        const browsable: SanitizedRecipeShare[] = [];
        const observedSnapshots: ObservedRecipeSnapshot[] = [];
        let collectionCursor = 0;
        while (collectionCursor < data.recipeIds.length && collectionCursor < 100) {
            const candidateRecipeIds = data.recipeIds.slice(collectionCursor, collectionCursor + 25);
            const recipeDocuments = await db.getAll(
                ...candidateRecipeIds.map((recipeId) => db.collection('shared_recipes').doc(recipeId))
            );
            observedSnapshots.push(...recipeDocuments.flatMap((recipeDocument) => {
                const ownerId = recipeDocument.data()?.ownerId;
                const updateTimeMillis = recipeDocument.updateTime?.toMillis();
                return typeof ownerId === "string" && typeof updateTimeMillis === "number"
                    ? [{ recipeId: recipeDocument.id, ownerId, updateTimeMillis }]
                    : [];
            }));
            browsable.push(...await browsableRecipes(recipeDocuments));
            collectionCursor += candidateRecipeIds.length;
        }
        const recipeOrder = new Map(data.recipeIds.map((recipeId, index) => [recipeId, index]));
        browsable.sort((lhs, rhs) => (recipeOrder.get(lhs.recipeId) ?? Number.MAX_SAFE_INTEGER) -
            (recipeOrder.get(rhs.recipeId) ?? Number.MAX_SAFE_INTEGER));
        const validation = await bestEffortRecipeIndexItems(browsable);
        const recipes = validation.items.slice(0, MAX_WEB_RECIPE_CARDS);
        const hasMoreRecipes = validation.items.length > MAX_WEB_RECIPE_CARDS || collectionCursor < data.recipeIds.length;
        await cleanupPermanentlyInvalidRecipeSnapshots(
            observedSnapshots,
            validation.permanentlyInvalidRecipeIds
        );
        const description = "A recipe collection shared from Cauldron.";
        const canonicalURL = `${PUBLIC_WEB_ORIGIN}/collection/${encodeURIComponent(shareId)}`;
        const appURL = `cauldron://import/collection/${shareId}`;
        const downloadURL = 'https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943';

        res.set("Cache-Control", "private, no-store, max-age=0");
        res.send(generateCompactRecipeIndexPageHtml({
            title: data.title,
            description,
            canonicalURL,
            appURL,
            downloadURL,
            recipes,
            totalRecipeCount: data.recipeIds.length,
            hasMoreRecipes,
            openGraphType: "website",
        }));
    } catch (error) {
        logger.error('Error loading collection preview:', error);
        res.status(500).send(generatePublicStatusPageHtml("Collection temporarily unavailable", "Please try opening this collection again in a moment."));
    }
});
