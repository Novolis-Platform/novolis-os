#!/usr/bin/env bash
# Build Novolis OS GUI appliance: rootfs + qcow2 + kernel/initrd for QEMU -kernel boot.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${1:-$REPO_ROOT/profiles/appliance.yaml}"
DISK_GB="${DISK_GB:-8}"

for tool in mmdebstrap zstd tar curl qemu-img mkfs.ext4 mount umount; do
  command -v "$tool" >/dev/null || { echo "Required tool not on PATH: $tool" >&2; exit 1; }
done

if ! command -v dotnet >/dev/null; then
  echo "dotnet SDK is required to publish GUI/console smokes." >&2
  exit 1
fi

OUT_ROOTFS="$REPO_ROOT/artifacts/novolis-os-appliance-rootfs.tar.zst"
OUT_QCOW="$REPO_ROOT/artifacts/novolis-os.qcow2"
BOOT_DIR="$REPO_ROOT/artifacts/boot"
WORK="$REPO_ROOT/artifacts/appliance-work"

if [[ "${SKIP_ROOTFS:-}" == "1" && -f "$OUT_ROOTFS" ]]; then
  echo "SKIP_ROOTFS=1 — reusing $OUT_ROOTFS"
else
  bash "$REPO_ROOT/scripts/build-rootfs.sh" "$PROFILE" "$OUT_ROOTFS"
fi

rm -rf "$WORK"
mkdir -p "$WORK/root" "$BOOT_DIR" "$WORK/publish-console" "$WORK/publish-gui"

echo "Publishing HelloNovolisOs (console)..."
dotnet publish "$REPO_ROOT/smokes/HelloNovolisOs/HelloNovolisOs.csproj" \
  -c Release -r linux-x64 --self-contained false /p:UseAppHost=false \
  -o "$WORK/publish-console"

echo "Publishing HelloNovolisOsGui (Avalonia)..."
dotnet publish "$REPO_ROOT/smokes/HelloNovolisOsGui/HelloNovolisOsGui.csproj" \
  -c Release -r linux-x64 --self-contained false /p:UseAppHost=false /p:DebugType=None \
  -o "$WORK/publish-gui"

echo "Unpacking appliance rootfs..."
# Skip device nodes — mknod fails in rootless/Podman extract; virt-make-fs does not need them.
zstd -d -c "$OUT_ROOTFS" | tar -xf - -C "$WORK/root" \
  --exclude='./dev' --exclude='./proc' --exclude='./sys'
mkdir -p "$WORK/root/dev" "$WORK/root/proc" "$WORK/root/sys"

ROOT="$WORK/root"
mkdir -p "$ROOT/opt/novolis/hello" "$ROOT/opt/novolis/hello-gui" \
  "$ROOT/etc/systemd/system" "$ROOT/etc/systemd/system/graphical.target.wants" \
  "$ROOT/etc/systemd/system/multi-user.target.wants"

cp -a "$WORK/publish-console/." "$ROOT/opt/novolis/hello/"
cp -a "$WORK/publish-gui/." "$ROOT/opt/novolis/hello-gui/"
# Drop symbols if any slipped through
rm -f "$ROOT/opt/novolis/hello"/*.pdb "$ROOT/opt/novolis/hello-gui"/*.pdb

cp "$REPO_ROOT/appliance/systemd/novolis-gui.service" \
  "$ROOT/etc/systemd/system/novolis-gui.service"

# Enable seatd + GUI; default to graphical.target
if [[ -f "$ROOT/lib/systemd/system/seatd.service" ]]; then
  ln -sfn /lib/systemd/system/seatd.service \
    "$ROOT/etc/systemd/system/multi-user.target.wants/seatd.service"
fi
ln -sfn /etc/systemd/system/novolis-gui.service \
  "$ROOT/etc/systemd/system/graphical.target.wants/novolis-gui.service"
ln -sfn /lib/systemd/system/graphical.target "$ROOT/etc/systemd/system/default.target"

cat >"$ROOT/etc/motd" <<'EOF'
Novolis OS (GUI appliance)
--------------------------
Boots to cage + HelloNovolisOsGui (Avalonia).
QEMU: use artifacts/boot/vmlinuz + initrd with root=LABEL=novolisos
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
