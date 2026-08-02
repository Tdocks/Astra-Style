#!/usr/bin/env node
/**
 * Copies brand assets + legal drafts into web/dist and ensures site files exist.
 * Safe to run with no npm deps. Cloudflare may skip this and deploy committed dist/.
 */
import { cpSync, mkdirSync, readFileSync, writeFileSync, existsSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const webRoot = join(__dirname, "..");
const repoRoot = join(webRoot, "..");
const dist = join(webRoot, "dist");
const site = join(webRoot, "site");

function ensureDir(p) {
  mkdirSync(p, { recursive: true });
}

function copyDir(from, to) {
  if (!existsSync(from)) {
    console.warn(`skip missing: ${from}`);
    return;
  }
  ensureDir(to);
  cpSync(from, to, { recursive: true });
}

ensureDir(dist);
copyDir(site, dist);

const assetsOut = join(dist, "assets");
ensureDir(assetsOut);
for (const name of [
  "app-icon-marble.jpg",
  "logo-wordmark-dark.jpg",
  "splash-reference.jpg",
  "ui-reference-daily-brief.jpg",
]) {
  const src = join(repoRoot, "brand", "assets", name);
  if (existsSync(src)) cpSync(src, join(assetsOut, name));
}

const draftBanner = `
<div style="background:#1B1B1B;color:#B9B3A8;font:14px/1.4 -apple-system,BlinkMacSystemFont,sans-serif;padding:12px 20px;border-bottom:1px solid #2A2927;">
  <strong style="color:#D7B46A;">Draft</strong> — not yet in force. Placeholders remain; this is not published legal counsel.
  <a href="/" style="color:#D7B46A;margin-left:12px;">← Astra Style</a>
</div>
`;

const legalMap = [
  ["privacy.html", "privacy"],
  ["terms.html", "terms"],
  ["data-deletion.html", "privacy/delete"],
  ["affiliate-disclosure.html", "affiliate-disclosure"],
];

for (const [file, path] of legalMap) {
  const src = join(repoRoot, "legal", file);
  if (!existsSync(src)) continue;
  const html = readFileSync(src, "utf8");
  const injected = html.includes("<body")
    ? html.replace(/<body([^>]*)>/i, `<body$1>${draftBanner}`)
    : draftBanner + html;
  const outDir = join(dist, path);
  ensureDir(outDir);
  writeFileSync(join(outDir, "index.html"), injected);
}

writeFileSync(
  join(dist, "robots.txt"),
  "User-agent: *\nAllow: /\nSitemap: https://astra-style.com/sitemap.xml\n"
);

writeFileSync(
  join(dist, "sitemap.xml"),
  `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://astra-style.com/</loc></url>
  <url><loc>https://astra-style.com/privacy/</loc></url>
  <url><loc>https://astra-style.com/terms/</loc></url>
  <url><loc>https://astra-style.com/privacy/delete/</loc></url>
  <url><loc>https://astra-style.com/affiliate-disclosure/</loc></url>
</urlset>
`
);

const files = readdirSync(dist);
console.log(`web/dist ready (${files.length} top-level entries)`);
