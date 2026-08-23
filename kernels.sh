#!/bin/bash
# Post-install script: adds the second kernel (linux 7.1.6) alongside the
# base-installed linux-lts 6.18.44, protects both from being clobbered by a
# future accidental system update, and sets up 4 GRUB entries (DIAGNOSTIC/
# CONTROL for each kernel) with manual selection enforced.
#
# Run this ON THE INSTALLED GUEST SYSTEM (as root), after install-arch-vm.sh
# has completed and you've booted into it — not from the archiso live env.
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────
LTS_ARCHIVE_DATE="2026/08/13"      # linux-lts 6.18.44-1 (verified against core.db, not just publish date + 1)
KERNEL_716_ARCHIVE_DATE="2026/08/07"  # linux 7.1.6.arch1-1 (verified against core.db; valid 08/07-08/10)

LTS_VMLINUZ_PINNED="/boot/vmlinuz-linux-lts-6.18.44-pinned"
LTS_INITRD_PINNED="/boot/initramfs-linux-lts-6.18.44-pinned.img"
K716_VMLINUZ_PINNED="/boot/vmlinuz-linux-7.1.6-pinned"
K716_INITRD_PINNED="/boot/initramfs-linux-7.1.6-pinned.img"

DIAG_PARAMS="ignore_loglevel nmi_watchdog=1 softlockup_panic=1 sysctl.kernel.hardlockup_panic=1 slub_debug=FZP slab_nomerge sysctl.kernel.panic_on_oops=1 sysctl.kernel.panic_print=1 crashkernel=512M sysctl.kernel.panic_on_warn=1 ftrace_dump_on_oops=1"
# ─────────────────────────────────────────────────────────────────────────

if [ "$EUID" -ne 0 ]; then
    echo "Run this as root." >&2
    exit 1
fi

ROOT_UUID=$(findmnt -no UUID /)
if [ -z "$ROOT_UUID" ]; then
    echo "Could not determine root filesystem UUID." >&2
    exit 1
fi
echo "Root filesystem UUID: $ROOT_UUID"

echo "=== Protecting the primary linux-lts kernel (currently installed) ==="
cp -v /boot/vmlinuz-linux-lts "$LTS_VMLINUZ_PINNED"
cp -v /boot/initramfs-linux-lts.img "$LTS_INITRD_PINNED"

echo "=== Installing second kernel: linux 7.1.6.arch1-1 (from $KERNEL_716_ARCHIVE_DATE archive) ==="
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak

echo "Server=https://archive.archlinux.org/repos/${KERNEL_716_ARCHIVE_DATE}/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist
pacman -Syy
pacman -S --noconfirm linux

echo "=== Protecting the second kernel's files ==="
cp -v /boot/vmlinuz-linux "$K716_VMLINUZ_PINNED"
cp -v /boot/initramfs-linux.img "$K716_INITRD_PINNED"

echo "=== Restoring mirrorlist to primary (LTS) archive date ==="
echo "Server=https://archive.archlinux.org/repos/${LTS_ARCHIVE_DATE}/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist
pacman -Syy

echo "=== Writing GRUB entries ==="
# Idempotent: strip any block from a previous run before appending a fresh one,
# so re-running this script doesn't duplicate menu entries.
sed -i '/# BEGIN vm-install kernels/,/# END vm-install kernels/d' /etc/grub.d/40_custom

cat >> /etc/grub.d/40_custom <<GRUBEOF
# BEGIN vm-install kernels

menuentry 'Arch Linux, linux-lts 6.18.44 (DIAGNOSTIC)' {
    load_video
    set gfxpayload=keep
    insmod gzio
    insmod part_msdos
    insmod ext2
    search --no-floppy --fs-uuid --set=root $ROOT_UUID
    linux $LTS_VMLINUZ_PINNED root=UUID=$ROOT_UUID rw $DIAG_PARAMS
    initrd $LTS_INITRD_PINNED
}

menuentry 'Arch Linux, linux-lts 6.18.44 (CONTROL)' {
    load_video
    set gfxpayload=keep
    insmod gzio
    insmod part_msdos
    insmod ext2
    search --no-floppy --fs-uuid --set=root $ROOT_UUID
    linux $LTS_VMLINUZ_PINNED root=UUID=$ROOT_UUID rw
    initrd $LTS_INITRD_PINNED
}

menuentry 'Arch Linux, linux 7.1.6 (DIAGNOSTIC)' {
    load_video
    set gfxpayload=keep
    insmod gzio
    insmod part_msdos
    insmod ext2
    search --no-floppy --fs-uuid --set=root $ROOT_UUID
    linux $K716_VMLINUZ_PINNED root=UUID=$ROOT_UUID rw $DIAG_PARAMS
    initrd $K716_INITRD_PINNED
}

menuentry 'Arch Linux, linux 7.1.6 (CONTROL)' {
    load_video
    set gfxpayload=keep
    insmod gzio
    insmod part_msdos
    insmod ext2
    search --no-floppy --fs-uuid --set=root $ROOT_UUID
    linux $K716_VMLINUZ_PINNED root=UUID=$ROOT_UUID rw
    initrd $K716_INITRD_PINNED
}
# END vm-install kernels
GRUBEOF

echo "=== Enforcing manual GRUB selection (no auto-boot timeout) ==="
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=-1/' /etc/default/grub

echo "=== Regenerating GRUB config ==="
grub-mkconfig -o /boot/grub/grub.cfg

echo "=== Done. Reboot to see the 4 new entries at the GRUB menu. ==="
echo "Pinned kernel files:"
echo "  $LTS_VMLINUZ_PINNED / $LTS_INITRD_PINNED"
echo "  $K716_VMLINUZ_PINNED / $K716_INITRD_PINNED"
