import { spawnSync } from "node:child_process";

const result = spawnSync("java", ["-version"], { encoding: "utf8" });
if (result.error?.code === "ENOENT") {
    fail("Java is not installed. Install JDK 21 and set JAVA_HOME before running Firestore rules tests.");
}
if (result.status !== 0) {
    fail(`java -version failed: ${(result.stderr || result.stdout).trim()}`);
}

const output = `${result.stderr}\n${result.stdout}`;
const match = output.match(/version\s+"(?:1\.)?(\d+)/i)
    ?? output.match(/openjdk\s+(\d+)/i);
const majorVersion = match ? Number.parseInt(match[1], 10) : Number.NaN;
if (!Number.isFinite(majorVersion) || majorVersion < 21) {
    fail(
        `Firestore emulator tests require Java 21 or newer; active runtime is: ${output.trim() || "unknown"}`,
    );
}

process.stdout.write(`Java ${majorVersion} is ready for Firestore emulator tests.\n`);

function fail(message) {
    process.stderr.write(`::error title=Unsupported Java runtime::${message}\n`);
    process.exit(1);
}
