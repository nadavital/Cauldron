import test from "node:test";
import assert from "node:assert/strict";
import { Buffer } from "node:buffer";
import {
  deriveSearchFieldsFromRecord,
  normalizeSearchValue,
  tokenizeSearchText,
  uniqueSearchTerms,
} from "./shared_recipe_search_terms.mjs";

function encodeJson(value) {
  return {
    value: Buffer.from(JSON.stringify(value), "utf8").toString("base64"),
    type: "BYTES",
  };
}

test("normalizeSearchValue folds case and diacritics", () => {
  assert.equal(normalizeSearchValue("  Crème Brûlée  "), "creme brulee");
});

test("tokenizeSearchText matches the app's 2+ character token rule", () => {
  assert.deepEqual(tokenizeSearchText("A 12-oz Café au lait"), ["12", "oz", "cafe", "au", "lait"]);
});

test("uniqueSearchTerms deduplicates and sorts", () => {
  assert.deepEqual(uniqueSearchTerms(["Apple pie", "apple tart"]), ["apple", "pie", "tart"]);
});

test("deriveSearchFieldsFromRecord extracts title, tags, and ingredient terms", () => {
  const record = {
    fields: {
      title: { value: "Crème Brûlée Pancakes" },
      tagsData: encodeJson([{ name: "Breakfast" }, { name: "Sweet Treat" }]),
      ingredientsData: encodeJson([{ name: "Heavy Cream" }, { name: "Vanilla Bean" }]),
    },
  };

  assert.deepEqual(deriveSearchFieldsFromRecord(record), {
    searchableTags: ["breakfast", "sweet", "treat"],
    searchableTitleTerms: ["brulee", "creme", "pancakes"],
    searchableIngredients: ["bean", "cream", "heavy", "vanilla"],
  });
});
