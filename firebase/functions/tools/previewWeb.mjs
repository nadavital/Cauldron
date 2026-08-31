import http from "node:http";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { GoogleAuth, OAuth2Client } from "google-auth-library";
import { googleCloudCredential, loadProductionCloudKitEnvironment, projectId } from "./productionContext.mjs";
import { createPreviewHandler } from "./previewWebHandler.mjs";

Object.assign(process.env, await loadProductionCloudKitEnvironment());
initializeApp({ projectId });
const credential = googleCloudCredential();
const authClient = new OAuth2Client();
authClient.refreshHandler = async () => {
    const token = await credential.getAccessToken();
    return { access_token: token.access_token, expiry_date: Date.now() + token.expires_in * 1000 };
};
getFirestore().settings({ projectId, auth: new GoogleAuth({ projectId, authClient }) });
const { loadHomepageRecipeShelf, generateHomePageHtml, generatePublicStatusPageHtml, publicSecurityHeaders } = await import("../lib/index.js");
const publicDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "../../public");
const port = 8766;

const server = http.createServer(createPreviewHandler({
    publicDirectory,
    loadHome: loadHomepageRecipeShelf,
    renderHome: generateHomePageHtml,
    renderError: generatePublicStatusPageHtml,
    securityHeaders: publicSecurityHeaders,
    log: (event) => console.log(JSON.stringify(event)),
}));
server.listen(port, "127.0.0.1", () => console.log(`Read-only production-data preview: http://127.0.0.1:${port}/`));
