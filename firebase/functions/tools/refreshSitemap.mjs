// Explicit operational repair/bootstrap; updates only the derived sitemap manifest.
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { GoogleAuth, OAuth2Client } from "google-auth-library";
import { googleCloudCredential, loadProductionCloudKitEnvironment, projectId } from "./productionContext.mjs";

if (process.argv[2] !== "--apply") throw new Error("Pass --apply to refresh the production sitemap manifest.");
Object.assign(process.env, await loadProductionCloudKitEnvironment());
initializeApp({ projectId });
const credential = googleCloudCredential();
const authClient = new OAuth2Client();
authClient.refreshHandler = async () => {
    const token = await credential.getAccessToken();
    return { access_token: token.access_token, expiry_date: Date.now() + token.expires_in * 1000 };
};
getFirestore().settings({ projectId, auth: new GoogleAuth({ projectId, authClient }) });
const { refreshCatalogSitemapManifest } = await import("../lib/index.js");
console.log(JSON.stringify(await refreshCatalogSitemapManifest()));
