import { execFileSync } from "node:child_process";

const projectId = process.env.GCLOUD_PROJECT || "cauldron-f900a";
const shouldApply = process.argv.includes("--apply");
const collectionIds = ["shared_recipes", "shared_profiles", "shared_collections"];
const sensitiveFields = [
    "imageURL",
    "ingredientCount",
    "yields",
    "notes",
    "sourceTitle",
    "sourceURL",
    "authorName",
    "originalCreatorName",
    "ingredients",
    "steps",
    "profileImageURL",
    "coverImageURL",
];
const token = execFileSync("gcloud", ["auth", "print-access-token"], {
    encoding: "utf8",
}).trim();
const documentRoot = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;

async function request(url, options = {}) {
    const response = await fetch(url, {
        ...options,
        headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
            ...(options.headers ?? {}),
        },
    });
    if (!response.ok) {
        throw new Error(`${response.status} ${response.statusText}: ${await response.text()}`);
    }
    return response.status === 204 ? null : response.json();
}

async function listSnapshots(collectionId) {
    const documents = [];
    let pageToken;
    do {
        const params = new URLSearchParams({ pageSize: "100" });
        if (pageToken) params.set("pageToken", pageToken);
        const page = await request(`${documentRoot}/${collectionId}?${params}`);
        documents.push(...(page.documents ?? []));
        pageToken = page.nextPageToken;
    } while (pageToken);
    return documents;
}

function sensitiveKeys(document) {
    const fields = document.fields ?? {};
    return sensitiveFields.filter((field) => Object.hasOwn(fields, field));
}

const documents = (await Promise.all(collectionIds.map(listSnapshots))).flat();
const affected = documents.filter((document) => sensitiveKeys(document).length > 0);
console.log(JSON.stringify({
    mode: shouldApply ? "apply" : "dry-run",
    projectId,
    scanned: documents.length,
    affected: affected.length,
}));

if (shouldApply) {
    for (const document of affected) {
        const masks = sensitiveKeys(document)
            .map((field) => `updateMask.fieldPaths=${encodeURIComponent(field)}`)
            .join("&");
        await request(`https://firestore.googleapis.com/v1/${document.name}?${masks}`, {
            method: "PATCH",
            body: JSON.stringify({ fields: {} }),
        });
    }

    const remaining = (await Promise.all(collectionIds.map(listSnapshots))).flat()
        .filter((document) => sensitiveKeys(document).length > 0);
    console.log(JSON.stringify({ scrubbed: affected.length, remaining: remaining.length }));
    if (remaining.length > 0) process.exitCode = 1;
}
