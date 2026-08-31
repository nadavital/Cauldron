import { googleCloudCredential, projectId } from "./productionContext.mjs";

const origin = "https://firebasehosting.googleapis.com/v1beta1";
const parent = `projects/${projectId}/sites/${projectId}`;
const domain = "www.cauldronrecipes.com";
const redirectTarget = "cauldronrecipes.com";
const token = await googleCloudCredential().getAccessToken();
const headers = { Authorization: `Bearer ${token.access_token}`, "Content-Type": "application/json", "X-Goog-User-Project": projectId };
const url = `${origin}/${parent}/customDomains/${domain}`;
const current = await fetch(url, { headers, signal: AbortSignal.timeout(30_000) });
if (current.status !== 404 && !current.ok) throw new Error(`Domain read failed: ${current.status} ${await current.text()}`);
const data = current.ok ? await current.json() : null;
if (!process.argv.includes("--apply")) {
    console.log(JSON.stringify(data ?? { domain, exists: false, proposedRedirectTarget: redirectTarget }, null, 2));
} else if (data?.redirectTarget === redirectTarget) {
    console.log(JSON.stringify(data, null, 2));
} else {
    const response = await fetch(data ? `${url}?updateMask=redirectTarget` :
        `${origin}/${parent}/customDomains?customDomainId=${domain}`, {
        method: data ? "PATCH" : "POST", headers,
        body: JSON.stringify({ redirectTarget, ...(data?.etag ? { etag: data.etag } : {}) }),
        signal: AbortSignal.timeout(30_000),
    });
    if (!response.ok) throw new Error(`Domain configuration failed: ${response.status} ${await response.text()}`);
    console.log(JSON.stringify(await response.json(), null, 2));
}
