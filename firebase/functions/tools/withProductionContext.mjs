import { spawn } from "node:child_process";
import { loadProductionCloudKitEnvironment } from "./productionContext.mjs";

const command = process.argv.slice(2);
if (command.length === 0) throw new Error("Pass a command to run with the production preflight environment.");
const environment = {
    ...process.env,
    ...await loadProductionCloudKitEnvironment(),
    CLOUDKIT_PREFLIGHT_USER_RECORD: process.env.CLOUDKIT_PREFLIGHT_USER_RECORD || "user__2beb0e7ec9a94d65fef255a49b575cac",
    CLOUDKIT_PREFLIGHT_USERNAME_CLAIM_RECORD: process.env.CLOUDKIT_PREFLIGHT_USERNAME_CLAIM_RECORD || "username_nadav",
    CLOUDKIT_PREFLIGHT_SHARED_RECIPE_RECORD: process.env.CLOUDKIT_PREFLIGHT_SHARED_RECIPE_RECORD || "7DBEAFFD-895F-43B1-9985-463F36EA5D8C",
    CLOUDKIT_PREFLIGHT_COLLECTION_RECORD: process.env.CLOUDKIT_PREFLIGHT_COLLECTION_RECORD || "9B0D2D38-3B17-406A-83EC-3F35B21BDB42",
};
const child = spawn(command[0], command.slice(1), { env: environment, stdio: "inherit" });
child.on("error", () => { console.error("Could not start the requested production check."); process.exitCode = 1; });
child.on("exit", (code) => { process.exitCode = code ?? 1; });
