// This reports audit metadata; production image authorization is separate.
export function hasSameOriginImages(images, expectedOrigin) {
    if (!Array.isArray(images) || images.length === 0) return false;
    return images.every(value => {
        if (typeof value !== "string") return false;
        try {
            const url = new URL(value);
            return url.origin === expectedOrigin && !url.username && !url.password;
        } catch {
            return false;
        }
    });
}
