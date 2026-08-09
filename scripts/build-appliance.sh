#!/usr/bin/env bash
# Build Novolis OS GUI appliance: rootfs + qcow2 + kernel/initrd for QEMU -kernel boot.
# With BUILD_ISO=1 (default), also emit UEFI GPT hybrid novolis-os.iso / novolis-os-uefi.img.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${1:-$REPO_ROOT/profiles/default.yaml}"
DISK_GB="${DISK_GB:-8}"
BUILD_ISO="${BUILD_ISO:-1}"
ESP_MIB="${ESP_MIB:-512}"

for tool in mmdebstrap zstd tar curl qemu-img mkfs.ext4 mount umount; do
  command -v "$tool" >/dev/null || { echo "Required tool not on PATH: $tool" >&2; exit 1; }
done

if [[ "$BUILD_ISO" == "1" ]]; then
  for tool in sgdisk mkfs.vfat losetup; do
    command -v "$tool" >/dev/null || { echo "BUILD_ISO=1 requires tool on PATH: $tool" >&2; exit 1; }
  done
  if ! command -v kpartx >/dev/null && ! command -v partx >/dev/null; then
    echo "BUILD_ISO=1 requires kpartx or partx to map GPT partitions" >&2
    exit 1
  fi
fi

if ! command -v dotnet >/dev/null; then
  echo "dotnet SDK is required to publish GUI/console smokes." >&2
  exit 1
fi

OUT_ROOTFS="$REPO_ROOT/artifacts/novolis-os-rootfs.tar.zst"
OUT_QCOW="$REPO_ROOT/artifacts/novolis-os.qcow2"
OUT_UEFI_IMG="$REPO_ROOT/artifacts/novolis-os-uefi.img"
OUT_ISO="$REPO_ROOT/artifacts/novolis-os.iso"
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
# Skip device nodes — mknod fails in rootless/Podman extract; loop/mkfs does not need them.
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
UEFI hybrid: flash artifacts/novolis-os.iso (DD mode) — Secure Boot off.
EOF

# Export kernel/initrd for QEMU -kernel boot (no GRUB required).
VMLINUZ="$(ls "$ROOT"/boot/vmlinuz-* 2>/dev/null | sort | tail -n1 || true)"
INITRD="$(ls "$ROOT"/boot/initrd.img-* 2>/dev/null | sort | tail -n1 || true)"
if [[ -z "$VMLINUZ" || -z "$INITRD" ]]; then
  echo "Kernel/initrd missing under /boot — is linux-image-amd64 installed?" >&2
  ls -la "$ROOT/boot" >&2 || true
  exit 1
fi
KERNEL_BASENAME="$(basename "$VMLINUZ")"
INITRD_BASENAME="$(basename "$INITRD")"
cp -f "$VMLINUZ" "$BOOT_DIR/vmlinuz"
cp -f "$INITRD" "$BOOT_DIR/initrd.img"
printf '%s\n' "root=LABEL=novolisos rw rootfstype=ext4 console=tty0" >"$BOOT_DIR/cmdline.txt"
echo "Boot files: $BOOT_DIR/vmlinuz , $BOOT_DIR/initrd.img"

# Stable names on root for GRUB (also keep versioned files from the package).
cp -f "$VMLINUZ" "$ROOT/boot/vmlinuz"
cp -f "$INITRD" "$ROOT/boot/initrd.img"

write_grub_cfg() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
  sed -e "s/@@KERNEL@@/vmlinuz/g" -e "s/@@INITRD@@/initrd.img/g" \
    "$REPO_ROOT/appliance/grub/grub.cfg.in" >"$dest"
}

populate_ext4_image() {
  local raw="$1"
  local mnt="$2"
  mkdir -p "$mnt"
  mount -o loop "$raw" "$mnt"
  if command -v rsync >/dev/null; then
    rsync -aHAX --numeric-ids "$ROOT"/ "$mnt"/
  else
    cp -a "$ROOT"/. "$mnt"/
  fi
  sync
  umount "$mnt"
}

# --- qcow2 (QEMU kernel-direct) ---
RAW="$WORK/disk.raw"
rm -f "$RAW" "$OUT_QCOW"
echo "Creating ${DISK_GB}G ext4 image (LABEL=novolisos) via loop mount..."
qemu-img create -f raw "$RAW" "${DISK_GB}G"
mkfs.ext4 -F -L novolisos "$RAW"
populate_ext4_image "$RAW" "$WORK/mnt"
qemu-img convert -f raw -O qcow2 "$RAW" "$OUT_QCOW"
rm -f "$RAW"

echo "Appliance written: $OUT_QCOW"

# --- UEFI GPT hybrid (ESP + root) ---
if [[ "$BUILD_ISO" == "1" ]]; then
  echo "Creating UEFI GPT hybrid (${DISK_GB}G, ESP ${ESP_MIB}MiB)..."
  HYBRID="$WORK/hybrid.raw"
  rm -f "$HYBRID" "$OUT_UEFI_IMG" "$OUT_ISO"
  qemu-img create -f raw "$HYBRID" "${DISK_GB}G"
  sgdisk --clear \
    --new=1:0:+${ESP_MIB}M --typecode=1:EF00 --change-name=1:ESP \
    --new=2:0:0 --typecode=2:8300 --change-name=2:novolisos \
    "$HYBRID"

  LOOP="$(losetup -f --show "$HYBRID")"
  PART1=""
  PART2=""
  cleanup_hybrid() {
    set +e
    umount "$WORK/hybrid-mnt/boot/efi" 2>/dev/null
    umount "$WORK/hybrid-mnt/dev/pts" 2>/dev/null
    umount "$WORK/hybrid-mnt/dev" 2>/dev/null
    umount "$WORK/hybrid-mnt/proc" 2>/dev/null
    umount "$WORK/hybrid-mnt/sys" 2>/dev/null
    umount "$WORK/hybrid-mnt" 2>/dev/null
    if [[ -n "${LOOP:-}" ]]; then
      if command -v kpartx >/dev/null; then
        kpartx -d "$LOOP" 2>/dev/null
      fi
      partx -d "$LOOP" 2>/dev/null || true
      losetup -d "$LOOP" 2>/dev/null
    fi
  }
  trap cleanup_hybrid EXIT

  # Containers often lack losetup -P partition nodes — force partition maps.
  partx -u "$LOOP" 2>/dev/null || partx -a "$LOOP" 2>/dev/null || true
  if command -v kpartx >/dev/null; then
    kpartx -av "$LOOP" || true
  fi
  if command -v partprobe >/dev/null; then
    partprobe "$LOOP" 2>/dev/null || true
  fi

  for _ in $(seq 1 30); do
    if [[ -b "${LOOP}p1" && -b "${LOOP}p2" ]]; then
      PART1="${LOOP}p1"
      PART2="${LOOP}p2"
      break
    fi
    base="$(basename "$LOOP")"
    if [[ -b "/dev/mapper/${base}p1" && -b "/dev/mapper/${base}p2" ]]; then
      PART1="/dev/mapper/${base}p1"
      PART2="/dev/mapper/${base}p2"
      break
    fi
    sleep 0.2
  done
  if [[ -z "$PART1" || -z "$PART2" ]]; then
    echo "Partition devices missing for $LOOP" >&2
    ls -la "$LOOP"* /dev/mapper/"$(basename "$LOOP")"* 2>&1 || true
    exit 1
  fi
  echo "Using partitions: $PART1 $PART2"

  mkfs.vfat -F 32 -n NOVOLISEFI "$PART1"
  mkfs.ext4 -F -L novolisos "$PART2"

  MNT="$WORK/hybrid-mnt"
  mkdir -p "$MNT"
  mount "$PART2" "$MNT"
  mkdir -p "$MNT/boot/efi"
  mount "$PART1" "$MNT/boot/efi"

  if command -v rsync >/dev/null; then
    rsync -aHAX --numeric-ids "$ROOT"/ "$MNT"/
  else
    cp -a "$ROOT"/. "$MNT"/
  fi

  # Modules + grub.cfg live on ESP so removable UEFI finds its prefix.
  mkdir -p "$MNT/boot/efi/boot/grub" "$MNT/boot/grub"
  write_grub_cfg "$MNT/boot/efi/boot/grub/grub.cfg"
  cp -f "$MNT/boot/efi/boot/grub/grub.cfg" "$MNT/boot/grub/grub.cfg"

  mount --bind /dev "$MNT/dev"
  mount --bind /proc "$MNT/proc"
  mount --bind /sys "$MNT/sys"
  mount --bind /dev/pts "$MNT/dev/pts"

  if [[ ! -x "$MNT/usr/sbin/grub-install" && ! -x "$MNT/usr/bin/grub-install" ]]; then
    echo "grub-install missing in rootfs — add grub-efi-amd64 to manifests/appliance.txt" >&2
    exit 1
  fi

  chroot "$MNT" grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --boot-directory=/boot/efi/boot \
    --removable \
    --no-nvram \
    --recheck

  # Removable layout: ensure EFI/BOOT/BOOTX64.EFI exists
  if [[ ! -f "$MNT/boot/efi/EFI/BOOT/BOOTX64.EFI" ]]; then
    echo "EFI/BOOT/BOOTX64.EFI missing after grub-install" >&2
    find "$MNT/boot/efi" -type f >&2 || true
    exit 1
  fi

  # Keep our menu (grub-install may overwrite grub.cfg)
  write_grub_cfg "$MNT/boot/efi/boot/grub/grub.cfg"
  cp -f "$MNT/boot/efi/boot/grub/grub.cfg" "$MNT/boot/grub/grub.cfg"

  sync
  umount "$MNT/dev/pts"
  umount "$MNT/dev"
  umount "$MNT/proc"
  umount "$MNT/sys"
  umount "$MNT/boot/efi"
  umount "$MNT"
  if command -v kpartx >/dev/null; then
    kpartx -d "$LOOP" 2>/dev/null || true
  fi
  partx -d "$LOOP" 2>/dev/null || true
  losetup -d "$LOOP"
  LOOP=""
  trap - EXIT

  # Identical GPT hybrid under .img and .iso (Rufus/balena DD mode).
  cp -f "$HYBRID" "$OUT_UEFI_IMG"
  cp -f "$HYBRID" "$OUT_ISO"
  rm -f "$HYBRID"

  echo "UEFI hybrid written:"
  echo "  $OUT_UEFI_IMG"
  echo "  $OUT_ISO"
  echo "Kernel used by GRUB: $KERNEL_BASENAME / $INITRD_BASENAME (copied as /boot/vmlinuz + initrd.img)"
fi

echo "Run QEMU kernel-direct: pwsh -File $REPO_ROOT/scripts/Run-Qemu.ps1"
if [[ "$BUILD_ISO" == "1" ]]; then
  echo "Run QEMU OVMF ISO:     pwsh -File $REPO_ROOT/scripts/Run-Iso.ps1"
fi
