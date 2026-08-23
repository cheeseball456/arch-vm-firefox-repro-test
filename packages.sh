#!/bin/bash
# Pins the entire package stack (Mesa/GPU drivers, desktop, Firefox, and
# everything else version-sensitive) to the single archive date that matches
# every one of them exactly — see SYSTEM_BASELINE.md for how this date was
# verified against the real machine's pacman.log history.
#
# Run this ON THE INSTALLED GUEST SYSTEM (as root), after install-arch-vm.sh
# and (if used) add-kernels-and-grub.sh have completed.
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────
PACKAGE_ARCHIVE_DATE="2026/08/14"  # covers mesa/vulkan-nouveau/vulkan-icd-loader/
                                    # xf86-video-nouveau/glibc/systemd/firefox/kwin/
                                    # plasma-desktop/plasma-workspace/wayland/xorg-xwayland
                                    # — verified against real-machine pacman.log, see
                                    # SYSTEM_BASELINE.md

GPU_PACKAGES="mesa vulkan-nouveau vulkan-icd-loader xf86-video-nouveau xorg-xwayland plasma-desktop kwin plasma-workspace sddm firefox konsole"
# ─────────────────────────────────────────────────────────────────────────

if [ "$EUID" -ne 0 ]; then
    echo "Run this as root." >&2
    exit 1
fi

echo "=== Pinning mirrorlist to $PACKAGE_ARCHIVE_DATE ==="
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
echo "Server=https://archive.archlinux.org/repos/${PACKAGE_ARCHIVE_DATE}/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist

# -Syy (not -Sy) — plain -Sy can skip re-downloading the sync db if the local
# cache looks "fresh enough" by timestamp, which silently keeps serving a
# stale db when jumping between archived dates. See SYSTEM_BASELINE.md.
echo "=== Syncing against pinned archive (forced refresh) ==="
pacman -Syy

# NEVER use a blanket `pacman -Su` here. A full system upgrade against this
# mirrorlist would also see the pinned `linux` (7.1.6) package as "outdated"
# relative to 08/14's repo state (linux moves fast — 7.1.6 was only current
# 08/07-08/10) and silently upgrade it, deleting the currently-running
# kernel's /usr/lib/modules/ directory out from under it. Confirmed this
# happen: it broke networking entirely (NIC driver module files gone) on a
# test run. --ignore is defense in depth on top of only ever naming specific
# packages below, never the kernel packages.
KERNEL_IGNORE="--ignore linux --ignore linux-lts --ignore linux-firmware --ignore linux-headers --ignore linux-lts-headers"

echo "=== Upgrading specific already-installed base packages to match this date ==="
echo "(catches glibc/systemd etc., which were installed from a different pinned"
echo " date during the base install and may not yet match $PACKAGE_ARCHIVE_DATE —"
echo " named explicitly, never a blanket -Su, and kernel packages are excluded)"
pacman -S --noconfirm $KERNEL_IGNORE glibc systemd

echo "=== Installing GPU/desktop/Firefox package set ==="
pacman -S --noconfirm $KERNEL_IGNORE $GPU_PACKAGES

echo "=== Enabling display manager ==="
systemctl enable sddm

echo "=== Verifying versions against expected baseline ==="
EXPECTED="mesa 1:26.1.7-1
vulkan-nouveau 1:26.1.7-1
vulkan-icd-loader 1.4.357.0-1
xf86-video-nouveau 1.0.18-1
glibc 2.44+r24+g16be1518495f-1
systemd 261.2-1
firefox 153.0.4-1
kwin 6.7.4-5
plasma-desktop 6.7.4-1
plasma-workspace 6.7.4-1
wayland 1.26.0-1
xorg-xwayland 24.1.13-1"

MISMATCH=0
while read -r pkg expected_ver; do
    actual_ver=$(pacman -Q "$pkg" 2>/dev/null | awk '{print $2}')
    if [ "$actual_ver" != "$expected_ver" ]; then
        echo "MISMATCH: $pkg expected $expected_ver, got ${actual_ver:-<not installed>}"
        MISMATCH=1
    fi
done <<< "$EXPECTED"

if [ "$MISMATCH" -eq 0 ]; then
    echo "All package versions match the baseline exactly."
else
    echo "One or more versions did not match — check output above before proceeding."
fi

echo "=== Mirrorlist left pinned at $PACKAGE_ARCHIVE_DATE (not restored) — this is now the primary date for this system ==="
echo "=== Done. Reboot to use the new desktop/display manager. ==="
