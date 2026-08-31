import test from "node:test";
import { hasSameOriginImages } from "../tools/publicImageAudit.mjs";

test("SEO image audit requires nonempty, well-formed exact-origin URLs", () => {
    const origin = "https://cauldronrecipes.com";
    assert.equal(hasSameOriginImages([`${origin}/recipe/id/social-card.png`], origin), true);
    assert.equal(hasSameOriginImages(["https://CAULDRONRECIPES.com:443/recipe/id/image/640.webp"], origin), true);
    for (const images of [undefined, null, [], "not an array", [null], [42], [{}],
        ["/recipe/id/image/640.webp"], ["not a URL"],
        ["blob:https://cauldronrecipes.com/recipe-image"],
        ["data:image/png;base64,AAAA"],
        ["javascript:alert(1)"],
        ["http://cauldronrecipes.com/image.png"],
        ["https://cauldronrecipes.com.attacker.example/image.png"],
        ["https://cauldronrecipes.com@attacker.example/image.png"],
        ["https://attacker.example/?https://cauldronrecipes.com"],
        ["https://cauldronrecipes.com:444/image.png"],
        ["https://user:password@cauldronrecipes.com/image.png"],
        [`${origin}/image.png`, "https://attacker.example/image.png"]]) {
        assert.equal(hasSameOriginImages(images, origin), false);
    }
});
import assert from "node:assert/strict";
import sharp from "sharp";
import { RecipeImageCache, recipeImageWidth, recipeImageRevisionKey, readBoundedImage, resizeRecipeImage } from "../lib/recipeImages.js";
import { sitemapRecipePages, sitemapPageNumber, generateCatalogSitemapIndex, catalogManifestCandidates, SITEMAP_MAX_AGE_MS } from "../lib/catalogSitemap.js";
import { browsableRecipes, publicPageCursor, pageNavigation, recipeListStructuredData, responsiveRecipeImageAttributes, assertCompleteRecipeShelfLookup, publicReadRateLimitPolicy, loadRecipeQueryPage, sanitizeCloudKitCollectionForWeb } from "../lib/index.js";
import { validateSitemapIndex, homepageRecipeCards } from "../tools/monitorHostedSharing.mjs";

const id = "7DBEAFFD-895F-43B1-9985-463F36EA5D8C";
const owner = "87BB336E-D474-4664-B06E-EC8E516B1748";
test("catalog manifest is candidate-only, expires, and resumes after deleted boundary IDs", () => {
    const ids=["00000000-0000-4000-8000-000000000001","00000000-0000-4000-8000-000000000003"];
    assert.deepEqual(catalogManifestCandidates(ids,1000,"00000000-0000-4000-8000-000000000002",1001),[ids[1]]);
    assert.equal(catalogManifestCandidates(ids,1000,null,1001+SITEMAP_MAX_AGE_MS),null);
    assert.equal(catalogManifestCandidates(ids,2000,null,1001),null);
    assert.equal(catalogManifestCandidates(undefined,1000,null,1001),null);
    assert.deepEqual(catalogManifestCandidates([],1000,null,1001),[]);
});
test("legacy duplicate collection memberships cannot repeat a cursor indefinitely", () => {
    const ids=Array.from({length:49},(_,i)=>`00000000-0000-4000-8000-${String(i).padStart(12,"0")}`);
    ids[47]=ids[23];
    const collection=sanitizeCloudKitCollectionForWeb({recordType:"Collection",recordName:id,created:{userRecordName:"creator"},fields:{
        collectionId:{value:id},userId:{value:owner},visibility:{value:"public"},name:{value:"Favorites"},recipeIds:{value:JSON.stringify(ids)},
    }},id,owner,"creator");
    assert.equal(collection.recipeIds.length,48);
    const firstCursor=collection.recipeIds[23];
    const next=collection.recipeIds.slice(collection.recipeIds.indexOf(firstCursor)+1);
    assert.equal(next.length,24);assert.equal(next.at(-1),ids[48]);assert.ok(!next.includes(firstCursor));
});
test("browse pagination never drops a boundary recipe and stops after four empty candidate pages", async () => {
    const ids = Array.from({length:120}, (_, i)=>`00000000-0000-4000-8000-${String(i).padStart(12,"0")}`);
    let calls=0;
    const makeQuery = (cursor=null, limit=25) => ({
        orderBy(){return this;}, limit(n){return makeQuery(cursor,n);}, startAfter(id){return makeQuery(id,limit);},
        async get(){calls++; const docs=ids.filter(id=>!cursor || id>cursor).slice(0,limit).map(id=>({id}));return {docs,size:docs.length};},
    });
    const validate = async docs=>({items:docs.map(d=>({recipeId:d.id})),permanentlyInvalidRecipeIds:[]});
    const first=await loadRecipeQueryPage(makeQuery(),null,[],validate);
    const second=await loadRecipeQueryPage(makeQuery(),first.nextCursor,[],validate);
    assert.equal(first.items.length,24);assert.equal(first.nextCursor,ids[23]);assert.equal(second.items[0].recipeId,ids[24]);
    const sparse=await loadRecipeQueryPage(makeQuery(),null,[],async docs=>({items:docs.filter(d=>ids.indexOf(d.id)%3===0).map(d=>({recipeId:d.id})),permanentlyInvalidRecipeIds:[]}));
    assert.ok(sparse.items.length>8); assert.equal(new Set(sparse.items.map(i=>i.recipeId)).size,sparse.items.length);
    const next=await loadRecipeQueryPage(makeQuery(),sparse.nextCursor,[],validate);
    assert.ok(next.items.every(item=>!sparse.items.some(seen=>seen.recipeId===item.recipeId)));
    calls=0;
    const empty=await loadRecipeQueryPage(makeQuery(),null,[],async()=>({items:[],permanentlyInvalidRecipeIds:[]}));
    assert.equal(calls,4);assert.equal(empty.nextCursor,ids[95]);
    await assert.rejects(loadRecipeQueryPage(makeQuery(),null,[],async()=>{throw Error("CloudKit timeout")}), /timeout/);
});
test("five fully viewed catalog pages do not consume the navigation rate budget", () => {
    const page = publicReadRateLimitPolicy("page"), image = publicReadRateLimitPolicy("image");
    assert.notEqual(page.prefix, image.prefix);
    assert.ok(5 < page.limit); assert.ok(5 * 24 < image.limit);
    assert.ok(image.limit < 1000);
});
test("strict sitemap and cursor validation distinguishes unavailable records from confirmed deletions", () => {
    assert.doesNotThrow(()=>assertCompleteRecipeShelfLookup([id], [{recordName:id}]));
    assert.doesNotThrow(()=>assertCompleteRecipeShelfLookup([id], [{recordName:id,serverErrorCode:"UNKNOWN_ITEM"}]));
    assert.throws(()=>assertCompleteRecipeShelfLookup([id], []), /Incomplete/);
    assert.throws(()=>assertCompleteRecipeShelfLookup([id], [{recordName:id,serverErrorCode:"SERVICE_UNAVAILABLE"}]), /Incomplete/);
});
test("thumbnail widths and responsive markup are bounded and cannot accept arbitrary origins", () => {
    for (const w of ["320", "640", "1280"]) assert.equal(recipeImageWidth(w), Number(w));
    for (const w of ["10000", "0320", "320px", 320, undefined, ["320"], "https://example.com"]) assert.equal(recipeImageWidth(w), null);
    assert.equal(responsiveRecipeImageAttributes("<script>"), "");
    assert.match(responsiveRecipeImageAttributes(id), /sizes=/);
    assert.match(responsiveRecipeImageAttributes(id,false,true), /704px/);
    assert.notEqual(recipeImageRevisionKey(id, "asset-v1", 320), recipeImageRevisionKey(id, "asset-v2", 320));
    assert.notEqual(recipeImageRevisionKey(id, "asset-v1", 320), recipeImageRevisionKey(id, "asset-v1", 640));
});
test("thumbnail byte cache expires and evicts by bytes with no stale fallback", () => {
    const cache = new RecipeImageCache(6, 10);
    cache.set("a", Buffer.from("aaa"), 0); cache.set("b", Buffer.from("bbb"), 0);
    assert.equal(cache.get("a", 1).toString(), "aaa");
    cache.set("c", Buffer.from("ccc"), 1);
    assert.equal(cache.get("b", 2), undefined);
    assert.equal(cache.get("a", 10), undefined);
    cache.set("c", Buffer.from("too-large"), 2);
    assert.equal(cache.get("c", 3), undefined);
});
test("image reader enforces streamed and declared byte limits and cancels streams", async () => {
    assert.equal((await readBoundedImage(new Response("abc"), 3)).toString(), "abc");
    await assert.rejects(readBoundedImage(new Response("abcd"), 3), /byte limit/);
    await assert.rejects(readBoundedImage(new Response("abc", { headers: { "content-length": "999" } }), 3), /too large/);
    await assert.rejects(readBoundedImage(new Response("bad", {status:404})), /unavailable/);
});
test("thumbnail encoder produces bounded WebP without enlargement and strips metadata", async () => {
    const original = await sharp({ create: { width: 1000, height: 750, channels: 3, background: "#e6801a" } }).jpeg().toBuffer();
    const result = await resizeRecipeImage(original, 320);
    const metadata = await sharp(result).metadata();
    assert.equal(metadata.format, "webp"); assert.equal(metadata.width, 320); assert.equal(metadata.height, 240);
    assert.equal(metadata.exif, undefined); assert.ok(result.length < original.length);
    assert.equal((await sharp(await resizeRecipeImage(result, 1280)).metadata()).width, 320);
    await assert.rejects(resizeRecipeImage(original, 10000), /Unsupported/);
    await assert.rejects(resizeRecipeImage(Buffer.from("not image"), 320));
});
test("sitemap manifest is deduplicated, bounded and paginated, never silently truncated", () => {
    const ids = Array.from({length:49}, (_, i) => `00000000-0000-4000-8000-${String(i).padStart(12,"0")}`);
    assert.deepEqual(sitemapRecipePages([...ids, ids[0], "invalid"]).map(p=>p.length), [24,24,1]);
    assert.deepEqual(sitemapRecipePages([]), [[]]);
    assert.equal(sitemapPageNumber("/sitemaps/recipes-12.xml"), 12);
    assert.equal(sitemapPageNumber("/sitemaps/recipes-01.xml"), null);
    assert.equal(sitemapPageNumber("/sitemaps/recipes-9999.xml"), null);
    assert.throws(() => sitemapRecipePages(Array.from({length:10001}, (_, i) => `00000000-0000-4000-8000-${String(i).padStart(12,"0")}`)), /capacity/);
    const xml = generateCatalogSitemapIndex(3, "https://cauldronrecipes.com");
    assert.equal(validateSitemapIndex(xml, "https://cauldronrecipes.com").length, 3);
    assert.throws(()=>validateSitemapIndex(xml.replace("recipes-0.xml", "../evil"), "https://cauldronrecipes.com"));
});
test("cursor URLs and JSON-LD escape content and keep only valid recipe identities", () => {
    assert.equal(publicPageCursor(undefined), null); assert.equal(publicPageCursor(id), id);
    for(const bad of ["", [], "../", "x?after=y"]) assert.throws(()=>publicPageCursor(bad));
    assert.equal(pageNavigation("//evil.com", "javascript:alert(1)"), "");
    assert.match(pageNavigation(`/recipes?after=${id}`, "/recipes"), /rel="next"/);
    const json = recipeListStructuredData([{recipeId:id,title:"</script>cake"},{recipeId:"evil",title:"evil"}], "https://cauldronrecipes.com/recipes");
    assert.ok(!json.includes("</script>")); assert.equal(JSON.parse(json).itemListElement.length, 1);
});
test("visibility checks batch deduplicated owner guards and fail closed on missing or revoked responses", async () => {
    const docs = [{exists:true,id,data:()=>({recipeId:id,ownerId:owner,title:"Cake",tags:[]})}];
    let calls=0;
    const guards = (blocked=false,revoked=false,missing=false) => async refs => {
        calls++; assert.equal(refs.length,2);
        return refs.filter(ref=>!missing || !ref.path.startsWith("share_revocations/")).map(ref=>({ref,exists:revoked,data:()=>ref.path.startsWith("share_revocations/") ? {} : {blocked}}));
    };
    assert.equal((await browsableRecipes(docs,null,guards())).length,1); assert.equal(calls,1);
    assert.equal((await browsableRecipes(docs,null,guards(true))).length,0);
    assert.equal((await browsableRecipes(docs,null,guards(false,true))).length,0);
    assert.equal((await browsableRecipes(docs,null,guards(false,false,true))).length,0);
    assert.equal((await browsableRecipes(docs,"00000000-0000-4000-8000-000000000000",()=>{throw Error("must not read")})).length,0);
});
test("homepage monitor accepts only the exact same-recipe thumbnail, not an arbitrary image proxy", () => {
    const card = src=>`<li class="discovery-card"><a href="/recipe/${id}"><img src="${src}"></a></li>`;
    assert.equal(homepageRecipeCards(card(`/recipe/${id}/image/640.webp`)).length,1);
    assert.throws(()=>homepageRecipeCards(card(`/recipe/00000000-0000-4000-8000-000000000000/image/640.webp`)));
    assert.throws(()=>homepageRecipeCards(card(`/recipe/${id}/image/640.webp?url=https://example.com`)));
});
