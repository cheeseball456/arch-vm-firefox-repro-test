#!/bin/bash
# Swaps the guest between nouveau/Mesa and the proprietary NVIDIA driver,
# for isolating whether the zink/nvk SIGBUS is driver-specific or not.
# Reversible — run again to switch back. Detects current state and acts
# accordingly.
#
# Run this ON THE INSTALLED GUEST SYSTEM (as root).
#
# NOTE: this is a deliberate one-off departure from the pinned package
# baseline in SYSTEM_BASELINE.md / packages.sh. Worth logging explicitly
# as a comparison run, not part of the pinned config.
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Run this as root." >&2
    exit 1
fi

CURRENT_KERNEL=$(uname -r)
echo "=== Currently running kernel: $CURRENT_KERNEL ==="

# Map running kernel to the matching headers package name.
case "$CURRENT_KERNEL" in
    *lts*) HEADERS_PKG="linux-lts-headers" ;;
    *)     HEADERS_PKG="linux-headers" ;;
esac
echo "=== Matching headers package: $HEADERS_PKG ==="

# Detect current state by checking which driver the GPU is actually bound to.
GPU_PCI=$(lspci -Dnn | grep -i 'VGA.*NVIDIA' | head -1 | awk '{print $1}')
if [ -z "$GPU_PCI" ]; then
    echo "Could not find an NVIDIA VGA device via lspci." >&2
    exit 1
fi
CURRENT_DRIVER=$(lspci -k -s "$GPU_PCI" | grep 'Kernel driver in use' | awk '{print $NF}')
echo "=== GPU ($GPU_PCI) currently bound to: ${CURRENT_DRIVER:-<none>} ==="

if [ "$CURRENT_DRIVER" = "nvidia" ]; then
    TARGET="nouveau"
elif [ "$CURRENT_DRIVER" = "nouveau" ]; then
    TARGET="nvidia"
else
    echo "Unexpected current driver state (${CURRENT_DRIVER:-<none>})." >&2
    echo "Pick a target manually: nouveau or nvidia" >&2
    read -r -p "Target driver [nouveau/nvidia]: " TARGET < /dev/tty
fi

echo "=== Proceeding: $CURRENT_DRIVER -> $TARGET ==="
read -r -p "Press Enter to continue, or Ctrl+C to abort." < /dev/tty

if [ "$TARGET" = "nvidia" ]; then
    echo "=== Blacklisting nouveau (modprobe.d) ==="
    echo "blacklist nouveau" > /etc/modprobe.d/blacklist-nouveau-guest.conf

    # The autodetect hook bakes 'nouveau' into the initramfs for early KMS,
    # so modprobe.d alone is too late — it fires after the initramfs has already
    # loaded the module. MODULES_BLACKLIST prevents it from being included at all.
    echo "=== Blacklisting nouveau from initramfs (MODULES_BLACKLIST in mkinitcpio.conf) ==="
    if grep -q '^MODULES_BLACKLIST=' /etc/mkinitcpio.conf; then
        if ! grep -q 'nouveau' /etc/mkinitcpio.conf; then
            sed -i 's/^MODULES_BLACKLIST=(\(.*\))/MODULES_BLACKLIST=(\1 nouveau)/' /etc/mkinitcpio.conf
        fi
    else
        echo 'MODULES_BLACKLIST=(nouveau)' >> /etc/mkinitcpio.conf
    fi

    echo "=== Verifying headers match running kernel (must be installed by kernels.sh) ==="
    KERNEL_PKG="${HEADERS_PKG%-headers}"  # linux-headers → linux, linux-lts-headers → linux-lts
    HEADERS_VER=$(pacman -Q "$HEADERS_PKG" 2>/dev/null | awk '{print $2}')
    KERNEL_VER=$(pacman -Q "$KERNEL_PKG" 2>/dev/null | awk '{print $2}')
    if [ -z "$HEADERS_VER" ] || [ "$HEADERS_VER" != "$KERNEL_VER" ]; then
        echo "ERROR: $HEADERS_PKG ($HEADERS_VER) does not match $KERNEL_PKG ($KERNEL_VER)." >&2
        echo "Install matching headers from the correct archive date (see kernels.sh) then re-run." >&2
        exit 1
    fi
    echo "Headers OK: $HEADERS_PKG $HEADERS_VER"

    echo "=== Installing proprietary driver (from currently-pinned mirrorlist) ==="
    pacman -S --noconfirm nvidia-dkms nvidia-utils

    echo "=== Enabling early KMS modeset (needed for correct Wayland behaviour) ==="
    echo "options nvidia-drm modeset=1" > /etc/modprobe.d/nvidia-modeset.conf

else
    echo "=== Removing nouveau guest-side blacklist (if present) ==="
    rm -f /etc/modprobe.d/blacklist-nouveau-guest.conf

    echo "=== Removing nouveau from initramfs MODULES_BLACKLIST ==="
    # Remove the word 'nouveau' from the MODULES_BLACKLIST line regardless of position.
    sed -i '/^MODULES_BLACKLIST=/ s/\bnouveau\b//' /etc/mkinitcpio.conf
    # Clean up any leading or trailing space left inside the parens.
    sed -i 's/^MODULES_BLACKLIST=(  */MODULES_BLACKLIST=(/' /etc/mkinitcpio.conf
    sed -i 's/^MODULES_BLACKLIST=(\(.*[^ ]\)  *)/MODULES_BLACKLIST=(\1)/' /etc/mkinitcpio.conf

    echo "=== Removing proprietary driver ==="
    pacman -Rns --noconfirm nvidia-dkms nvidia-utils || true
    rm -f /etc/modprobe.d/nvidia-modeset.conf
fi

echo "=== Regenerating initramfs (mkinitcpio -P) ==="
mkinitcpio -P

# GRUB loads the pinned initramfs files, not the standard ones that mkinitcpio
# writes by default. Copy the freshly generated files to the pinned locations so
# the MODULES_BLACKLIST change (or its removal) is actually seen at boot.
echo "=== Updating pinned initramfs files ==="
[ -f /boot/initramfs-linux.img ]     && cp -v /boot/initramfs-linux.img     /boot/initramfs-linux-7.1.6-pinned.img
[ -f /boot/initramfs-linux-lts.img ] && cp -v /boot/initramfs-linux-lts.img /boot/initramfs-linux-lts-6.18.44-pinned.img

echo "=== Removing non-pinned and fallback initramfs to free ESP space ==="
rm -f /boot/initramfs-linux.img          /boot/initramfs-linux-fallback.img \
      /boot/initramfs-linux-lts.img      /boot/initramfs-linux-lts-fallback.img

if [ "$TARGET" = "nvidia" ]; then
    echo "=== Verifying DKMS build ==="
    DKMS_STATUS=$(dkms status 2>/dev/null)
    if echo "$DKMS_STATUS" | grep -qi "nvidia.*installed"; then
        echo "DKMS: OK — nvidia module built for $CURRENT_KERNEL."
    else
        echo "WARNING: dkms status does not show nvidia as installed:"
        echo "${DKMS_STATUS:-<blank>}"
        echo ""
        echo "This almost certainly means $HEADERS_PKG does not match the running kernel ($CURRENT_KERNEL)."
        echo "The proprietary driver WILL NOT load after reboot until this is fixed."
        echo ""
        echo "Fix: install the headers that match $CURRENT_KERNEL from the correct archive date, then:"
        echo "  dkms autoinstall"
        echo ""
        echo "Aborting to prevent a broken reboot. Fix headers and re-run, or reboot into nouveau."
        exit 1
    fi
fi

echo "=== Done. Reboot required for the driver change to take effect. ==="
echo "After reboot, verify with:"
echo "  lspci -k -s $GPU_PCI          # should show 'Kernel driver in use: $TARGET'"
if [ "$TARGET" = "nvidia" ]; then
    echo "  nvidia-smi                    # should show the RTX 2060"
fi
