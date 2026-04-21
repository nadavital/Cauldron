import { Buffer } from "node:buffer";

export function normalizeSearchValue(value) {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/\p{Mark}+/gu, "")
    .toLowerCase()
    .trim();
}

export function tokenizeSearchText(text) {
  return normalizeSearchValue(text)
    .split(/[^\p{L}\p{N}]+/u)
    .filter((token) => Array.from(token).length >= 2);
}

export function uniqueSearchTerms(values) {
  const terms = new Set();

  for (const value of values) {
    for (const token of tokenizeSearchText(value)) {
      if (token) {
        terms.add(token);
      }
    }
  }

  return [...terms].sort();
}

export function decodeBytesField(field) {
  if (!field || typeof field.value !== "string" || field.value.length === 0) {
    return null;
  }

  try {
    return JSON.parse(Buffer.from(field.value, "base64").toString("utf8"));
  } catch {
    return null;
  }
}

export function getStringListFieldValue(field) {
  if (!field) {
    return [];
  }

  if (Array.isArray(field.value)) {
    return field.value.filter((value) => typeof value === "string");
  }

  return [];
}

export function deriveSearchFieldsFromRecord(record) {
  const fields = record?.fields ?? {};
  const title = typeof fields.title?.value === "string" ? fields.title.value : "";
  const tags = decodeBytesField(fields.tagsData);
  const ingredients = decodeBytesField(fields.ingredientsData);

  const tagNames = Array.isArray(tags)
    ? tags.map((tag) => tag?.name).filter((name) => typeof name === "string")
    : [];
  const ingredientNames = Array.isArray(ingredients)
    ? ingredients.map((ingredient) => ingredient?.name).filter((name) => typeof name === "string")
    : [];

  return {
    searchableTags: uniqueSearchTerms(tagNames),
    searchableTitleTerms: uniqueSearchTerms([title]),
    searchableIngredients: uniqueSearchTerms(ingredientNames),
  };
}

export function areStringArraysEqual(left, right) {
  if (left.length !== right.length) {
    return false;
  }

  return left.every((value, index) => value === right[index]);
}
