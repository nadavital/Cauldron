import sharp = require("sharp");
import { createHash } from "node:crypto";

export const RECIPE_IMAGE_WIDTHS = [320, 640, 1280] as const;
export const MAX_IMAGE_BYTES = 10_000_000;
const MAX_CACHE_BYTES = 16_000_000;
const CACHE_TTL_MS = 10 * 60_000;

export function recipeImageWidth(value: unknown): number | null {
    return typeof value === "string" && /^(320|640|1280)$/.test(value) ? Number(value) : null;
}

export function recipeImageRevisionKey(recipeId: string, assetURL: string, width: number): string {
    // Includes the current signed asset revision; never caches authorization.
    return createHash("sha256").update(`${recipeId}\n${assetURL}\n${width}\nwebp-v1`).digest("hex");
}

export class RecipeImageCache {
    private entries = new Map<string, { bytes: Buffer; expires: number }>();
    private size = 0;
    constructor(private maxBytes = MAX_CACHE_BYTES, private ttl = CACHE_TTL_MS) {}
    get(key: string, now = Date.now()): Buffer | undefined {
        const entry = this.entries.get(key);
        if (!entry) return undefined;
        this.entries.delete(key);
        this.size -= entry.bytes.length;
        if (entry.expires <= now) return undefined;
        this.entries.set(key, entry);
        this.size += entry.bytes.length;
        return entry.bytes;
    }
    set(key: string, bytes: Buffer, now = Date.now()): void {
        const old = this.entries.get(key);
        if (old) { this.size -= old.bytes.length; this.entries.delete(key); }
        if (bytes.length > this.maxBytes) return;
        for (const [id, entry] of this.entries) {
            if (entry.expires <= now || this.size + bytes.length > this.maxBytes || this.entries.size >= 128) {
                this.entries.delete(id);
                this.size -= entry.bytes.length;
            }
        }
        this.entries.set(key, { bytes, expires: now + this.ttl });
        this.size += bytes.length;
    }
}

export async function readBoundedImage(response: Response, limit = MAX_IMAGE_BYTES): Promise<Buffer> {
    const declared = Number(response.headers.get("content-length") ?? "0");
    if (!response.ok || declared > limit || !response.body) {
        await response.body?.cancel();
        throw new Error("Image response unavailable or too large");
    }
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let size = 0;
    try {
        while (true) {
            const { value, done } = await reader.read();
            if (done) break;
            size += value.byteLength;
            if (size > limit) throw new Error("Image response exceeded byte limit");
            chunks.push(value);
        }
    } finally {
        await reader.cancel();
        reader.releaseLock();
    }
    return Buffer.concat(chunks, size);
}

export async function resizeRecipeImage(input: Buffer, width: number): Promise<Buffer> {
    if (!RECIPE_IMAGE_WIDTHS.some((allowed) => allowed === width) || input.length > MAX_IMAGE_BYTES) {
        throw new Error("Unsupported image variant");
    }
    return sharp(input, { limitInputPixels: 16_000_000, animated: false, failOn: "warning" })
        .rotate().resize({ width, withoutEnlargement: true })
        .webp({ quality: 78, effort: 3 }).timeout({ seconds: 3 }).toBuffer();
}
