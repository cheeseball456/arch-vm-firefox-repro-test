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
    echo "=== Blacklisting nouveau (guest-side) ==="
    echo "blacklist nouveau" > /etc/modprobe.d/blacklist-nouveau-guest.conf

    echo "=== Installing headers + proprietary driver (from currently-pinned mirrorlist) ==="
    pacman -S --noconfirm "$HEADERS_PKG" nvidia-dkms nvidia-utils

    echo "=== Enabling early KMS modeset (needed for correct Wayland behaviour) ==="
    echo "options nvidia-drm modeset=1" > /etc/modprobe.d/nvidia-modeset.conf

else
    echo "=== Removing nouveau guest-side blacklist (if present) ==="
    rm -f /etc/modprobe.d/blacklist-nouveau-guest.conf

    echo "=== Removing proprietary driver ==="
    pacman -Rns --noconfirm nvidia-dkms nvidia-utils || true
    rm -f /etc/modprobe.d/nvidia-modeset.conf
fi

echo "=== Regenerating initramfs (mkinitcpio -P) ==="
mkinitcpio -P

echo "=== Done. Reboot required for the driver change to take effect. ==="
echo "After reboot, verify with:"
echo "  lspci -k -s $GPU_PCI          # should show 'Kernel driver in use: $TARGET'"
if [ "$TARGET" = "nvidia" ]; then
    echo "  nvidia-smi                    # should show the RTX 2060"
fi
