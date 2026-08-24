#!/bin/bash
# Automated Arch Linux install for GPU-passthrough testing VMs.
# Run this from an Arch Linux ISO's live environment, after networking is up.
#
# Usage: curl -O https://raw.githubusercontent.com/<you>/<repo>/main/install-arch-vm.sh
#        bash install-arch-vm.sh
set -euo pipefail

# ── Configuration — adjust these ────────────────────────────────────────
DISK="/dev/sda"
ARCHIVE_DATE="2026/08/13"          # archive.archlinux.org snapshot date
                                    # Verified against core.db (not just publish date + 1 —
                                    # the archive's snapshot generation lags real package
                                    # publish time by several days, confirmed empirically).
                                    # 2026/08/13 is the first snapshot containing
                                    # linux-lts 6.18.44-1, matching SYSTEM_BASELINE.md.
HOSTNAME="gpu-test-vm"
TIMEZONE="Europe/London"
LOCALE="en_GB.UTF-8"
BASE_PACKAGES="base linux-lts linux-firmware vim base-devel networkmanager grub sudo openssh git"
GPU_PACKAGES="mesa vulkan-nouveau vulkan-icd-loader xf86-video-nouveau xorg-xwayland plasma-desktop kwin sddm firefox"
# ─────────────────────────────────────────────────────────────────────────

# ── Boot mode: auto-detect from how the live ISO booted, confirm with user ──
if [ -d /sys/firmware/efi/efivars ]; then
    DETECTED_MODE="UEFI"; DEFAULT_ANSWER="n"
else
    DETECTED_MODE="Legacy BIOS"; DEFAULT_ANSWER="y"
fi

echo "=== Detected boot mode: $DETECTED_MODE (based on how this ISO session booted) ==="
read -r -p "Install using Legacy BIOS/MBR instead? [y/N, default follows detected mode] " BIOS_MODE_ANSWER < /dev/tty
BIOS_MODE_ANSWER="${BIOS_MODE_ANSWER:-$DEFAULT_ANSWER}"

if [[ "$BIOS_MODE_ANSWER" =~ ^[Yy]$ ]]; then
    BIOS_MODE=true
else
    BIOS_MODE=false
fi
echo "=== Proceeding with BIOS_MODE=$BIOS_MODE ==="
if ! $BIOS_MODE; then
    BASE_PACKAGES="$BASE_PACKAGES efibootmgr"
fi
echo "=== About to WIPE $DISK and install Arch Linux (archive snapshot: $ARCHIVE_DATE) ==="
echo "Press Enter to continue, or Ctrl+C to abort."
read -r < /dev/tty

MIRROR_URL="https://archive.archlinux.org/repos/${ARCHIVE_DATE}/\$repo/os/\$arch"

echo "=== Setting live-environment mirrorlist ==="
echo "Server=$MIRROR_URL" > /etc/pacman.d/mirrorlist
sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf

echo "=== Partitioning $DISK ==="
if $BIOS_MODE; then
    parted -s "$DISK" mklabel msdos
    parted -s "$DISK" mkpart primary ext4 1MiB 100%
    parted -s "$DISK" set 1 boot on
    ROOT_PART="${DISK}1"
    mkfs.ext4 -F "$ROOT_PART"
    mount "$ROOT_PART" /mnt
else
    parted -s "$DISK" mklabel gpt
    parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
    parted -s "$DISK" set 1 esp on
    parted -s "$DISK" mkpart primary ext4 513MiB 100%
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
    mkfs.fat -F32 "$EFI_PART"
    mkfs.ext4 -F "$ROOT_PART"
    mount "$ROOT_PART" /mnt
    mount --mkdir "$EFI_PART" /mnt/boot
fi

echo "=== pacstrap (this takes a while) ==="
pacstrap -K /mnt $BASE_PACKAGES

echo "=== fstab ==="
genfstab -U /mnt >> /mnt/etc/fstab

echo "=== Propagating mirrorlist + relaxed sig checking into new system ==="
echo "Server=$MIRROR_URL" > /mnt/etc/pacman.d/mirrorlist
sed -i 's/^SigLevel.*/SigLevel = Never/' /mnt/etc/pacman.conf

echo "=== Configuring new system ==="
arch-chroot /mnt /bin/bash -c "
set -e
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# locale.gen has been observed empty/truncated on some archive snapshots —
# don't assume the package's template content is present; write it directly.
if ! grep -q '^${LOCALE}' /etc/locale.gen 2>/dev/null; then
    echo '${LOCALE} UTF-8' >> /etc/locale.gen
fi
locale-gen
echo 'LANG=${LOCALE}' > /etc/locale.conf

echo '$HOSTNAME' > /etc/hostname

systemctl enable NetworkManager
systemctl enable sshd
"

if $BIOS_MODE; then
    arch-chroot /mnt grub-install --target=i386-pc "$DISK"
else
    arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
fi
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

echo "=== Set the root password (not scripted — do this interactively) ==="
arch-chroot /mnt passwd

echo "=== Create a non-root user (needed to log in via SDDM — it blocks root login by default) ==="
read -r -p "Enter username for the new user account: " NEW_USERNAME < /dev/tty
arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$NEW_USERNAME"
echo "Set password for $NEW_USERNAME:"
arch-chroot /mnt passwd "$NEW_USERNAME"
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /mnt/etc/sudoers

read -r -p "Install the GPU/Mesa/desktop package set now too? [y/N] " ans < /dev/tty
if [[ "$ans" =~ ^[Yy]$ ]]; then
    arch-chroot /mnt pacman -S --noconfirm $GPU_PACKAGES
    arch-chroot /mnt systemctl enable sddm
fi

echo "=== Done. Unmount and reboot when ready: ==="
echo "  umount -R /mnt && reboot"
