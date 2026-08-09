#!/usr/bin/env bash
# Enforce Novolis OS package allowlists and budgets (single profile).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOLVED="${1:-}"
MANIFEST_DIR="$REPO_ROOT/manifests"
MAX_EXPLICIT=80
MAX_RESOLVED=280

read_list() {
  local f="$1"
  [[ -f "$f" ]] || { echo "Missing package list: $f" >&2; exit 1; }
  sed -e 's/\r$//' -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$f" | sed '/^$/d'
}

matches_exclude() {
  local name="$1"
  local pat
  while IFS= read -r pat; do
    # shellcheck disable=SC2254
    case "$name" in
      $pat) return 0 ;;
    esac
  done < <(read_list "$MANIFEST_DIR/excludes.txt")
  return 1
}

mapfile -t ALL_PKGS < <(
  for f in base.txt dotnet.txt ui-graphics.txt audio-alsa.txt appliance.txt; do
    read_list "$MANIFEST_DIR/$f"
  done | sort -u
)

ALL_COUNT="${#ALL_PKGS[@]}"
FAIL=0

echo "Novolis OS package budget (single profile)"
echo "  explicit : $ALL_COUNT / $MAX_EXPLICIT"

if (( ALL_COUNT > MAX_EXPLICIT )); then
  echo "Explicit packages: $ALL_COUNT > budget $MAX_EXPLICIT" >&2
  FAIL=1
fi

for pkg in "${ALL_PKGS[@]}"; do
  if matches_exclude "$pkg"; then
    echo "Allowlist package '$pkg' matches hard exclude" >&2
    FAIL=1
  fi
done

if [[ -z "$RESOLVED" && -f "$REPO_ROOT/artifacts/resolved-packages.txt" ]]; then
  RESOLVED="$REPO_ROOT/artifacts/resolved-packages.txt"
fi

if [[ -n "$RESOLVED" && -f "$RESOLVED" ]]; then
  mapfile -t RESOLVED_PKGS < <(read_list "$RESOLVED")
  RESOLVED_COUNT="${#RESOLVED_PKGS[@]}"
  echo "  resolved : $RESOLVED_COUNT / $MAX_RESOLVED"
  if (( RESOLVED_COUNT > MAX_RESOLVED )); then
    echo "Resolved packages: $RESOLVED_COUNT > budget $MAX_RESOLVED" >&2
    FAIL=1
  fi
  for pkg in "${RESOLVED_PKGS[@]}"; do
    if matches_exclude "$pkg"; then
      echo "Resolved package '$pkg' matches hard exclude" >&2
      FAIL=1
    fi
  done
else
  echo "  resolved : (no artifacts/resolved-packages.txt yet)"
fi

if (( FAIL != 0 )); then
  echo "Package budget failed." >&2
  exit 1
fi

echo "OK — allowlists within budget and clear of hard excludes."
exit 0
