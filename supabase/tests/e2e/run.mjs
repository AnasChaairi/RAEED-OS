// Runs the end-to-end tests against the local Supabase started with `supabase start`.
// Reads its URL and keys from `supabase status`, so nothing is configured by hand.
import { execSync, spawnSync } from "node:child_process";
import { readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..", "..", "..");

let status;
try {
  status = JSON.parse(execSync("npx --yes supabase@2 status -o json", { cwd: repo, stdio: ["ignore", "pipe", "ignore"] }).toString());
} catch {
  console.error("The local Supabase is not running. Start it from the repository root with:\n  npx supabase start");
  process.exit(1);
}

// `npm test` runs every *.test.mjs; `npm test -- 02_setup.test.mjs` runs the ones named.
const named = process.argv.slice(2);
const files = (named.length ? named : readdirSync(here).filter((f) => f.endsWith(".test.mjs")).sort()).map((f) => join(here, f));
const result = spawnSync(process.execPath, ["--test", "--test-concurrency=1", ...files], {
  stdio: "inherit",
  env: {
    ...process.env,
    SUPABASE_URL: status.API_URL,
    SUPABASE_ANON_KEY: status.ANON_KEY,
    SUPABASE_SERVICE_ROLE_KEY: status.SERVICE_ROLE_KEY,
  },
});
process.exit(result.status ?? 1);
