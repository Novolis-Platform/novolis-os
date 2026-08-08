#!/usr/bin/env bash
# Build Novolis OS rootfs with mmdebstrap (Linux). Used by CI and Podman builder.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${1:-$REPO_ROOT/profiles/rootfs.yaml}"
OUTPUT="${2:-}"

bash "$REPO_ROOT/scripts/verify-package-budget.sh"

yaml_scalar() {
  local key="$1" file="$2"
  sed -e 's/\r$//' "$file" | awk -v k="$key" '
    $0 ~ "^[[:space:]]*"k":[[:space:]]*" {
      sub("^[[:space:]]*"k":[[:space:]]*", "", $0)
      gsub(/^["'\'']|["'\'']$/, "", $0)
      print $0
      exit
    }'
}

yaml_list() {
  local key="$1" file="$2"
  sed -e 's/\r$//' "$file" | awk -v k="$key" '
    $0 ~ "^[[:space:]]*"k":[[:space:]]*$" { inlist=1; next }
    inlist && /^[^[:space:]-]/ { exit }
    inlist && /^[[:space:]]*-[[:space:]]+/ {
      sub(/^[[:space:]]*-[[:space:]]+/, "", $0)
      gsub(/^["'\'']|["'\'']$/, "", $0)
      print $0
    }'
}

read_list() {
  local f="$1"
  sed -e 's/\r$//' -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$f" | sed '/^$/d'
}

SUITE="$(yaml_scalar suite "$PROFILE")"
VARIANT="$(yaml_scalar variant "$PROFILE")"
SUITE="${SUITE:-trixie}"
VARIANT="${VARIANT:-minbase}"

mapfile -t MANIFESTS < <(yaml_list manifests "$PROFILE")
if ((${#MANIFESTS[@]} == 0)); then
  echo "No manifests listed in $PROFILE" >&2
  exit 1
fi

mapfile -t PACKAGES < <(
  for f in "${MANIFESTS[@]}"; do
    read_list "$REPO_ROOT/manifests/$f"
  done | sort -u
)

APT_PACKAGES=()
WANT_DOTNET=0
for p in "${PACKAGES[@]}"; do
  if [[ "$p" == "dotnet-runtime-10.0" ]]; then
    WANT_DOTNET=1
  else
    APT_PACKAGES+=("$p")
  fi
done

if [[ -z "$OUTPUT" ]]; then
  ROOTFS_OUT="$(yaml_scalar rootfs_output "$PROFILE")"
  OUT="$(yaml_scalar output "$PROFILE")"
  if [[ -n "$ROOTFS_OUT" ]]; then
    OUTPUT="$REPO_ROOT/$ROOTFS_OUT"
  elif [[ "$OUT" == *.tar.zst ]]; then
    OUTPUT="$REPO_ROOT/$OUT"
  else
    OUTPUT="$REPO_ROOT/artifacts/novolis-os-rootfs.tar.zst"
  fi
fi

ARTIFACTS_DIR="$(dirname "$OUTPUT")"
mkdir -p "$ARTIFACTS_DIR"

for tool in mmdebstrap zstd tar curl; do
  command -v "$tool" >/dev/null || { echo "Required tool not on PATH: $tool" >&2; exit 1; }
done

KEYRING="/usr/share/keyrings/debian-archive-keyring.gpg"
[[ -f "$KEYRING" ]] || { echo "Missing $KEYRING — install debian-archive-keyring." >&2; exit 1; }

WORK="$ARTIFACTS_DIR/rootfs-work"
rm -rf "$WORK"
mkdir -p "$WORK/hooks"

SETUP_DOTNET="$WORK/hooks/setup-dotnet.sh"
if (( WANT_DOTNET == 1 )); then
  cat >"$SETUP_DOTNET" <<'EOF'
#!/bin/sh
set -eu
root="$1"
install_sh="/tmp/novolis-dotnet-install.sh"
curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$install_sh"
bash "$install_sh" --channel 10.0 --runtime dotnet --install-dir "$root/usr/share/dotnet"
ln -sfn /usr/share/dotnet/dotnet "$root/usr/bin/dotnet"
chroot "$root" /usr/bin/dotnet --list-runtimes | grep -E 'Microsoft\.NETCore\.App 10\.'
rm -f "$install_sh"
EOF
else
  printf '#!/bin/sh\nexit 0\n' >"$SETUP_DOTNET"
fi
chmod +x "$SETUP_DOTNET"

TAR_TMP="$WORK/rootfs.tar"
echo "mmdebstrap suite=$SUITE variant=$VARIANT packages=${#APT_PACKAGES[@]} (+dotnet hook=$WANT_DOTNET)"

MM=(mmdebstrap
  "--variant=$VARIANT"
  --mode=root
  "--keyring=$KEYRING"
  --aptopt='Apt::Install-Recommends "false"'
)
for p in "${APT_PACKAGES[@]}"; do
  MM+=("--include=$p")
done
if (( WANT_DOTNET == 1 )); then
  MM+=("--customize-hook=$SETUP_DOTNET")
fi
MM+=("$SUITE" "$TAR_TMP")

UID_NUM="$(id -u)"
if [[ "$UID_NUM" != "0" ]]; then
  sudo "${MM[@]}"
  sudo chown -R "${UID_NUM}:${UID_NUM}" "$WORK"
else
  "${MM[@]}"
fi

STATUS="$WORK/dpkg-status"
tar -xOf "$TAR_TMP" ./var/lib/dpkg/status >"$STATUS"
RESOLVED="$ARTIFACTS_DIR/resolved-packages.txt"
awk '/^Package:/{print $2}' "$STATUS" | sort -u >"$RESOLVED"
echo "Wrote $(wc -l <"$RESOLVED") resolved packages -> $RESOLVED"
bash "$REPO_ROOT/scripts/verify-package-budget.sh" "$RESOLVED"

rm -f "$OUTPUT"
zstd -T0 -19 -o "$OUTPUT" "$TAR_TMP"
echo "Rootfs written: $OUTPUT"
