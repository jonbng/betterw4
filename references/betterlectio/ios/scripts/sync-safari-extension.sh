#!/usr/bin/env bash
#
# sync-safari-extension.sh — build the WXT extension and vendor the Manifest V3
# output into this repo for the Safari Web Extension appex.
#
# Run this on a Mac, online, before committing. Xcode NEVER runs it: the contents
# of SafariExtension/Resources/ are committed build *inputs*, which keeps Xcode
# builds hermetic (no bun, no secrets, no network).
#
# Usage:
#   ./scripts/sync-safari-extension.sh                 build from source and sync
#   ./scripts/sync-safari-extension.sh --dry-run       show what would change
#   EXTENSION_DIR=/path/to/extension ./scripts/sync-safari-extension.sh
#
# Requires a gitignored .env.safari at the repo root:
#   VITE_SUPABASE_URL=https://<project-ref>.supabase.co
#   VITE_SUPABASE_PUBLISHABLE_KEY=...
#   VITE_POSTHOG_KEY=...
#   VITE_POSTHOG_HOST=https://eu.i.posthog.com
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"

EXTENSION_DIR="${EXTENSION_DIR:-$(cd -- "${REPO_ROOT}/../extension" 2>/dev/null && pwd -P || true)}"
# Deliberately OUTSIDE SafariExtension/: that folder is a synchronized root group,
# and Xcode would bundle a flattened duplicate of every nested file alongside the
# correctly-structured copy made by the appex's "Copy WXT Web Resources" phase.
RESOURCES_DIR="${REPO_ROOT}/SafariExtensionResources"
# Bundled into the Mac app (BetterLectioMac/ is that target's synchronized group)
# so ExtensionBuildInfo.bundled can report the shipped web-extension version.
PROVENANCE_FILE="${REPO_ROOT}/BetterLectioMac/EXTENSION_BUILD_INFO.json"
ENV_FILE="${REPO_ROOT}/.env.safari"
BUILD_OUT="safari-mv3"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

red() { printf '\033[31m%s\033[0m\n' "$*" >&2; }
grn() { printf '\033[32m%s\033[0m\n' "$*"; }
ylw() { printf '\033[33m%s\033[0m\n' "$*"; }
die() { red "ERROR: $*"; exit 1; }

# ── 1. Preconditions ────────────────────────────────────────────────────────

[[ -n "${EXTENSION_DIR}" && -d "${EXTENSION_DIR}" ]] \
  || die "Extension repo not found.
  Expected a sibling checkout at ${REPO_ROOT}/../extension
  Clone it:  git clone https://github.com/jonbng/betterlectio.git extension
  Or set:    EXTENSION_DIR=/path/to/betterlectio ./scripts/sync-safari-extension.sh"

[[ -f "${EXTENSION_DIR}/wxt.config.ts" ]] \
  || die "${EXTENSION_DIR} does not look like the WXT extension repo (no wxt.config.ts)."

command -v bun >/dev/null 2>&1 \
  || die "bun is not installed. Install it:  curl -fsSL https://bun.sh/install | bash
  (the extension repo pins packageManager bun@1.3.14)"
command -v rsync >/dev/null 2>&1 || die "rsync not found."
command -v python3 >/dev/null 2>&1 || die "python3 not found (needed to validate manifest.json)."

# ── 2. Build environment ────────────────────────────────────────────────────

REQUIRED_VARS=(VITE_SUPABASE_URL VITE_SUPABASE_PUBLISHABLE_KEY VITE_POSTHOG_KEY VITE_POSTHOG_HOST)

if [[ -f "${ENV_FILE}" ]]; then
  ylw "Loading build env from ${ENV_FILE}"
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

MISSING=()
for v in "${REQUIRED_VARS[@]}"; do
  [[ -n "${!v:-}" ]] || MISSING+=("$v")
done
if (( ${#MISSING[@]} )); then
  die "Missing required build env vars: ${MISSING[*]}

  Vite inlines these into the bundle at build time. Without VITE_SUPABASE_URL in
  particular, wxt.config.ts falls back to the host_permissions wildcard
  'https://*.supabase.co/*' AND the runtime Supabase URL is undefined — a silently
  broken, over-permissioned build that App Review is likely to reject.

  Create ${ENV_FILE} (gitignored) with:
    VITE_SUPABASE_URL=https://<project-ref>.supabase.co
    VITE_SUPABASE_PUBLISHABLE_KEY=...
    VITE_POSTHOG_KEY=...
    VITE_POSTHOG_HOST=https://eu.i.posthog.com"
fi

case "${VITE_SUPABASE_URL}" in
  *'*'*)     die "VITE_SUPABASE_URL contains a wildcard ('${VITE_SUPABASE_URL}'). Use the concrete project URL." ;;
  https://*) : ;;
  *)         die "VITE_SUPABASE_URL must be an https:// URL, got '${VITE_SUPABASE_URL}'." ;;
esac

# ── 3. Provenance ───────────────────────────────────────────────────────────

pushd "${EXTENSION_DIR}" >/dev/null

SRC_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
SRC_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
SRC_REMOTE="$(git remote get-url origin 2>/dev/null || echo unknown)"
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  SRC_DIRTY=true
  ylw "WARNING: ${EXTENSION_DIR} has uncommitted changes."
  ylw "         The synced output will not be reproducible from ${SRC_SHA}."
else
  SRC_DIRTY=false
fi

# ── 4. Build ────────────────────────────────────────────────────────────────

grn "==> Installing dependencies (${EXTENSION_DIR})"
bun install --frozen-lockfile

grn "==> Building Safari MV3 extension"
rm -rf ".output/${BUILD_OUT}"
if ! bun run build:safari; then
  popd >/dev/null
  die "'bun run build:safari' failed. Nothing was synced; ${RESOURCES_DIR} is untouched."
fi

BUILD_DIR="${EXTENSION_DIR}/.output/${BUILD_OUT}"
EXT_VERSION="$(node -p "require('${EXTENSION_DIR}/package.json').version")"

popd >/dev/null

# ── 5. Validate ─────────────────────────────────────────────────────────────

grn "==> Validating build output"

[[ -d "${BUILD_DIR}" ]] || die "Expected output dir ${BUILD_DIR} does not exist.
  WXT names it \${browser}-mv\${manifestVersion}. If this is missing, --mv3 is
  probably absent from package.json's build:safari script (it would have emitted
  .output/safari-mv2 instead)."

[[ -f "${BUILD_DIR}/manifest.json" ]] || die "No manifest.json in ${BUILD_DIR}."

python3 - "${BUILD_DIR}/manifest.json" "${BUILD_DIR}" <<'PY'
import json, sys, os, fnmatch

manifest_path, build_dir = sys.argv[1], sys.argv[2]
with open(manifest_path) as f:
    m = json.load(f)

errors, warnings = [], []

if m.get("manifest_version") != 3:
    errors.append(f"manifest_version is {m.get('manifest_version')!r}, expected 3. "
                  "Is --mv3 present in package.json build:safari?")

if m.get("name") != "BetterLectio":
    errors.append(f"name is {m.get('name')!r}, expected 'BetterLectio' "
                  "(set by the safari branch of build:manifestGenerated).")

bg = m.get("background") or {}
if not bg.get("scripts"):
    errors.append(
        "background.scripts is missing. Safari does NOT apply the host_permissions "
        "CORS bypass to a background service worker — only to a background page or "
        "event page. Without background.scripts every Supabase and PostHog request "
        "from the background will fail CORS on Safari.")
if "persistent" in bg:
    warnings.append("background.persistent is present; it is an MV2-only key and should "
                    "be removed from the safari branch in wxt.config.ts.")

for hp in m.get("host_permissions", []):
    host = hp.split("://", 1)[-1].split("/", 1)[0]
    if "*" in host:
        errors.append(
            f"host_permissions contains a wildcard host: {hp!r}. This is the "
            "VITE_SUPABASE_URL fallback in wxt.config.ts firing. Shipping it requests "
            "access to every Supabase project on the internet and is a likely App "
            "Review rejection. Build with VITE_SUPABASE_URL set.")

files = set()
for root, _dirs, names in os.walk(build_dir):
    for n in names:
        files.add(os.path.relpath(os.path.join(root, n), build_dir))

for entry in m.get("web_accessible_resources", []):
    if isinstance(entry, str):
        errors.append(f"MV2-style string web_accessible_resource: {entry!r}")
        continue
    for pat in entry.get("resources", []):
        norm = pat.replace("**", "*")
        if not any(fnmatch.fnmatch(f, norm) for f in files):
            errors.append(
                f"web_accessible_resources pattern {pat!r} matches no file in the build "
                "output — the extension declares a resource it does not ship, so anything "
                "loading it at runtime will 404.")

for icon in (m.get("icons") or {}).values():
    if icon not in files:
        errors.append(f"icon {icon!r} declared but not present in output.")

for w in warnings:
    print(f"  WARN:  {w}")
for e in errors:
    print(f"  FAIL:  {e}")
if errors:
    sys.exit(1)

print(f"  manifest.json OK (mv{m['manifest_version']}, v{m.get('version')}, "
      f"background: {'scripts+service_worker' if bg.get('service_worker') else 'scripts'})")
PY

[[ -f "${BUILD_DIR}/background.js" ]]   || die "background.js missing from build output."
[[ -d "${BUILD_DIR}/content-scripts" ]] || die "content-scripts/ missing from build output."

# ── 6. Sync ─────────────────────────────────────────────────────────────────

# Guardrail: never --delete outside this repo.
case "${RESOURCES_DIR}" in
  "${REPO_ROOT}"/*) : ;;
  *) die "Refusing to rsync --delete into ${RESOURCES_DIR}: outside ${REPO_ROOT}." ;;
esac

mkdir -p "${RESOURCES_DIR}"

RSYNC_FLAGS=(-a --delete --checksum
             --exclude '.DS_Store'
             --exclude '*.map'          # keep sourcemaps out of the App Store build
             --itemize-changes)
(( DRY_RUN )) && RSYNC_FLAGS+=(--dry-run)

grn "==> Syncing ${BUILD_DIR}/ -> ${RESOURCES_DIR}/"
rsync "${RSYNC_FLAGS[@]}" "${BUILD_DIR}/" "${RESOURCES_DIR}/"

if (( DRY_RUN )); then
  ylw "Dry run — no files were written and no provenance was recorded."
  exit 0
fi

# ── 7. Provenance ───────────────────────────────────────────────────────────

BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BUILT_BY="$(git -C "${REPO_ROOT}" config user.email 2>/dev/null || whoami)"

python3 - "${PROVENANCE_FILE}" <<PY
import json, sys
data = {
  "_comment": "Generated by scripts/sync-safari-extension.sh. Do not edit by hand. "
              "Describes the contents of SafariExtensionResources/.",
  "extension_version": "${EXT_VERSION}",
  "source_repo": "${SRC_REMOTE}",
  "source_branch": "${SRC_BRANCH}",
  "source_commit": "${SRC_SHA}",
  "source_dirty": "${SRC_DIRTY}" == "true",
  "manifest_version": 3,
  "target_browser": "safari",
  "built_at": "${BUILT_AT}",
  "built_by": "${BUILT_BY}",
  "supabase_url": "${VITE_SUPABASE_URL}",
  "posthog_host": "${VITE_POSTHOG_HOST}",
}
with open(sys.argv[1], "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

grn "==> Done."
echo
echo "  extension version : ${EXT_VERSION}"
echo "  source commit     : ${SRC_SHA}$( [[ "${SRC_DIRTY}" == true ]] && echo ' (DIRTY)')"
echo "  provenance        : ${PROVENANCE_FILE#"${REPO_ROOT}"/}"
echo
echo "Next:"
echo "  git -C '${REPO_ROOT}' add SafariExtensionResources BetterLectioMac/EXTENSION_BUILD_INFO.json"
echo "  git -C '${REPO_ROOT}' commit -m 'chore(safari): sync extension v${EXT_VERSION} (${SRC_SHA:0:8})'"
