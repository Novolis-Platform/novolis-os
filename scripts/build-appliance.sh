#!/usr/bin/env bash
# Build Novolis OS GUI appliance: rootfs + qcow2 + kernel/initrd for QEMU -kernel boot.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${1:-$REPO_ROOT/profiles/default.yaml}"
DISK_GB="${DISK_GB:-8}"

for tool in mmdebstrap zstd tar curl qemu-img mkfs.ext4 mount umount; do
  command -v "$tool" >/dev/null || { echo "Required tool not on PATH: $tool" >&2; exit 1; }
done

if ! command -v dotnet >/dev/null; then
  echo "dotnet SDK is required to publish GUI/console smokes." >&2
  exit 1
fi

OUT_ROOTFS="$REPO_ROOT/artifacts/novolis-os-rootfs.tar.zst"
OUT_QCOW="$REPO_ROOT/artifacts/novolis-os.qcow2"
BOOT_DIR="$REPO_ROOT/artifacts/boot"
WORK="$REPO_ROOT/artifacts/appliance-work"

if [[ "${SKIP_ROOTFS:-}" == "1" && -f "$OUT_ROOTFS" ]]; then
  echo "SKIP_ROOTFS=1 — reusing $OUT_ROOTFS"
else
  bash "$REPO_ROOT/scripts/build-rootfs.sh" "$PROFILE" "$OUT_ROOTFS"
fi

rm -rf "$WORK"
mkdir -p "$WORK/root" "$BOOT_DIR" "$WORK/publish-console" "$WORK/publish-app"

echo "Publishing HelloNovolisOs (console)..."
dotnet publish "$REPO_ROOT/smokes/HelloNovolisOs/HelloNovolisOs.csproj" \
  -c Release -r linux-x64 --self-contained false /p:UseAppHost=false \
  -o "$WORK/publish-console"

# Prefer a pre-published novolis-apps payload (host publish into artifacts/app-publish).
APP_PUBLISH="${APP_PUBLISH_DIR:-$REPO_ROOT/artifacts/app-publish}"
if [[ -d "$APP_PUBLISH" && -n "$(ls -A "$APP_PUBLISH" 2>/dev/null || true)" ]]; then
  echo "Installing pre-published app from $APP_PUBLISH"
  cp -a "$APP_PUBLISH"/. "$WORK/publish-app/"
else
  echo "No artifacts/app-publish — falling back to HelloNovolisOsGui smoke."
  dotnet publish "$REPO_ROOT/smokes/HelloNovolisOsGui/HelloNovolisOsGui.csproj" \
    -c Release -r linux-x64 --self-contained false /p:UseAppHost=false /p:DebugType=None \
    -o "$WORK/publish-app"
fi

# Detect primary entry DLL (prefer known product names, else first non-Avalonia host dll).
APP_DLL=""
for candidate in GeoPolity.dll CapitalistSimulator.dll CoverageStudio.dll BooksWriterStudio.dll \
  SketchStudio.dll DraftStudio.dll HelloNovolisOsGui.dll; do
  if [[ -f "$WORK/publish-app/$candidate" ]]; then
    APP_DLL="$candidate"
    break
  fi
done
if [[ -z "$APP_DLL" ]]; then
  APP_DLL="$(find "$WORK/publish-app" -maxdepth 1 -name '*.dll' ! -name 'Avalonia*' ! -name 'Microsoft*' ! -name 'System*' | head -n1 | xargs -r basename)"
fi
if [[ -z "$APP_DLL" ]]; then
  echo "No app DLL found under publish-app." >&2
  ls -la "$WORK/publish-app" >&2 || true
  exit 1
fi
echo "GUI entry: /opt/novolis/app/$APP_DLL"

echo "Unpacking appliance rootfs..."
# Skip device nodes — mknod fails in rootless/Podman extract; virt-make-fs does not need them.
zstd -d -c "$OUT_ROOTFS" | tar -xf - -C "$WORK/root" \
  --exclude='./dev' --exclude='./proc' --exclude='./sys'
mkdir -p "$WORK/root/dev" "$WORK/root/proc" "$WORK/root/sys"

ROOT="$WORK/root"
mkdir -p "$ROOT/opt/novolis/hello" "$ROOT/opt/novolis/app" \
  "$ROOT/etc/systemd/system" "$ROOT/etc/systemd/system/graphical.target.wants" \
  "$ROOT/etc/systemd/system/multi-user.target.wants"

cp -a "$WORK/publish-console/." "$ROOT/opt/novolis/hello/"
cp -a "$WORK/publish-app/." "$ROOT/opt/novolis/app/"
# Drop symbols if any slipped through
rm -f "$ROOT/opt/novolis/hello"/*.pdb "$ROOT/opt/novolis/app"/*.pdb

cp "$REPO_ROOT/appliance/systemd/novolis-gui.service" \
  "$ROOT/etc/systemd/system/novolis-gui.service"
cp "$REPO_ROOT/appliance/systemd/novolis-app-9p.service" \
  "$ROOT/etc/systemd/system/novolis-app-9p.service"

# Enable seatd + GUI; default to graphical.target
if [[ -f "$ROOT/lib/systemd/system/seatd.service" ]]; then
  ln -sfn /lib/systemd/system/seatd.service \
    "$ROOT/etc/systemd/system/multi-user.target.wants/seatd.service"
fi
ln -sfn /etc/systemd/system/novolis-gui.service \
  "$ROOT/etc/systemd/system/graphical.target.wants/novolis-gui.service"
ln -sfn /etc/systemd/system/novolis-app-9p.service \
  "$ROOT/etc/systemd/system/graphical.target.wants/novolis-app-9p.service"
ln -sfn /lib/systemd/system/graphical.target "$ROOT/etc/systemd/system/default.target"

cat >"$ROOT/etc/motd" <<EOF
Novolis OS (GUI appliance)
--------------------------
Boots to cage + $APP_DLL under /opt/novolis/app.
QEMU 9p: Run-Qemu.ps1 mounts artifacts/app-publish when present.
EOF

# Export kernel/initrd for QEMU -kernel boot (no GRUB required).
VMLINUZ="$(ls "$ROOT"/boot/vmlinuz-* 2>/dev/null | sort | tail -n1 || true)"
INITRD="$(ls "$ROOT"/boot/initrd.img-* 2>/dev/null | sort | tail -n1 || true)"
if [[ -z "$VMLINUZ" || -z "$INITRD" ]]; then
  echo "Kernel/initrd missing under /boot — is linux-image-amd64 installed?" >&2
  ls -la "$ROOT/boot" >&2 || true
  exit 1
fi
cp -f "$VMLINUZ" "$BOOT_DIR/vmlinuz"
cp -f "$INITRD" "$BOOT_DIR/initrd.img"
printf '%s\n' "root=LABEL=novolisos rw rootfstype=ext4 console=tty0" >"$BOOT_DIR/cmdline.txt"
echo "Boot files: $BOOT_DIR/vmlinuz , $BOOT_DIR/initrd.img"

RAW="$WORK/disk.raw"
rm -f "$RAW" "$OUT_QCOW"
echo "Creating ${DISK_GB}G ext4 image (LABEL=novolisos) via loop mount..."
qemu-img create -f raw "$RAW" "${DISK_GB}G"
mkfs.ext4 -F -L novolisos "$RAW"
MNT="$WORK/mnt"
mkdir -p "$MNT"
mount -o loop "$RAW" "$MNT"
# Prefer rsync if available; fall back to cp -a
if command -v rsync >/dev/null; then
  rsync -aHAX --numeric-ids "$ROOT"/ "$MNT"/
else
  cp -a "$ROOT"/. "$MNT"/
fi
sync
umount "$MNT"
qemu-img convert -f raw -O qcow2 "$RAW" "$OUT_QCOW"
rm -f "$RAW"

# Optional VHDX for Hyper-V (still needs a bootloader for Gen1/Gen2 — kernel-direct is QEMU-only).
if qemu-img convert -f qcow2 -O vhdx "$OUT_QCOW" "$REPO_ROOT/artifacts/novolis-os.vhdx" 2>/dev/null; then
  echo "Also wrote artifacts/novolis-os.vhdx (disk only — Hyper-V bootloader not wired yet)."
fi

echo "Appliance written: $OUT_QCOW"
echo "Run: pwsh -File $REPO_ROOT/scripts/Run-Qemu.ps1"
