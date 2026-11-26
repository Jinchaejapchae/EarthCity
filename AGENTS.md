# EarthCity — Agent Team Rules

> Keep this top rules block stable so implicit prompt caching applies across runs.
> Read `CLAUDE.md` for full Godot 4.7.2 & Web Three.js architecture history, debug flags, and known physics pitfalls.

## Never (Hard Rules)
- Never edit `dist/index.html` directly (always regenerate via `npm run build`).
- Never modify or re-import `godot/assets/people/**` (Git LFS binaries) or `godot/export_presets.cfg` without explicit user approval.
- Never install packages, push, publish releases, delete files, or spend money without explicit user approval.
- Never ask for API keys or secrets in chat; never send `thinking_budget`.
- Never regress core physics/world invariants documented in `CLAUDE.md:104-108` (road collision normal filter `|n.y| >= 0.85`, car wall slowdown only `n.y < 0.6`, capsule car collider, `water_level_at` swimming/slowdown, non-blocking tile streaming).
- Never pretend a build, smoke test, or Godot run succeeded; paste the last 20 lines of actual output and 1-based `path:line` citations.

## Project
- **Godot Runtime (`godot/`)**: Godot 4.7.2 Forward+ GDScript open-world with live z14 MVT + Terrarium DEM + Sentinel-2 satellite streaming (`world.gd`, `chunk_builder.gd`, `main.gd`, `traffic.gd`, `signals.gd`, `atmos.gd`, `sfx.gd`, `landmarks.gd`, `style.gd`).
- **Web Runtime (`src/`)**: Three.js single-HTML bundle (`src/main.js`, `src/carModels.js`, `src/index.html`, `build.mjs` → `dist/index.html`) with Puppeteer smoke suite (`tests/smoke.mjs`).
- **Riskiest Files**: `godot/scripts/chunk_builder.gd`, `godot/scripts/world.gd`, `godot/scripts/main.gd`, `src/main.js`.

## Commands
- **Web build**: `npm run build` (`node build.mjs` → builds `dist/index.html`)
- **Web smoke test**: `npm test` (`node build.mjs && node tests/smoke.mjs`; mobile: `node tests/smoke.mjs m`; set `CHROME_PATH` if needed)
- **Godot syntax/boot check**: `godot --headless --path godot --quit`
- **Godot targeted verification** (as relevant to change):
  - `--shot=out.png --ll=lat,lon --cam=x,y,z,tx,ty,tz --frame=N`
  - `--npcdbg`, `--speeddbg --walk`, `--sigdbg`, `--swimtest`

## Ownership
- `@coordinator` (`gemini-4-neon`, thinking `high`; `xhigh` only for 1 deep bug): Sole user interface; plans, assigns ownership, reviews verifier output, prepares PRs.
- `@earthcity-godot` (`gemini-4-hydrogen`): Owns `godot/scripts/**`, `godot/main.tscn`, `godot/project.godot`. Must not touch `src/**`, `tests/**`, `tools/**`, `build.mjs`, `dist/**`, `godot/assets/people/**`, `godot/export_presets.cfg`.
- `@earthcity-web` (`gemini-4-hydrogen`): Owns `src/main.js`, `src/index.html`, `tests/**`, `tools/**`, `build.mjs`. Must not touch `godot/**`, `src/carModels.js` (generated via `tools/convert-cars.mjs`), `dist/index.html` (generated via `npm run build`).
- `@verifier` (**must run on a different model than workers**, read-only): Owns no files; never edits. Reports to `@coordinator`.

## Done Means
1. Every worker touched only files inside its `OWNS` paths.
2. Web changes pass `npm run build` and `npm test` (if Chrome is unavailable in sandbox, report explicitly — never pretend it ran).
3. Godot changes pass `godot --headless --path godot --quit` with zero script errors plus relevant debug-flag verification (if Godot binary is unavailable in cloud CI, report explicitly).
4. `@verifier` verified all cited files/lines, re-ran commands, pasted the last 20 lines, and approved within at most 2 reject rounds.
5. Changes land on a feature/fix branch and open a PR (never direct push to `main`).
