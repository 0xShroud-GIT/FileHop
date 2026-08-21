#!/usr/bin/env bash
# Deterministic FileHop source export retained for the existing repository
# contract tests. Generated artifact manifests are ignored by Git.
# Usage: scripts/export_review_bundle.sh <mission-NN> <output.zip>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MISSION="${1:-}"
OUT="${2:-}"

if [[ ! "$MISSION" =~ ^[0-9]{2}$ || -z "$OUT" ]]; then
  printf 'Usage: %s <mission-NN> <output.zip>\n' "$0" >&2
  exit 2
fi

MANIFEST_REL="artifacts/evidence/mission-${MISSION}/export-manifest.txt"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
DEST="$STAGING/FileHop"
mkdir -p "$DEST"

should_skip() {
  local rel="$1"
  local base
  base="$(basename "$rel")"
  case "$rel" in
    .git/*|.git|.dart_tool/*|.dart_tool|.idea/*|.idea|.vscode/*|.vscode) return 0 ;;
    build/*|build|*/build/*|*/build|android/.gradle/*|android/.gradle) return 0 ;;
    android/local.properties|android/key.properties) return 0 ;;
    ios/Pods/*|ios/Pods|ios/.symlinks/*|ios/.symlinks|ios/Flutter/ephemeral/*|ios/Flutter/ephemeral) return 0 ;;
    artifacts/*|artifacts) return 0 ;;
    *.zip|*.zip.sha256|*.db|*.sqlite|*.sqlite3|*.tmp|*.temp|*.swp|*.log) return 0 ;;
  esac
  case "$base" in
    Generated.xcconfig|flutter_export_environment.sh|.DS_Store|*.iml) return 0 ;;
  esac
  return 1
}

(
  cd "$ROOT"
  find . -type f -print0 | while IFS= read -r -d '' file; do
    rel="${file#./}"
    if should_skip "$rel"; then
      continue
    fi
    mkdir -p "$DEST/$(dirname "$rel")"
    cp -a "$ROOT/$rel" "$DEST/$rel"
  done
)

mkdir -p "$DEST/$(dirname "$MANIFEST_REL")"
touch "$DEST/$MANIFEST_REL"
mapfile -t LIST < <(cd "$STAGING" && find FileHop -type f | LC_ALL=C sort)
count="${#LIST[@]}"

{
  echo "exportRulesVersion: 5"
  echo "mission: $MISSION"
  echo "exportZipName: $(basename "$OUT")"
  echo "includedFileCount: $count"
  echo "note: deterministic source export for repository contract validation"
  echo
  echo "files:"
  printf '%s\n' "${LIST[@]}"
} > "$DEST/$MANIFEST_REL"

mkdir -p "$ROOT/$(dirname "$MANIFEST_REL")"
cp -a "$DEST/$MANIFEST_REL" "$ROOT/$MANIFEST_REL"

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
(
  cd "$STAGING"
  find FileHop -type f | LC_ALL=C sort | zip -X -q "$OUT" -@
)

actual="$(unzip -Z1 "$OUT" | wc -l | tr -d ' ')"
if [[ "$actual" != "$count" ]]; then
  printf 'internal count %s != archive count %s\n' "$count" "$actual" >&2
  exit 1
fi

if ! diff <(unzip -Z1 "$OUT" | LC_ALL=C sort) \
          <(sed -n '/^files:$/,$p' "$DEST/$MANIFEST_REL" | tail -n +2 | LC_ALL=C sort) >/dev/null; then
  printf 'export self-check failed: ZIP listing != manifest listing\n' >&2
  exit 1
fi

sha256sum "$OUT" | awk -v name="$(basename "$OUT")" '{print $1 "  " name}' > "${OUT}.sha256"
printf '%s\n' "$OUT"
