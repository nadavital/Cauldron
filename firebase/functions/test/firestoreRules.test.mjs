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
