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
    cloudKitOwnerQuery,
    cloudKitRecordsPayloadDisposition,
    cloudKitSignatureInput,
    generateCompactRecipeIndexPageHtml,
    generateCompactRecipePageHtml,
    generateInvitePreviewHtml,
    generatePublicStatusPageHtml,
    generateRecipePageHtml,
    generatePreviewHtml,
    isValidUUID,
    isCurrentResourceMutationGeneration,
    publicSecurityHeaders,
    publishedShareResponse,
    recipeCategoryPresentation,
    renderCanonicalRecipePage,
    resourceMutationCannotSupersede,
    safeImageURL,
    sanitizeAccountUnshareInput,
    sanitizeCollectionShareInput,
    sanitizeCollectionUnshareInput,
    sanitizeCloudKitRecipeForWeb,
    sanitizeProfileShareInput,
    sanitizeProfileUnshareInput,
    sanitizeRecipeShareInput,
    sanitizeStoredRecipeShareInput,
    sanitizeStoredProfileShareInput,
    sanitizeStoredCollectionShareInput,
    retiredCapabilityCannotSupersedeRestoration,
    sanitizeRecipeUnshareInput,
} from "../lib/index.js";

test("share publication responses expose the write outcome on every endpoint", () => {
    assert.deepEqual(
        publishedShareResponse("profile-id", "https://cauldron-f900a.web.app/profile/profile-id", true),
        {
            shareId: "profile-id",
            shareUrl: "https://cauldron-f900a.web.app/profile/profile-id",
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
    assert.equal(safeImageURL("https://cauldron-f900a.web.app/images/recipe.jpg?token=secret#crop"), "https://cauldron-f900a.web.app/images/recipe.jpg");
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

test("retired account capability cannot supersede an in-flight or completed restoration", () => {
    const oldHash = "a".repeat(64);
    const newHash = "b".repeat(64);
    assert.equal(retiredCapabilityCannotSupersedeRestoration("restore", newHash, undefined, oldHash), true);
    assert.equal(retiredCapabilityCannotSupersedeRestoration("unshare", oldHash, newHash, oldHash), true);
    assert.equal(retiredCapabilityCannotSupersedeRestoration("restore", newHash, newHash, newHash), false);
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
        { username: "nadav", displayName: "Nadav", profileEmoji: "🧑‍🍳", profileColor: "#E9792F" }
    );
    assert.equal(canonicalCloudKitRecipeCreator([attackerRecord], ownerId), null);
});

test("CloudKit HTTP-200 record errors distinguish missing data from retryable failures", () => {
    assert.equal(cloudKitRecordsPayloadDisposition({
        records: [{ serverErrorCode: "UNKNOWN_ITEM" }],
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
        "https://cauldron-f900a.web.app/recipe/018f9344-54ff-42fc-83a8-c2a92e2d1b10",
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
    assert.doesNotMatch(html, /surface|secondary|<footer/);
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
        canonicalURL: "https://cauldron-f900a.web.app/u/chef_nadav",
        appURL: "cauldron://import/profile/chef_nadav",
        downloadURL: "https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943",
        recipes: [recipe.value],
        totalRecipeCount: 2,
        avatarEmoji: "🧑‍🍳",
        avatarColor: "#E9792F",
    });

    assert.match(html, /Tomato &amp; Basil Soup/);
    assert.match(html, /href="\/recipe\/018f9344-54ff-42fc-83a8-c2a92e2d1b10"/);
    assert.doesNotMatch(html, /30 min|recipe-time/);
    assert.match(html, /2 recipes/);
    assert.match(html, /class="handle">@chef_nadav/);
    assert.match(html, /class="profile-avatar"[^>]*>🧑‍🍳<\/span>/);
    assert.match(html, /class="recipe-list"/);
    assert.match(html, /id="openRecipeShelf"/);
    assert.match(html, /href="https:\/\/apps\.apple\.com\/us\/app\/cauldron-magical-recipes\/id6754004943">Get the app<\/a>/);
    assert.match(html, /window\.location\.assign\(appURL\)/);
    assert.doesNotMatch(html, /class="surface"|<footer|Get Cauldron/);
    assert.doesNotMatch(html, /<script>alert\(1\)<\/script>/);
    assert.doesNotMatch(html, /unshare|stop sharing|make private/i);
    assert.doesNotMatch(html, /Shared recipe|Shared page|personal shelf|recipe shelf shared from Cauldron/i);
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
    const html = generateCompactRecipePageHtml(result.value, "https://cauldron-f900a.web.app/recipe/test", "cauldron://recipe/test", "https://apps.apple.com/app/id6754004943");
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
        imageURL: "https://cauldron-f900a.web.app/recipe-images/tomato-soup.jpg",
        ingredients: [{ text: "2 tomatoes" }],
        steps: [{ text: "Simmer" }],
    });
    assert.equal(result.ok, true);
    const html = generateCompactRecipePageHtml(result.value, "https://cauldron-f900a.web.app/recipe/test", "cauldron://recipe/test", "https://apps.apple.com/app/id6754004943");
    assert.doesNotMatch(html, /application\/ld\+json/);
    assert.doesNotMatch(html, /recipe-images\/tomato-soup\.jpg/);
    assert.doesNotMatch(html, /2 tomatoes|Simmer/);
});

test("CloudKit public recipes render complete cookbook pages", () => {
    const recipeId = "018f9344-54ff-42fc-83a8-c2a92e2d1b10";
    const ownerId = "9f082214-0c9e-4e30-94d7-072fc359d2f4";
    const bytes = (value) => Buffer.from(JSON.stringify(value), "utf8").toString("base64");
    const record = {
        recordName: recipeId,
        recordType: "SharedRecipe",
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

    const recipe = sanitizeCloudKitRecipeForWeb(record, recipeId, ownerId);
    assert.ok(recipe);
    assert.equal(recipe.ingredients.length, 1);
    assert.equal(recipe.steps.length, 1);
    assert.equal(recipe.imageURL, "https://cvws.icloud-content.com/image.jpg?token=signed");
    const html = generateRecipePageHtml(
        recipe,
        `https://cauldron-f900a.web.app/recipe/${recipeId}`,
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
    assert.doesNotMatch(html, /<footer|top-action|Get Cauldron/);
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
    assert.equal(sanitizeCloudKitRecipeForWeb(record, recipeId, crypto.randomUUID()), null);
});

test("canonical recipe routes never render a Firebase-only compact fallback", () => {
    const rendered = renderCanonicalRecipePage(
        null,
        null,
        "https://cauldron-f900a.web.app/recipe/recipe-id",
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
    assert.doesNotMatch(html, /class="surface"|<footer|Get Cauldron/);
    assert.doesNotMatch(html, /<script>alert\(1\)<\/script>/);
});

test("profile preview uses HTTPS canonical metadata and emoji fallback", () => {
    const html = generatePreviewHtml(
        "Nadav",
        "12 recipes",
        null,
        "https://cauldron-f900a.web.app/profile/owner-id",
        "cauldron://import/profile/owner-id",
        "https://apps.apple.com/us/app/cauldron-magical-recipes/id6754004943",
        "🧑‍🍳",
        "#FF9933"
    );
    assert.match(html, /property="og:url" content="https:\/\/cauldron-f900a\.web\.app\/profile\/owner-id"/);
    assert.match(html, /rel="canonical" href="https:\/\/cauldron-f900a\.web\.app\/profile\/owner-id"/);
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
