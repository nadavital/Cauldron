import assert from "node:assert/strict";
import test from "node:test";
import {
    escapeHtml,
    canonicalRecipeCategoryName,
    cloudKitAuthorityMatches,
    cloudKitReferralRecordIsActive,
    cloudKitReferralQueryResolvesUniquely,
    canonicalCloudKitOwnerRecord,
    canonicalCloudKitRecipeCreator,
    canonicalOwnerRecipesFromCloudKitRecords,
    hideRelatedWebRecipeReferences,
    publicWebRecipeData,
    canonicalProfileImageRecordName,
    canonicalProfileURL,
    canonicalProfileRedirectURL,
    profileShareRequestMatchesCanonicalUsername,
    profileBackfillFailureState,
    cloudKitOwnerQuery,
    cloudKitRecipeShelfLookupBody,
    cloudKitRecordsPayloadDisposition,
    cloudKitQueryPayloadHasErrors,
    cloudKitRecordsPayloadIsRetryableError,
    cloudKitSignatureInput,
    generateCompactRecipeIndexPageHtml,
    generateHomePageHtml,
    HOMEPAGE_CACHE_CONTROL,
    rotatingHomepageRecipeCandidates,
    generateCompactRecipePageHtml,
    generateInvitePreviewHtml,
    generatePublicStatusPageHtml,
    generateRecipePageHtml,
    generatePreviewHtml,
    isValidUUID,
    isCurrentResourceMutationGeneration,
    ownerManifestStateMatches,
    isTransientCloudKitHTTPStatus,
    publicSecurityHeaders,
    PUBLIC_WEB_ORIGIN,
    previewCollection,
    previewProfile,
    publishedShareResponse,
    recipeCategoryPresentation,
    detectedImageContentType,
    recipeSocialImageURL,
    recipeIndexItemsWithCloudKitImages,
    permanentlyInvalidRecipeShelfIDs,
    resolveCloudKitCollectionMembershipRecipeIDs,
    retryTransientCloudKitOperation,
    renderCanonicalRecipePage,
    resourceMutationCannotSupersede,
    safeImageURL,
    sanitizeAccountUnshareInput,
    sanitizeCollectionShareInput,
    sanitizeCollectionUnshareInput,
    sanitizeCloudKitRecipeForWeb,
    sanitizeCloudKitCollectionForWeb,
    sanitizeProfileShareInput,
    sanitizeProfileUnshareInput,
    sanitizeOwnerManifestInput,
    sanitizeRecipeShareInput,
    sanitizeStoredRecipeShareInput,
    sanitizeStoredProfileShareInput,
    sanitizeStoredCollectionShareInput,
    retiredCapabilityCannotSupersedeRestoration,
    revocationCreatorMatches,
    restorationRevocationIsValid,
    sanitizeRecipeUnshareInput,
} from "../lib/index.js";

test("web avatar resolution matches the native emoji-first recovery rule", () => {
    assert.equal(canonicalProfileImageRecordName("🍳", "stale-profile-photo"), null);
    assert.equal(canonicalProfileImageRecordName("  ", "current-profile-photo"), "current-profile-photo");
    assert.equal(canonicalProfileImageRecordName(null, null), null);
});

test("profile aliases must still match the owner's canonical username", () => {
    const ownerId = "9f082214-0c9e-4e30-94d7-072fc359d2f4";
    assert.equal(profileShareRequestMatchesCanonicalUsername(ownerId, "nadav"), true);
    assert.equal(profileShareRequestMatchesCanonicalUsername("NADAV", "nadav"), true);
    assert.equal(profileShareRequestMatchesCanonicalUsername("old-name", "nadav"), false);
});

test("public profile URLs expose the normalized username rather than the owner UUID", () => {
    assert.equal(canonicalProfileURL("NADAV"), "https://cauldronrecipes.com/u/nadav");
    assert.equal(canonicalProfileRedirectURL("nadav", "nadav"), null);
    assert.equal(
        canonicalProfileRedirectURL("9f082214-0c9e-4e30-94d7-072fc359d2f4", "nadav"),
        "https://cauldronrecipes.com/u/nadav"
    );
    assert.equal(canonicalProfileRedirectURL("NADAV", "nadav"), "https://cauldronrecipes.com/u/nadav");
    assert.equal(canonicalProfileRedirectURL("old_name", "nadav"), "https://cauldronrecipes.com/u/nadav");
});

test("profile backfill retries are bounded and quarantine does not retain retry state", () => {
    const ownerId = "9f082214-0c9e-4e30-94d7-072fc359d2f4";
    const first = profileBackfillFailureState({}, [], ownerId);
    assert.equal(first.shouldRetry, true);
    assert.equal(first.retryCounts[ownerId], 1);

    const second = profileBackfillFailureState(first.retryCounts, first.failedOwnerIds, ownerId);
    assert.equal(second.shouldRetry, true);
    assert.equal(second.retryCounts[ownerId], 2);

    const third = profileBackfillFailureState(second.retryCounts, second.failedOwnerIds, ownerId);
    assert.equal(third.shouldRetry, false);
    assert.equal(ownerId in third.retryCounts, false);
    assert.deepEqual(third.failedOwnerIds, [ownerId]);
});

test("CloudKit collection validation rejects stale or private pointers", () => {
    const collectionId = "018f9344-54ff-42fc-83a8-c2a92e2d1b10";
    const ownerId = "9f082214-0c9e-4e30-94d7-072fc359d2f4";
    const creator = "creator-record";
    const record = {
        recordName: collectionId,
        recordType: "Collection",
        created: { userRecordName: creator },
        fields: {
            collectionId: { value: collectionId },
            userId: { value: ownerId },
            visibility: { value: "public" },
            name: { value: "Weeknight" },
            recipeIds: { value: JSON.stringify([collectionId]) },
        },
    };
    assert.deepEqual(sanitizeCloudKitCollectionForWeb(record, collectionId, ownerId, creator), {
        collectionId,
        ownerId,
        title: "Weeknight",
        recipeIds: [collectionId],
    });
    assert.equal(sanitizeCloudKitCollectionForWeb({
        ...record,
        fields: { ...record.fields, visibility: { value: "private" } },
    }, collectionId, ownerId, creator), null);
    assert.equal(sanitizeCloudKitCollectionForWeb(record, collectionId, ownerId, "attacker"), null);
});

test("collection membership edges override the legacy recipe list safely", () => {
    const collectionId = "018f9344-54ff-42fc-83a8-c2a92e2d1b10";
    const ownerId = "9f082214-0c9e-4e30-94d7-072fc359d2f4";
    const firstRecipeId = "601e40f5-3abe-42cb-9d9d-f37530cd3963";
    const secondRecipeId = "dbf6f739-1e1b-472c-b571-5607f300740d";
    const edge = (recipeId, status, updatedAt, sortOrder, creator = "creator") => ({
        recordType: "CollectionMembership",
        created: { userRecordName: creator },
        fields: {
            collectionId: { value: collectionId },
            ownerId: { value: ownerId },
            recipeId: { value: recipeId },
            status: { value: status },
            updatedAt: { value: updatedAt },
            sortOrder: { value: sortOrder },
        },
    });
    assert.deepEqual(resolveCloudKitCollectionMembershipRecipeIDs([
        edge(firstRecipeId, "active", "2026-01-01T00:00:00Z", 0),
        edge(firstRecipeId, "removed", "2026-01-02T00:00:00Z", 0),
        edge(secondRecipeId, "active", "2026-01-03T00:00:00Z", 2),
        edge(firstRecipeId, "active", "2026-01-04T00:00:00Z", 1, "attacker"),
    ], collectionId, ownerId, "creator"), [secondRecipeId]);
    assert.equal(resolveCloudKitCollectionMembershipRecipeIDs([], collectionId, ownerId, "creator"), null);
    assert.equal(resolveCloudKitCollectionMembershipRecipeIDs([
        edge(firstRecipeId, "active", "2026-01-01T00:00:00Z", 0, "attacker"),
    ], collectionId, ownerId, "creator"), null);
    assert.equal(resolveCloudKitCollectionMembershipRecipeIDs([
        edge(firstRecipeId, "active", "2026-01-01T00:00:00Z", 0),
        edge(firstRecipeId, "removed", "2026-01-01T00:00:00Z", 0),
    ], collectionId, ownerId, "creator")?.length, 0);
    assert.equal(resolveCloudKitCollectionMembershipRecipeIDs([
        edge(firstRecipeId, "removed", "2026-01-01T00:00:00Z", 0),
        edge(firstRecipeId, "active", "2026-01-01T00:00:00Z", 0),
    ], collectionId, ownerId, "creator")?.length, 0);
    assert.equal(resolveCloudKitCollectionMembershipRecipeIDs([
        edge(firstRecipeId, "active", "2026-01-01T00:00:00Z", 0),
    ], collectionId, ownerId, null), null);
});

test("automatic recipe materialization accepts only the canonical user's records", () => {
    const ownerId = "9f082214-0c9e-4e30-94d7-072fc359d2f4";
    const recipeId = "601e40f5-3abe-42cb-9d9d-f37530cd3963";
    const record = (creator) => ({
        recordName: recipeId,
        recordType: "SharedRecipe",
        created: { userRecordName: creator },
        fields: {
            recipeId: { value: recipeId },
            ownerId: { value: ownerId },
            visibility: { value: "public" },
            title: { value: "Soup" },
        },
    });
    assert.equal(canonicalOwnerRecipesFromCloudKitRecords([
        record("attacker"),
    ], ownerId, "creator").length, 0);
    assert.equal(canonicalOwnerRecipesFromCloudKitRecords([
        record("creator"),
    ], ownerId, "creator").length, 1);
});

test("share publication responses expose the write outcome on every endpoint", () => {
    assert.equal(PUBLIC_WEB_ORIGIN, "https://cauldronrecipes.com");
    assert.deepEqual(
        publishedShareResponse("profile-id", "https://cauldronrecipes.com/profile/profile-id", true),
        {
            shareId: "profile-id",
            shareUrl: "https://cauldronrecipes.com/profile/profile-id",
            published: true,
        }
    );
    assert.equal(publishedShareResponse("profile-id", "url", false).published, false);
});

test("web recipe category colors match the app's adaptive and custom palette", () => {
    assert.deepEqual(recipeCategoryPresentation.Mexican, {
        emoji: "🌮", light: "#E6801A", dark: "#E6801A",
    });
    assert.deepEqual(recipeCategoryPresentation.Japanese, {
        emoji: "🍣", light: "#FF6666", dark: "#FF6666",
    });
    assert.deepEqual(recipeCategoryPresentation.Vegan, {
        emoji: "🌱", light: "#66CC66", dark: "#66CC66",
    });
    assert.deepEqual(recipeCategoryPresentation.Snack, {
        emoji: "🍿", light: "#FFCC00", dark: "#FFD60A",
    });
    assert.deepEqual(recipeCategoryPresentation["Side Dish"], {
        emoji: "🥗", light: "#34C759", dark: "#30D158",
    });
});

test("recipe previews use a stable same-origin social image URL", () => {
    const canonicalURL = "https://cauldronrecipes.com/recipe/018f9344-54ff-42fc-83a8-c2a92e2d1b10";
    assert.equal(
        recipeSocialImageURL(canonicalURL),
        `${canonicalURL}/social-card.png`
    );

    const html = generateRecipePageHtml({
        recipeId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        ownerId: "9f082214-0c9e-4e30-94d7-072fc359d2f4",
        title: "Tomato Soup",
        yields: "4 servings",
        totalMinutes: 30,
        tags: ["Dinner"],
        ingredients: [],
        steps: [],
        imageURL: "https://cvws.icloud-content.com/signed-photo?token=temporary",
    }, canonicalURL, "cauldron://import/recipe/test", "https://apps.apple.com/app/id6754004943", {
        username: "chef_nadav",
        displayName: "Chef Nadav",
        profileEmoji: "🍲",
        profileColor: "#FF9933",
    });

    assert.match(html, new RegExp(`property="og:image" content="${canonicalURL}/social-card\\.png"`));
    assert.match(html, /property="og:image:alt" content="Tomato Soup on Cauldron"/);
    assert.doesNotMatch(html, /property="og:image" content="https:\/\/cvws\.icloud-content\.com/);
});

test("social image proxy validates file signatures when CloudKit omits a MIME type", () => {
    assert.equal(detectedImageContentType(Buffer.from([0xFF, 0xD8, 0xFF, 0xE0])), "image/jpeg");
    assert.equal(detectedImageContentType(Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])), "image/png");
    assert.equal(detectedImageContentType(Buffer.from("RIFF1234WEBP", "ascii")), "image/webp");
    assert.equal(detectedImageContentType(Buffer.from("<script>", "utf8")), null);
});

test("web recipe tags use the app's trimming, case, and alias normalization", () => {
    assert.equal(canonicalRecipeCategoryName(" dessert "), "Dessert");
    assert.equal(canonicalRecipeCategoryName("mexican food"), "Mexican");
    assert.equal(canonicalRecipeCategoryName("GF"), "Gluten-Free");
    assert.equal(canonicalRecipeCategoryName("not a category"), null);
});

test("invite preview opens the app without an automatic App Store redirect", () => {
    const html = generateInvitePreviewHtml("ABC123");
    assert.match(html, /window\.location\.assign\(deepLink\)/);
    assert.doesNotMatch(html, /setTimeout\(/);
    assert.doesNotMatch(html, /window\.location\.href\s*=\s*appStoreURL/);
    assert.match(html, /Download Cauldron<\/a>/);
    assert.match(html, /--bg: #F6F1EA/);
    assert.match(html, /--bg: #18120D/);
    assert.match(html, /--orange: #FF9933/);
    assert.doesNotMatch(html, /radial-gradient|box-shadow/);
});

test("public responses use browser defense-in-depth headers", () => {
    const headers = publicSecurityHeaders();
    assert.match(headers["Content-Security-Policy"], /default-src 'none'/);
    assert.match(headers["Content-Security-Policy"], /frame-ancestors 'none'/);
    assert.equal(headers["Cross-Origin-Opener-Policy"], "same-origin");
    assert.equal(headers["Permissions-Policy"], "camera=(), microphone=(), geolocation=(), payment=(), usb=()");
    assert.equal(headers["Referrer-Policy"], "no-referrer");
    assert.equal(headers["X-Content-Type-Options"], "nosniff");
    assert.equal(headers["X-Frame-Options"], "DENY");
});

test("escapeHtml escapes preview metadata", () => {
    assert.equal(
        escapeHtml(`<script>alert("x")</script> & 'bad'`),
        "&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt; &amp; &#39;bad&#39;"
    );
});

test("safeImageURL accepts only controlled public image URLs", () => {
    assert.equal(safeImageURL("https://cauldronrecipes.com/images/recipe.jpg?token=secret#crop"), "https://cauldronrecipes.com/images/recipe.jpg");
    assert.equal(safeImageURL("https://cauldron-f900a.web.app/images/legacy.jpg?token=secret#crop"), "https://cauldron-f900a.web.app/images/legacy.jpg");
    assert.equal(safeImageURL("https://cauldron-f900a.firebaseapp.com/images/legacy.jpg?token=secret#crop"), "https://cauldron-f900a.firebaseapp.com/images/legacy.jpg");
    assert.equal(safeImageURL("https://example.com/image.jpg"), null);
    assert.equal(safeImageURL("https://127.0.0.1/image.jpg"), null);
    assert.equal(safeImageURL("https://user:password@example.com/image.jpg"), null);
    assert.equal(safeImageURL("http://example.com/image.jpg"), null);
    assert.equal(safeImageURL("javascript:alert(1)"), null);
    assert.equal(safeImageURL("not a url"), null);
});

test("share metadata validation rejects malformed identities", () => {
    assert.equal(isValidUUID("018f9344-54ff-42fc-83a8-c2a92e2d1b10"), true);
    assert.equal(isValidUUID("not-a-uuid"), false);

    assert.equal(
        sanitizeRecipeShareInput({
            recipeId: "not-a-uuid",
            ownerId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
            identityRecordName: "user_current-user-record",
            title: "Soup",
        }).ok,
        false
    );

    assert.equal(
        sanitizeProfileShareInput({
            userId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
            username: "../admin",
            identityRecordName: "user_current-user-record",
            capability: "p".repeat(43),
        }).ok,
        false
    );
});

test("share metadata validation bounds and normalizes client-controlled fields", () => {
    const recipe = sanitizeRecipeShareInput({
        recipeId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        ownerId: "9f082214-0c9e-4e30-94d7-072fc359d2f4",
        identityRecordName: "user_current-user-record",
        title: "  Tomato Soup  ",
        capability: "a".repeat(43),
        imageURL: "http://example.com/image.jpg",
        ingredientCount: 9999,
        totalMinutes: -1,
        tags: ["Dinner", " dinner ", "", "x".repeat(80)],
    });

    assert.equal(recipe.ok, true);
    assert.deepEqual(recipe.value, {
        recipeId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        ownerId: "9f082214-0c9e-4e30-94d7-072fc359d2f4",
        identityRecordName: "user_current-user-record",
        title: "Tomato Soup",
        totalMinutes: null,
        tags: ["Dinner", "x".repeat(48)],
        capability: "a".repeat(43),
        shouldCreate: false,
    });

    const profile = sanitizeProfileShareInput({
        userId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        username: "Chef_Nadav",
        identityRecordName: "user_current-user-record",
        recipeCount: 25,
        capability: "p".repeat(43),
    });
    assert.equal(profile.ok, true);
    assert.equal(profile.value.username, "chef_nadav");
    assert.equal(profile.value.displayName, "Chef_Nadav");
    assert.equal(profile.value.capability, "p".repeat(43));
    assert.equal(profile.value.shouldCreate, false);

    const metadataRefresh = sanitizeProfileShareInput({
        ...profile.value,
        capability: "p".repeat(43),
    });
    assert.equal(metadataRefresh.ok, true);
    assert.equal(metadataRefresh.value.recipeCount, 25);

    const countPreservingRefresh = sanitizeProfileShareInput({
        userId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        identityRecordName: "user_current-user-record",
        username: "chef_nadav",
        displayName: "Chef Nadav",
        capability: "p".repeat(43),
    });
    assert.equal(countPreservingRefresh.ok, true);
    assert.equal(countPreservingRefresh.value.recipeCount, null);

    const createProfile = sanitizeProfileShareInput({
        userId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        username: "Chef_Nadav",
        identityRecordName: "user_current-user-record",
        capability: "p".repeat(43),
        shouldCreate: true,
    });
    assert.equal(createProfile.ok, true);
    assert.equal(createProfile.value.shouldCreate, true);

    const collection = sanitizeCollectionShareInput({
        collectionId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        ownerId: "9f082214-0c9e-4e30-94d7-072fc359d2f4",
        identityRecordName: "user_current-user-record",
        capability: "c".repeat(43),
        shouldCreate: true,
        title: "Weeknight",
        recipeIds: [
            "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
            "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
            "not-a-uuid",
        ],
    });
    assert.equal(collection.ok, true);
    assert.deepEqual(collection.value.recipeIds, ["018f9344-54ff-42fc-83a8-c2a92e2d1b10"]);
    assert.equal(collection.value.recipeCount, 1);
    assert.equal(collection.value.shouldCreate, true);
});

test("profile unshare requires a synchronized management capability", () => {
    const userId = "018f9344-54ff-42fc-83a8-c2a92e2d1b10";
    const identityRecordName = "user_current-user-record";
    assert.equal(sanitizeProfileUnshareInput({ userId }).ok, false);
    assert.deepEqual(sanitizeProfileUnshareInput({ userId, identityRecordName, username: "nadav", capability: "p".repeat(43) }), {
        ok: true,
        value: { userId, identityRecordName, username: "nadav", capability: "p".repeat(43) },
    });
});

test("account unshare requires owner UUID, CloudKit identity, and capability", () => {
    const userId = "018f9344-54ff-42fc-83a8-c2a92e2d1b10";
    const identityRecordName = "user_current-user-record";
    const capability = "p".repeat(43);
    assert.equal(sanitizeAccountUnshareInput({ userId, identityRecordName }).ok, false);
    assert.deepEqual(sanitizeAccountUnshareInput({ userId, identityRecordName, capability }), {
        ok: true,
        value: { userId, identityRecordName, capability },
    });
});

test("owner manifests require exact unique public UUID sets", () => {
    const ownerId = "9f082214-0c9e-4e30-94d7-072fc359d2f4";
    const recipeId = "018f9344-54ff-42fc-83a8-c2a92e2d1b10";
    const collectionId = "b1b7d3ee-8039-4fa7-a21f-4a57a7f05e75";
    const valid = sanitizeOwnerManifestInput({
        ownerId,
        identityRecordName: "user_current-user-record",
        capability: "m".repeat(43),
        publicRecipeIds: [recipeId],
        publicCollectionIds: [collectionId],
    });
    assert.equal(valid.ok, true);
    assert.deepEqual(valid.value.publicRecipeIds, [recipeId]);
    assert.equal(sanitizeOwnerManifestInput({
        ownerId,
        identityRecordName: "user_current-user-record",
        capability: "m".repeat(43),
        publicRecipeIds: [recipeId, recipeId],
        publicCollectionIds: [],
    }).ok, false);
    assert.equal(sanitizeOwnerManifestInput({
        ownerId,
        identityRecordName: "user_current-user-record",
        capability: "m".repeat(43),
        publicRecipeIds: ["not-a-uuid"],
        publicCollectionIds: [],
    }).ok, false);
});

test("stale owner manifest generations cannot delete newer derived snapshots", () => {
    const capabilityHash = "a".repeat(64);
    assert.equal(ownerManifestStateMatches({
        generation: 4,
        capabilityHash,
    }, 4, capabilityHash), true);
    assert.equal(ownerManifestStateMatches({
        generation: 5,
        capabilityHash,
    }, 4, capabilityHash), false);
    assert.equal(ownerManifestStateMatches({
        generation: 4,
        capabilityHash: "b".repeat(64),
    }, 4, capabilityHash), false);
});

test("retired account capability cannot supersede an in-flight or completed restoration", () => {
    const oldHash = "a".repeat(64);
    const newHash = "b".repeat(64);
    assert.equal(retiredCapabilityCannotSupersedeRestoration("restore", newHash, undefined, oldHash), true);
    assert.equal(retiredCapabilityCannotSupersedeRestoration("unshare", oldHash, newHash, oldHash), true);
    assert.equal(retiredCapabilityCannotSupersedeRestoration("restore", newHash, newHash, newHash), false);
});

test("account sharing restoration is bound to the original CloudKit creator record", () => {
    assert.equal(revocationCreatorMatches("user_original", "user_original"), true);
    assert.equal(revocationCreatorMatches("user_original", "user_attacker"), false);
    assert.equal(revocationCreatorMatches(undefined, "user_original"), false);
    assert.equal(restorationRevocationIsValid(
        true,
        "a".repeat(64),
        "user_original",
        "b".repeat(64),
        "user_original"
    ), true);
    assert.equal(restorationRevocationIsValid(
        true,
        "a".repeat(64),
        "user_original",
        "b".repeat(64),
        "user_attacker"
    ), false);
});

test("stale resource mutations cannot commit privacy state", () => {
    assert.equal(isCurrentResourceMutationGeneration({ generation: 4 }, 4), true);
    assert.equal(isCurrentResourceMutationGeneration({ generation: 5 }, 4), false);
    assert.equal(isCurrentResourceMutationGeneration(undefined, 1), false);
});

test("retired resource capabilities cannot overtake privacy removal", () => {
    const retiredHash = "a".repeat(64);
    const rotatedHash = "b".repeat(64);
    assert.equal(resourceMutationCannotSupersede("unshare", retiredHash, "publish", retiredHash), true);
    assert.equal(resourceMutationCannotSupersede("unshare", retiredHash, "publish", rotatedHash), false);
    assert.equal(resourceMutationCannotSupersede("publish", rotatedHash, "unshare", retiredHash), true);
    assert.equal(resourceMutationCannotSupersede("publish", retiredHash, "unshare", retiredHash), false);
});

test("collection unshare requires stable owner and private capability", () => {
    const collectionId = "018f9344-54ff-42fc-83a8-c2a92e2d1b10";
    const ownerId = "9f082214-0c9e-4e30-94d7-072fc359d2f4";
    const identityRecordName = "user_current-user-record";
    const capability = "c".repeat(43);
    assert.equal(sanitizeCollectionUnshareInput({ collectionId, ownerId }).ok, false);
    assert.deepEqual(
        sanitizeCollectionUnshareInput({ collectionId, ownerId, identityRecordName, capability }),
        { ok: true, value: { collectionId, ownerId, identityRecordName, capability } }
    );
});

test("CloudKit authority binds identity, owner, and capability hash", async () => {
    const { createHash } = await import("node:crypto");
    const ownerId = "018f9344-54ff-42fc-83a8-c2a92e2d1b10";
    const hash = createHash("sha256").update("p".repeat(43), "utf8").digest("hex");
    const record = {
        recordName: "user_current-user-record",
        recordType: "User",
        created: { timestamp: 100, userRecordName: "current-user-record" },
        fields: { userId: { value: ownerId }, webShareCapabilityHash: { value: hash } },
    };
    assert.equal(cloudKitAuthorityMatches(record, "user_current-user-record", ownerId, hash), true);
    assert.equal(cloudKitAuthorityMatches(record, "user_other", ownerId, hash), false);
    assert.equal(cloudKitAuthorityMatches(record, "user_current-user-record", ownerId, "0".repeat(64)), false);
    assert.equal(cloudKitAuthorityMatches({ ...record, created: { timestamp: 100, userRecordName: "attacker" } }, "user_current-user-record", ownerId, hash), false);

    const attackerRecord = {
        recordName: "user_attacker",
        recordType: "User",
        created: { timestamp: 200, userRecordName: "attacker" },
        fields: { userId: { value: ownerId }, webShareCapabilityHash: { value: "0".repeat(64) } },
    };
    assert.equal(canonicalCloudKitOwnerRecord([attackerRecord, record], ownerId), record);
    const creatorRecord = {
        ...record,
        fields: {
            ...record.fields,
            username: { value: "nadav" },
            displayName: { value: "Nadav" },
            profileEmoji: { value: "🧑‍🍳" },
            profileColor: { value: "#E9792F" },
        },
    };
    assert.deepEqual(
        canonicalCloudKitRecipeCreator([attackerRecord, creatorRecord], ownerId),
        { username: "nadav", displayName: "Nadav", profileEmoji: "🧑‍🍳", profileColor: "#E9792F", profileImageURL: null }
    );
    assert.equal(canonicalCloudKitRecipeCreator([attackerRecord], ownerId), null);
});

test("CloudKit HTTP-200 record errors distinguish missing data from retryable failures", () => {
    assert.equal(cloudKitRecordsPayloadDisposition({
        records: [{ serverErrorCode: "UNKNOWN_ITEM" }],
    }), "notFound");
    assert.equal(cloudKitRecordsPayloadDisposition({
        records: [{ serverErrorCode: "NOT_FOUND" }],
    }), "notFound");
    assert.equal(cloudKitRecordsPayloadDisposition({
        serverErrorCode: "NOT_FOUND",
    }), "notFound");
    assert.equal(cloudKitRecordsPayloadDisposition({
        records: [{ serverErrorCode: "TRY_AGAIN_LATER" }],
    }), "error");
    assert.equal(cloudKitRecordsPayloadDisposition({
        serverErrorCode: "SERVICE_UNAVAILABLE",
    }), "error");
    assert.equal(cloudKitRecordsPayloadDisposition({
        records: [{ recordName: "recipe-id", recordType: "SharedRecipe" }],
    }), "records");
    assert.equal(cloudKitQueryPayloadHasErrors({ records: [] }), false);
    assert.equal(cloudKitQueryPayloadHasErrors({
        records: [
            { recordName: "recipe-id", recordType: "SharedRecipe" },
            { serverErrorCode: "TRY_AGAIN_LATER" },
        ],
    }), true);
    assert.equal(cloudKitRecordsPayloadIsRetryableError({
        records: [{ serverErrorCode: "TRY_AGAIN_LATER" }],
    }), true);
    assert.equal(cloudKitRecordsPayloadIsRetryableError({
        serverErrorCode: "SERVICE_UNAVAILABLE",
    }), true);
    assert.equal(cloudKitRecordsPayloadIsRetryableError({
        records: [{ serverErrorCode: "ACCESS_DENIED" }],
    }), false);
    assert.equal(cloudKitRecordsPayloadIsRetryableError({
        serverErrorCode: "BAD_REQUEST",
    }), false);
});

test("CloudKit reads retry transient transport failures once", async () => {
    let attempts = 0;
    const result = await retryTransientCloudKitOperation(async () => {
        attempts += 1;
        if (attempts === 1) {
            throw new TypeError("fetch failed");
        }
        return "ok";
    }, 2, 0);
    assert.equal(result, "ok");
    assert.equal(attempts, 2);
});

test("CloudKit reads retry interrupted response bodies", async () => {
    let attempts = 0;
    const result = await retryTransientCloudKitOperation(async () => {
        attempts += 1;
        if (attempts === 1) {
            throw Object.assign(new TypeError("terminated"), {
                cause: { code: "UND_ERR_SOCKET" },
            });
        }
        return "ok";
    }, 2, 0);
    assert.equal(result, "ok");
    assert.equal(attempts, 2);
});

test("CloudKit retries stop at the configured cap and skip permanent failures", async () => {
    let transientAttempts = 0;
    await assert.rejects(
        retryTransientCloudKitOperation(async () => {
            transientAttempts += 1;
            throw new TypeError("fetch failed");
        }, 2, 0),
        /fetch failed/
    );
    assert.equal(transientAttempts, 2);

    let permanentAttempts = 0;
    await assert.rejects(
        retryTransientCloudKitOperation(async () => {
            permanentAttempts += 1;
            throw new Error("invalid request");
        }, 2, 0),
        /invalid request/
    );
    assert.equal(permanentAttempts, 1);
});

test("CloudKit HTTP retries are limited to transient statuses", () => {
    for (const status of [408, 425, 429, 500, 502, 503, 504]) {
        assert.equal(isTransientCloudKitHTTPStatus(status), true, `${status} should retry`);
    }
    for (const status of [400, 401, 403, 404, 409, 422]) {
        assert.equal(isTransientCloudKitHTTPStatus(status), false, `${status} should fail immediately`);
    }
});

test("CloudKit server request signature input hashes the exact body", async () => {
    const { createHash } = await import("node:crypto");
    const body = '{"records":[{"recordName":"user_123"}]}';
    const date = "2026-07-31T20:00:00Z";
    const subpath = "/database/1/iCloud.Nadav.Cauldron/production/public/records/lookup";
    const expectedHash = createHash("sha256").update(body, "utf8").digest("base64");
    assert.equal(cloudKitSignatureInput(body, date, subpath), `${date}:${expectedHash}:${subpath}`);
});

test("CloudKit owner lookup uses only production-indexed query fields", () => {
    const ownerId = "9f082214-0c9e-4e30-94d7-072fc359d2f4";
    const query = cloudKitOwnerQuery(ownerId);
    assert.deepEqual(query, {
        query: {
            recordType: "User",
            filterBy: [{
                fieldName: "userId",
                comparator: "EQUALS",
                fieldValue: { value: ownerId },
            }],
        },
        resultsLimit: 20,
    });
    assert.equal("sortBy" in query.query, false);
});

test("CloudKit referral validation accepts only canonical current User records", () => {
    const code = "ABC123";
    const record = {
        recordName: "user_current-user-record",
        recordType: "User",
        created: { userRecordName: "current-user-record" },
        fields: {
            userId: { value: "018f9344-54ff-42fc-83a8-c2a92e2d1b10" },
            referralCode: { value: code },
        },
    };
    assert.equal(cloudKitReferralRecordIsActive(record, code), true);
    assert.equal(cloudKitReferralRecordIsActive({ ...record, recordName: "user_attacker" }, code), false);
    assert.equal(cloudKitReferralRecordIsActive({ ...record, recordType: "Recipe" }, code), false);
    assert.equal(cloudKitReferralRecordIsActive({
        ...record,
        fields: { ...record.fields, referralCode: { value: "ZZZ999" } },
    }, code), false);
    assert.equal(cloudKitReferralRecordIsActive({
        ...record,
        fields: { ...record.fields, userId: { value: "not-a-uuid" } },
    }, code), false);
    assert.equal(cloudKitReferralQueryResolvesUniquely([record], code), true);
    assert.equal(cloudKitReferralQueryResolvesUniquely([record, {
        ...record,
        recordName: "user_second-record",
        created: { userRecordName: "second-record" },
        fields: {
            ...record.fields,
            userId: { value: "9f082214-0c9e-4e30-94d7-072fc359d2f4" },
        },
    }], code), false);
    assert.equal(cloudKitReferralQueryResolvesUniquely([record], code, "next-page"), false);
});

test("recipe web content is summary-only, normalized, and safe", () => {
    const recipe = sanitizeRecipeShareInput({
        recipeId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        ownerId: "9f082214-0c9e-4e30-94d7-072fc359d2f4",
        identityRecordName: "user_current-user-record",
        title: "  Tomato & Basil Soup  ",
        yields: "  4 bowls ",
        notes: "Serve warm <script>alert(1)</script> Source: https://user:password@example.com/soup?X-Amz-Credential=secret&X-Amz-Security-Token=session#method",
        sourceTitle: "Family notebook",
        sourceURL: "https://user:password@example.com/soup?X-Amz-Credential=secret&X-Amz-Security-Token=session#method",
        authorName: "Nadav",
        capability: "a".repeat(43),
        ingredients: [
            { text: "2 tomatoes", section: "Soup" },
            { text: "   ", section: "Ignored" },
            "not-an-object",
        ],
        steps: [{ text: "Simmer for 20 minutes", section: "Cook" }],
    });

    assert.equal(recipe.ok, true);
    assert.equal(recipe.value.capability, "a".repeat(43));
    assert.deepEqual(Object.keys(recipe.value).sort(), [
        "capability", "identityRecordName", "ownerId", "recipeId",
        "shouldCreate", "tags", "title", "totalMinutes",
    ]);

    const html = generateCompactRecipePageHtml(
        recipe.value,
        "https://cauldronrecipes.com/recipe/018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        "cauldron://import/recipe/018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        "https://apps.apple.com/app/id6754004943"
    );

    assert.match(html, /Tomato &amp; Basil Soup/);
    assert.doesNotMatch(html, /2 tomatoes/);
    assert.doesNotMatch(html, /Simmer for 20 minutes/);
    assert.doesNotMatch(html, /Ingredients|Method/);
    assert.doesNotMatch(html, /Shared recipe|The full recipe is available in Cauldron/);
    assert.equal((html.match(/href="cauldron:\/\/import\/recipe\//g) ?? []).length, 1);
    assert.match(html, /href="https:\/\/apps\.apple\.com\/app\/id6754004943">Get the app<\/a>/);
    assert.match(html, /window\.location\.assign\(appURL\)/);
    assert.match(html, /id="openCompactRecipe"/);
    assert.doesNotMatch(html, /class="surface"|class="secondary"/);
    assert.match(html, /<footer class="site-footer">/);
    assert.doesNotMatch(html, /application\/ld\+json/);
    assert.doesNotMatch(html, /<script>alert\(1\)<\/script>/);
    assert.doesNotMatch(html, /javascript:alert/);
    assert.doesNotMatch(html, /password|credential=secret|security-token=session/i);
});

test("profile and collection pages expose clean recipe shelves without management controls", () => {
    const recipe = sanitizeRecipeShareInput({
        recipeId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        ownerId: "9f082214-0c9e-4e30-94d7-072fc359d2f4",
        identityRecordName: "user_current-user-record",
        title: "Tomato & Basil Soup",
        capability: "a".repeat(43),
        totalMinutes: 30,
        yields: "4 bowls",
        tags: ["Dinner"],
        ingredients: [{ text: "2 tomatoes" }],
        steps: [{ text: "Simmer" }],
    });
    assert.equal(recipe.ok, true);

    const html = generateCompactRecipeIndexPageHtml({
        handle: "@chef_nadav",
        title: "Nadav <script>alert(1)</script>",
        description: "2 public recipes",
        canonicalURL: "https://cauldronrecipes.com/u/chef_nadav",
        appURL: "cauldron://import/profile/chef_nadav",
        downloadURL: "https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943",
        recipes: [recipe.value],
        totalRecipeCount: 2,
        avatarEmoji: "🧑‍🍳",
        avatarColor: "#E9792F",
    });

    assert.match(html, /Tomato &amp; Basil Soup/);
    assert.match(html, /href="\/recipe\/018f9344-54ff-42fc-83a8-c2a92e2d1b10"/);
    assert.match(html, /30 min/);
    assert.match(html, /class="recipe-media"/);
    assert.match(html, /class="recipe-placeholder"/);
    assert.match(html, /src="\/icon-small-light\.svg"/);
    assert.match(html, /class="recipe-tag"[^>]*><span aria-hidden="true">🍽️<\/span>Dinner/);
    assert.match(html, /2 recipes/);
    assert.match(html, /class="handle">@chef_nadav/);
    assert.match(html, /class="profile-avatar"[^>]*>🧑‍🍳<\/span>/);
    assert.match(html, /class="recipe-list"/);
    assert.match(html, /id="openRecipeShelf"/);
    assert.match(html, /href="https:\/\/apps\.apple\.com\/us\/app\/cauldron-magical-recipes\/id6754004943">Get the app<\/a>/);
    assert.match(html, /window\.location\.assign\(appURL\)/);
    assert.doesNotMatch(html, /class="surface"/);
    assert.match(html, /<footer class="site-footer">/);
    assert.match(html, />Get Cauldron<\/a>/);
    assert.doesNotMatch(html, /<script>alert\(1\)<\/script>/);
    assert.doesNotMatch(html, /unshare|stop sharing|make private/i);
    assert.doesNotMatch(html, /Shared recipe|Shared page|personal shelf|recipe shelf shared from Cauldron/i);
});

test("homepage presents only supplied validated recipes and complete icon metadata", () => {
    const recipe = sanitizeRecipeShareInput({
        recipeId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        ownerId: "9f082214-0c9e-4e30-94d7-072fc359d2f4",
        identityRecordName: "user_current-user-record",
        title: "Tomato & Basil Soup",
        capability: "a".repeat(43),
        totalMinutes: 30,
        tags: ["Dessert"],
    });
    assert.equal(recipe.ok, true);
    const html = generateHomePageHtml([{
        ...recipe.value,
        imageURL: "https://cvws.icloud-content.com/recipe.jpg?token=ephemeral",
        creatorDisplayName: "Nadav",
    }]);
    assert.match(html, /<h1 id="recipes-title"[^>]*>Recipes<\/h1>/);
    assert.match(html, /Tomato &amp; Basil Soup/);
    assert.match(html, /href="\/recipe\/018f9344-54ff-42fc-83a8-c2a92e2d1b10"/);
    assert.match(html, /src="https:\/\/cvws\.icloud-content\.com\/recipe\.jpg\?token=ephemeral"/);
    assert.match(html, /Get Cauldron/);
    assert.match(html, /class="creator-name">Nadav<\/span>/);
    assert.match(html, /data-filter="Dessert"/);
    assert.match(html, /class="discovery-grid"/);
    assert.match(html, /class="discovery-card"/);
    assert.match(html, /fetchpriority="high"/);
    assert.match(html, /window\.cauldronRecipeImageFailed/);
    assert.match(html, /https:\/\/www\.nadavavital\.com\/apps\/support\/\?app=Cauldron/);
    assert.match(html, /https:\/\/www\.nadavavital\.com\/cauldron\/privacy-policy\//);
    assert.doesNotMatch(html, /From the community|From found to familiar|Your recipes, remembered|Cauldron for iPhone/);
    assert.match(html, /rel="icon" type="image\/svg\+xml" href="\/favicon\.svg"/);
    assert.match(html, /rel="alternate icon" href="\/favicon\.ico"/);
    assert.match(html, /rel="apple-touch-icon" href="\/apple-touch-icon\.png"/);
    assert.doesNotMatch(generateHomePageHtml([recipe.value]), /class="recipe-media"/);
    assert.doesNotMatch(generateHomePageHtml([recipe.value]), /class="placeholder"/);
    assert.match(generateHomePageHtml([]), /Open Cauldron/);
});

test("homepage responses remain private while daily rotation prioritizes diverse owners", () => {
    assert.equal(HOMEPAGE_CACHE_CONTROL, "private, no-store, max-age=0");
    const recipes = Array.from({ length: 16 }, (_, index) => ({
        recipeId: `recipe-${index}`,
        ownerId: index < 8 ? "owner-repeat" : `owner-${index}`,
    }));
    const first = rotatingHomepageRecipeCandidates(recipes, "2026-08-29", 8, 2);
    const repeated = rotatingHomepageRecipeCandidates(recipes, "2026-08-29", 8, 2);
    const nextDay = rotatingHomepageRecipeCandidates(recipes, "2026-08-30", 8, 2);
    assert.deepEqual(first, repeated);
    assert.notDeepEqual(first.map((recipe) => recipe.recipeId), nextDay.map((recipe) => recipe.recipeId));
    assert.ok(first.filter((recipe) => recipe.ownerId === "owner-repeat").length <= 2);
    assert.ok(new Set(first.map((recipe) => recipe.ownerId)).size > 1);

    const oneCreator = recipes.filter((recipe) => recipe.ownerId === "owner-repeat");
    const filled = rotatingHomepageRecipeCandidates(oneCreator, "2026-08-29", 6, 2);
    assert.equal(filled.length, 6);
    assert.equal(new Set(filled.map((recipe) => recipe.recipeId)).size, 6);
});

test("resolved web profile photos render without persisting signed asset URLs", () => {
    const imageURL = "https://cvws.icloud-content.com/profile.jpg?token=ephemeral";
    const html = generateCompactRecipeIndexPageHtml({
        handle: "@chef_nadav",
        title: "Nadav",
        description: "Public recipes",
        canonicalURL: "https://cauldronrecipes.com/u/chef_nadav",
        appURL: "cauldron://import/profile/chef_nadav",
        downloadURL: "https://apps.apple.com/app/id6754004943",
        recipes: [],
        totalRecipeCount: 0,
        avatarEmoji: "🧑‍🍳",
        avatarColor: "#E9792F",
        avatarImageURL: imageURL,
    });
    assert.match(html, /class="profile-avatar"[^>]*><img src="https:\/\/cvws\.icloud-content\.com\/profile\.jpg\?token=ephemeral"/);
    assert.doesNotMatch(html, /🧑‍🍳/);
});

test("recipe shelves use only owner-validated CloudKit image assets", () => {
    const recipeId = "018f9344-54ff-42fc-83a8-c2a92e2d1b10";
    const ownerId = "9f082214-0c9e-4e30-94d7-072fc359d2f4";
    const creator = "creator-record";
    const summary = sanitizeRecipeShareInput({
        recipeId,
        ownerId,
        identityRecordName: "user_current-user-record",
        title: "Tomato Soup",
        capability: "a".repeat(43),
        tags: ["Dinner"],
    });
    assert.equal(summary.ok, true);
    const record = {
        recordName: recipeId,
        recordType: "SharedRecipe",
        created: { userRecordName: creator },
        fields: {
            recipeId: { value: recipeId },
            ownerId: { value: ownerId },
            visibility: { value: "public" },
            title: { value: "Tomato Soup" },
            imageAsset: { value: {
                size: 120_000,
                downloadURL: "https://cvws.icloud-content.com/image.jpg?token=signed",
            } },
        },
    };

    const creatorNames = new Map([[ownerId, creator]]);
    const [valid] = recipeIndexItemsWithCloudKitImages([summary.value], [record], creatorNames);
    assert.equal(valid.imageURL, "https://cvws.icloud-content.com/image.jpg?token=signed");

    const wrongOwner = recipeIndexItemsWithCloudKitImages([summary.value], [{
        ...record,
        fields: { ...record.fields, ownerId: { value: "018f9344-54ff-42fc-83a8-c2a92e2d1b10" } },
    }], creatorNames);
    assert.deepEqual(wrongOwner, []);
    assert.deepEqual(recipeIndexItemsWithCloudKitImages([summary.value], [{
        ...record,
        created: { userRecordName: "attacker" },
    }], creatorNames), []);

    const html = generateCompactRecipeIndexPageHtml({
        title: "Favorites",
        description: "A collection",
        canonicalURL: "https://cauldronrecipes.com/collection/test",
        appURL: "cauldron://import/collection/test",
        downloadURL: "https://apps.apple.com/app/id6754004943",
        recipes: [valid],
        totalRecipeCount: 1,
    });
    assert.match(html, /src="https:\/\/cvws\.icloud-content\.com\/image\.jpg\?token=signed"/);
    assert.match(html, /loading="lazy" decoding="async"/);
});

test("profile and collection shelves bind CloudKit secrets and request image-only fields", () => {
    const expectedSecrets = ["CLOUDKIT_SERVER_KEY_ID", "CLOUDKIT_SERVER_PRIVATE_KEY"];
    const endpointSecrets = (endpoint) => endpoint.__endpoint.secretEnvironmentVariables
        .map(({ key }) => key)
        .sort();
    assert.deepEqual(endpointSecrets(previewProfile), expectedSecrets);
    assert.deepEqual(endpointSecrets(previewCollection), expectedSecrets);
    assert.deepEqual(cloudKitRecipeShelfLookupBody([{ recipeId: "recipe-id" }]), {
        records: [{ recordName: "recipe-id" }],
        desiredKeys: [
            "recipeId",
            "ownerId",
            "visibility",
            "title",
            "imageAsset",
            "relatedRecipeIdsData",
            "originalRecipeId",
            "followsSourceUpdates",
        ],
    });
});

test("public recipe summary text strips embedded URL credentials and signed queries", () => {
    const result = sanitizeRecipeShareInput({
        recipeId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        ownerId: "9f082214-0c9e-4e30-94d7-072fc359d2f4",
        identityRecordName: "user_current-user-record",
        title: "Soup https://user:password@example.com/title?token=secret",
        capability: "q".repeat(43),
        tags: ["Tag https://example.com/tag?signature=private"],
        yields: "4 bowls https://example.com/yield?key=private",
        sourceTitle: "Source https://example.com/source?credential=secret",
        authorName: "Author https://example.com/author?token=secret",
        originalCreatorName: "Creator https://example.com/creator?signature=private",
    });

    assert.equal(result.ok, true);
    const html = generateCompactRecipePageHtml(result.value, "https://cauldronrecipes.com/recipe/test", "cauldron://recipe/test", "https://apps.apple.com/app/id6754004943");
    assert.doesNotMatch(html, /password|token=|signature=|key=|credential=/i);
    assert.match(html, /https:\/\/example.com\/title/);
});

test("compact recipe preview never emits recipe images or structured instructions", () => {
    const result = sanitizeRecipeShareInput({
        recipeId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        ownerId: "9f082214-0c9e-4e30-94d7-072fc359d2f4",
        identityRecordName: "user_current-user-record",
        title: "Tomato Soup ftp://user:password@example.com/file?token=secret",
        notes: "Open " + "https:" + "\\" + "user:password@example.com/path?token=secret",
        capability: "q".repeat(43),
        imageURL: "https://cauldronrecipes.com/recipe-images/tomato-soup.jpg",
        ingredients: [{ text: "2 tomatoes" }],
        steps: [{ text: "Simmer" }],
    });
    assert.equal(result.ok, true);
    const html = generateCompactRecipePageHtml(result.value, "https://cauldronrecipes.com/recipe/test", "cauldron://recipe/test", "https://apps.apple.com/app/id6754004943");
    assert.doesNotMatch(html, /application\/ld\+json/);
    assert.doesNotMatch(html, /recipe-images\/tomato-soup\.jpg/);
    assert.doesNotMatch(html, /2 tomatoes|Simmer/);
});

test("CloudKit public recipes render complete cookbook pages", () => {
    const recipeId = "018f9344-54ff-42fc-83a8-c2a92e2d1b10";
    const ownerId = "9f082214-0c9e-4e30-94d7-072fc359d2f4";
    const creator = "creator-record";
    const bytes = (value) => Buffer.from(JSON.stringify(value), "utf8").toString("base64");
    const record = {
        recordName: recipeId,
        recordType: "SharedRecipe",
        created: { userRecordName: creator },
        fields: {
            recipeId: { value: recipeId },
            ownerId: { value: ownerId },
            visibility: { value: "public" },
            title: { value: "Tomato & Basil Soup" },
            totalMinutes: { value: 35 },
            yields: { value: "4 bowls" },
            tagsData: { value: bytes([{ id: "tag", name: "Dinner" }]) },
            ingredientsData: { value: bytes([{
                id: "ingredient",
                name: "tomatoes",
                quantity: { value: 2, unit: "piece" },
                note: "ripe <script>alert(1)</script>",
                section: "Soup",
            }]) },
            stepsData: { value: bytes([{
                id: "step",
                index: 0,
                text: "Simmer for 20 minutes",
                timers: [],
                section: "Cook",
            }]) },
            imageAsset: { value: {
                size: 120_000,
                downloadURL: "https://cvws.icloud-content.com/image.jpg?token=signed",
            } },
        },
    };

    const recipe = sanitizeCloudKitRecipeForWeb(record, recipeId, ownerId, creator);
    assert.ok(recipe);
    assert.equal(recipe.ingredients.length, 1);
    assert.equal(recipe.steps.length, 1);
    assert.equal(recipe.imageURL, "https://cvws.icloud-content.com/image.jpg?token=signed");
    const html = generateRecipePageHtml(
        recipe,
        `https://cauldronrecipes.com/recipe/${recipeId}`,
        `cauldron://import/recipe/${recipeId}`,
        "https://apps.apple.com/app/id6754004943",
        { username: "nadav", displayName: "Nadav", profileEmoji: "🧑‍🍳", profileColor: "#E9792F" }
    );
    assert.match(html, /class="hero-image"/);
    assert.match(html, />Ingredients</);
    assert.match(html, />Instructions</);
    assert.match(html, /class="brand-icon"/);
    assert.match(html, /src="\/icon-small-light\.svg"/);
    assert.match(html, /srcset="\/icon-small-dark\.svg"/);
    assert.match(html, /class="tags" aria-label="Recipe tags"><li style="--tag-color:#AF52DE;--tag-color-dark:#BF5AF2"><span aria-hidden="true">🍽️<\/span>Dinner<\/li>/);
    assert.match(html, /--paper:#F6F1EA/);
    assert.match(html, /--accent:#FF9933/);
    assert.match(html, /background:color-mix\(in srgb,var\(--tag-color\) 15%,transparent\)/);
    assert.doesNotMatch(html, /class="cauldron-mark"/);
    assert.match(html, /class="recipe-masthead"/);
    assert.doesNotMatch(html, />Shared recipe</);
    assert.match(html, /class="intro-action"/);
    assert.match(html, /class="creator" href="\/u\/nadav"/);
    assert.match(html, /<strong>Nadav<\/strong><small>@nadav<\/small>/);
    assert.doesNotMatch(html, /Recipe by/);
    assert.match(html, /class="creator-avatar"[^>]*>🧑‍🍳<\/span>/);
    assert.equal((html.match(/href="cauldron:\/\/import\/recipe\//g) ?? []).length, 1);
    assert.match(html, /href="https:\/\/apps\.apple\.com\/app\/id6754004943">Get the app<\/a>/);
    assert.match(html, /id="openRecipe"/);
    assert.match(html, /window\.location\.assign\(appURL\)/);
    assert.doesNotMatch(html, /window\.location\.href=downloadURL/);
    assert.doesNotMatch(html, /top-action/);
    assert.match(html, /<footer class="site-footer">/);
    assert.match(html, />Get Cauldron<\/a>/);
    assert.match(html, /@media print/);
    assert.match(html, /id="shareRecipe"/);
    assert.match(html, /class="method-section" role="presentation"><h3>Cook<\/h3><\/li>/);
    assert.match(html, /overflow-wrap:anywhere/);
    assert.doesNotMatch(html, /glass-card|cook-action/);
    assert.match(html, /2 pieces/);
    assert.match(html, /tomatoes/);
    assert.match(html, /Simmer for 20 minutes/);
    assert.match(html, /application\/ld\+json/);
    assert.doesNotMatch(html, /<script>alert\(1\)<\/script>/);
    assert.doesNotMatch(html, /unshare|stop sharing|make private/i);
    assert.equal(sanitizeCloudKitRecipeForWeb(record, recipeId, crypto.randomUUID(), creator), null);
    assert.equal(sanitizeCloudKitRecipeForWeb(record, recipeId, ownerId, "attacker"), null);
});

test("web profile materialization hides recipes referenced by a canonical parent", () => {
    const parentId = "018f9344-54ff-42fc-83a8-c2a92e2d1b10";
    const childId = "601e40f5-3abe-42cb-9d9d-f37530cd3963";
    const base = {
        ownerId: "9f082214-0c9e-4e30-94d7-072fc359d2f4",
        title: "Recipe",
        yields: null,
        totalMinutes: null,
        tags: [],
        ingredients: [],
        steps: [],
        relatedGraphReferenceId: parentId,
        imageURL: null,
    };
    assert.deepEqual(hideRelatedWebRecipeReferences([
        { ...base, recipeId: parentId, relatedRecipeIds: [childId] },
        { ...base, recipeId: childId, relatedRecipeIds: [], relatedGraphReferenceId: childId },
    ]).map((recipe) => recipe.recipeId), [parentId]);

    const savedCopyId = "f4181742-d7f8-414f-a03e-eaed2d0bb301";
    assert.deepEqual(hideRelatedWebRecipeReferences([
        { ...base, recipeId: parentId, relatedRecipeIds: [childId] },
        {
            ...base,
            recipeId: savedCopyId,
            relatedRecipeIds: [],
            relatedGraphReferenceId: childId,
        },
    ]).map((recipe) => recipe.recipeId), [parentId]);

    assert.deepEqual(hideRelatedWebRecipeReferences([
        { ...base, recipeId: parentId, relatedRecipeIds: [childId] },
        { ...base, recipeId: childId, relatedRecipeIds: [parentId], relatedGraphReferenceId: childId },
    ]).map((recipe) => recipe.recipeId), [parentId, childId]);

    assert.deepEqual(permanentlyInvalidRecipeShelfIDs(
        [parentId, childId],
        [{ recordName: parentId }, { recordName: childId }],
        [parentId, childId]
    ), []);
    assert.deepEqual(permanentlyInvalidRecipeShelfIDs(
        [parentId, childId],
        [{ recordName: parentId }, { recordName: childId, serverErrorCode: "UNKNOWN_ITEM" }],
        [parentId]
    ), [childId]);
});

test("public recipe data omits internal related recipe graph identifiers", () => {
    const recipeId = "018f9344-54ff-42fc-83a8-c2a92e2d1b10";
    const childId = "601e40f5-3abe-42cb-9d9d-f37530cd3963";
    const publicData = publicWebRecipeData({
        recipeId,
        ownerId: "9f082214-0c9e-4e30-94d7-072fc359d2f4",
        title: "Recipe",
        yields: null,
        totalMinutes: null,
        tags: [],
        ingredients: [],
        steps: [],
        relatedRecipeIds: [childId],
        imageURL: null,
    });

    assert.equal(publicData.recipeId, recipeId);
    assert.equal("relatedRecipeIds" in publicData, false);
});

test("canonical recipe routes never render a Firebase-only compact fallback", () => {
    const rendered = renderCanonicalRecipePage(
        null,
        null,
        "https://cauldronrecipes.com/recipe/recipe-id",
        "cauldron://import/recipe/recipe-id",
        "https://apps.apple.com/app/id6754004943"
    );
    assert.equal(rendered.status, 404);
    assert.match(rendered.html, /Recipe unavailable/);
    assert.doesNotMatch(rendered.html, /Open this recipe|Ingredients|Recipe details/);
});

test("public status pages use the shared restrained design and escape messages", () => {
    const html = generatePublicStatusPageHtml(
        "Recipe <unavailable>",
        "Try again <script>alert(1)</script>"
    );
    assert.match(html, /Recipe &lt;unavailable&gt;/);
    assert.match(html, /Try again &lt;script&gt;alert\(1\)&lt;\/script&gt;/);
    assert.match(html, /icon-small-light\.svg/);
    assert.doesNotMatch(html, /class="surface"/);
    assert.match(html, /<footer class="site-footer">/);
    assert.match(html, />Get Cauldron<\/a>/);
    assert.doesNotMatch(html, /<script>alert\(1\)<\/script>/);
});

test("profile preview uses HTTPS canonical metadata and emoji fallback", () => {
    const html = generatePreviewHtml(
        "Nadav",
        "12 recipes",
        null,
        "https://cauldronrecipes.com/profile/owner-id",
        "cauldron://import/profile/owner-id",
        "https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943",
        "🧑‍🍳",
        "#FF9933"
    );
    assert.match(html, /property="og:url" content="https:\/\/cauldronrecipes\.com\/profile\/owner-id"/);
    assert.match(html, /rel="canonical" href="https:\/\/cauldronrecipes\.com\/profile\/owner-id"/);
    assert.match(html, /twitter:app:id:iphone" content="6754004943"/);
    assert.match(html, /🧑‍🍳/);
});

test("persisted snapshots render without storing the private capability", () => {
    const snapshot = sanitizeStoredRecipeShareInput({
        recipeId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        ownerId: "9f082214-0c9e-4e30-94d7-072fc359d2f4",
        title: "Tomato Soup ftp://user:password@example.com/file?token=secret",
        notes: "Open " + "https:" + "\\" + "user:password@example.com/path?token=secret",
        ingredients: [{ text: "2 tomatoes", section: null }],
        steps: [{ text: "Simmer", section: null }],
        capabilityHash: "0".repeat(64),
    });
    assert.equal(snapshot.ok, true);
    assert.equal(snapshot.value.title, "Tomato Soup [private URL removed]");
    assert.equal("notes" in snapshot.value, false);
    assert.equal("ingredients" in snapshot.value, false);
    assert.equal("steps" in snapshot.value, false);
});

test("legacy profile and collection snapshots are re-sanitized before public reads", () => {
    const userId = "9f082214-0c9e-4e30-94d7-072fc359d2f4";
    const profile = sanitizeStoredProfileShareInput({
        userId,
        ownerId: userId,
        username: "nadav",
        displayName: "Nadav //user:password@example.com/profile?token=secret",
        profileImageURL: "https://example.com/avatar.jpg?signature=private",
        profileEmoji: "https:" + "\\" + "u:p@x.co",
    });
    assert.equal(profile.ok, true);
    assert.equal(profile.value.displayName, "Nadav [private URL removed]");
    assert.equal("profileImageURL" in profile.value, false);
    assert.equal(profile.value.profileEmoji, null);

    const collection = sanitizeStoredCollectionShareInput({
        collectionId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        ownerId: userId,
        title: "Favorites ftp://user:password@example.com/list?credential=secret",
        coverImageURL: "https://user:password@example.com/cover.jpg",
        recipeIds: [],
    });
    assert.equal(collection.ok, true);
    assert.equal(collection.value.title, "Favorites [private URL removed]");
    assert.equal("coverImageURL" in collection.value, false);
});

test("unshare metadata requires both stable identities", () => {
    assert.deepEqual(
        sanitizeRecipeUnshareInput({
            recipeId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
            ownerId: "9f082214-0c9e-4e30-94d7-072fc359d2f4",
            identityRecordName: "user_current-user-record",
            capability: "b".repeat(43),
        }),
        {
            ok: true,
            value: {
                recipeId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
                ownerId: "9f082214-0c9e-4e30-94d7-072fc359d2f4",
                identityRecordName: "user_current-user-record",
                capability: "b".repeat(43),
            },
        }
    );
    assert.equal(sanitizeRecipeUnshareInput({ recipeId: "bad", ownerId: "also-bad" }).ok, false);
    assert.equal(
        sanitizeRecipeUnshareInput({
            recipeId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
            ownerId: "9f082214-0c9e-4e30-94d7-072fc359d2f4",
        }).ok,
        false
    );
});

test("recipe snapshots discard aggregate rich payloads before Firestore", () => {
    const oversized = sanitizeRecipeShareInput({
        recipeId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        ownerId: "9f082214-0c9e-4e30-94d7-072fc359d2f4",
        identityRecordName: "user_current-user-record",
        title: "Oversized",
        capability: "c".repeat(43),
        ingredients: Array.from({ length: 500 }, () => ({ text: "🍅".repeat(1_000) })),
        steps: Array.from({ length: 300 }, () => ({ text: "🥣".repeat(1_000) })),
    });

    assert.equal(oversized.ok, true);
    assert.equal("ingredients" in oversized.value, false);
    assert.equal("steps" in oversized.value, false);
});
