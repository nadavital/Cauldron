import { execFile } from "node:child_process";
import { promisify } from "node:util";

const exec = promisify(execFile);
export const projectId = "cauldron-f900a";

// Credentials remain in process memory and are only used with their intended
// Google/CloudKit services. Never log command output or persist the values.
async function gcloud(args) {
    try {
        const { stdout } = await exec("gcloud", args, {
            maxBuffer: 1024 * 1024,
            timeout: 30_000,
        });
        return stdout.trim();
    } catch {
        throw new Error(`Google Cloud authorization failed for ${args[0]} ${args[1]}; check the active gcloud account.`);
    }
}

export async function loadProductionCloudKitEnvironment() {
    const values = await Promise.all([
        "CLOUDKIT_SERVER_KEY_ID", "CLOUDKIT_SERVER_PRIVATE_KEY",
    ].map(async (name) => [name, await gcloud([
        "secrets", "versions", "access", "latest", `--secret=${name}`,
        `--project=${projectId}`, "--quiet",
    ])]));
    return Object.fromEntries(values);
}

export function googleCloudCredential() {
    let cached;
    let expiresAt = 0;
    return {
        async getAccessToken() {
            if (!cached || Date.now() >= expiresAt) {
                cached = await gcloud(["auth", "print-access-token", "--quiet"]);
                expiresAt = Date.now() + 45 * 60 * 1000;
            }
            return { access_token: cached, expires_in: 2700 };
        },
    };
}
