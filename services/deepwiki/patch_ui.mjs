// Build-time patch for DeepWiki's slides and workshop pages (run from the source root).
//
// These client pages open their chat WebSocket at
//   process.env.SERVER_BASE_URL || 'http://localhost:8001'
// In the browser SERVER_BASE_URL is undefined, so they connect to the *visitor's own*
// localhost:8001 (which may trigger the browser's local-network permission prompt)
// before falling back to HTTP. This deployment serves /ws/* on the page's own origin,
// so point them there. The script refuses to run if upstream changed these lines.
import { readFileSync, writeFileSync } from "node:fs";

const OLD = "const serverBaseUrl = process.env.SERVER_BASE_URL || 'http://localhost:8001';";
const NEW = "const serverBaseUrl = window.location.origin; // [railway-template] same-origin /ws";
const EXPECTED = {
  "src/app/[owner]/[repo]/slides/page.tsx": 2,
  "src/app/[owner]/[repo]/workshop/page.tsx": 1,
};

let failed = false;
for (const [file, expected] of Object.entries(EXPECTED)) {
  const source = readFileSync(file, "utf8");
  if (source.includes("[railway-template] same-origin /ws")) {
    console.log(`${file}: already patched`);
    continue;
  }
  const found = source.split(OLD).length - 1;
  if (found !== expected) {
    console.error(`${file}: expected ${expected} WebSocket base line(s), found ${found}; upstream changed`);
    failed = true;
    continue;
  }
  writeFileSync(file, source.split(OLD).join(NEW));
  console.log(`${file}: ${found} WebSocket base line(s) now use the page origin`);
}
process.exit(failed ? 1 : 0);
