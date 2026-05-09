import assert from "node:assert/strict";
import test from "node:test";
import {
    escapeHtml,
    isValidUUID,
    safeImageURL,
    sanitizeCollectionShareInput,
    sanitizeProfileShareInput,
    sanitizeRecipeShareInput,
} from "../lib/index.js";

test("escapeHtml escapes preview metadata", () => {
    assert.equal(
        escapeHtml(`<script>alert("x")</script> & 'bad'`),
        "&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt; &amp; &#39;bad&#39;"
    );
});

test("safeImageURL accepts only valid https image URLs", () => {
    assert.equal(
        safeImageURL("https://example.com/image.jpg"),
        "https://example.com/image.jpg"
    );
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
            title: "Soup",
        }).ok,
        false
    );

    assert.equal(
        sanitizeProfileShareInput({
            userId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
            username: "../admin",
        }).ok,
        false
    );
});

test("share metadata validation bounds and normalizes client-controlled fields", () => {
    const recipe = sanitizeRecipeShareInput({
        recipeId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        ownerId: "9f082214-0c9e-4e30-94d7-072fc359d2f4",
        title: "  Tomato Soup  ",
        imageURL: "http://example.com/image.jpg",
        ingredientCount: 9999,
        totalMinutes: -1,
        tags: ["Dinner", " dinner ", "", "x".repeat(80)],
    });

    assert.equal(recipe.ok, true);
    assert.deepEqual(recipe.value, {
        recipeId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        ownerId: "9f082214-0c9e-4e30-94d7-072fc359d2f4",
        title: "Tomato Soup",
        imageURL: null,
        ingredientCount: 500,
        totalMinutes: null,
        tags: ["Dinner", "x".repeat(48)],
    });

    const profile = sanitizeProfileShareInput({
        userId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        username: "Chef_Nadav",
        recipeCount: 25,
    });
    assert.equal(profile.ok, true);
    assert.equal(profile.value.username, "chef_nadav");
    assert.equal(profile.value.displayName, "Chef_Nadav");

    const collection = sanitizeCollectionShareInput({
        collectionId: "018f9344-54ff-42fc-83a8-c2a92e2d1b10",
        ownerId: "9f082214-0c9e-4e30-94d7-072fc359d2f4",
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
});
