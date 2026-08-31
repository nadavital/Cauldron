import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import {
    assertFails,
    initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
    deleteDoc,
    doc,
    getDoc,
    setDoc,
} from "firebase/firestore";

const projectId = "demo-cauldron-rules";
const rulesPath = fileURLToPath(new URL("../../firestore.rules", import.meta.url));
const protectedCollections = [
    "shared_recipes",
    "shared_profiles",
    "shared_collections",
    "share_revocations",
    "share_account_mutation_states",
    "share_mutation_states",
    "share_privacy_epochs",
    "share_rate_limits",
    "share_read_rate_limits",
];

let environment;

before(async () => {
    environment = await initializeTestEnvironment({
        projectId,
        firestore: {
            rules: await readFile(rulesPath, "utf8"),
        },
    });
});

after(async () => {
    await environment?.cleanup();
});

for (const collectionName of protectedCollections) {
    test(`unauthenticated clients cannot read or write ${collectionName}`, async () => {
        const firestore = environment.unauthenticatedContext().firestore();
        const reference = doc(firestore, collectionName, "test-document");
        await assertFails(getDoc(reference));
        await assertFails(setDoc(reference, { ownerId: "attacker" }));
        await assertFails(deleteDoc(reference));
    });

    test(`authenticated clients cannot bypass Functions for ${collectionName}`, async () => {
        const firestore = environment.authenticatedContext("test-user").firestore();
        const reference = doc(firestore, collectionName, "test-document");
        await assertFails(getDoc(reference));
        await assertFails(setDoc(reference, { ownerId: "test-user" }));
        await assertFails(deleteDoc(reference));
    });
}

test("Admin SDK remains the only persistence boundary", async () => {
    await environment.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), "shared_recipes", "server-write"), {
            ownerId: "server",
        });
    });

    const clientReference = doc(
        environment.authenticatedContext("server").firestore(),
        "shared_recipes",
        "server-write"
    );
    await assertFails(getDoc(clientReference));
    assert.ok(true);
});

test("homepage archive query reaches older and timestamp-less records with bounded unique results", async () => {
    assert.ok(process.env.FIRESTORE_EMULATOR_HOST, "Archive query tests must never use production");
    const { initializeApp, deleteApp } = await import("firebase-admin/app");
    const { getFirestore, Timestamp } = await import("firebase-admin/firestore");
    const { loadHomepageRecipeDocuments } = await import("../lib/index.js");
    const app = initializeApp({ projectId }, "homepage-query-test");
    const firestore = getFirestore(app);
    const collection = firestore.collection("homepage_query_fixture");
    const refs = Array.from({ length: 41 }, (_, i) => collection.doc(`00000000-0000-0000-0000-${String(i).padStart(12, "0")}`));
    try {
        const batch = firestore.batch();
        refs.forEach((ref, i) => batch.set(ref, i === 0 ? { title: "Legacy recipe" } : { updatedAt: Timestamp.fromMillis(i * 1000) }));
        await batch.commit();
        const { recent, archive } = await loadHomepageRecipeDocuments(collection, "2026-08-30");
        assert.equal(recent.length, 24);
        assert.equal(archive.length, 36);
        assert.equal(new Set(archive.map((doc) => doc.id)).size, 36);
        assert.ok(archive.some((doc) => doc.id === refs[0].id));
        assert.ok(archive.some((doc) => !recent.some((r) => r.id === doc.id)));
        assert.equal(recent[0].id, refs[40].id);
    } finally {
        const batch = firestore.batch();
        refs.forEach((ref) => batch.delete(ref));
        await batch.commit();
        await deleteApp(app);
    }
});
