#!/bin/bash
# Builds the standalone headless EGL/OpenGL repro (mesa_repro.c) — no
# browser, no window system, just the one glTexImage2D call that crashes
# the zink/nvk driver.
#
# Usage: curl -O https://raw.githubusercontent.com/cheeseball456/arch-vm-firefox-repro-test/main/build-mesa-repro.sh
#        bash build-mesa-repro.sh
set -euo pipefail

if [ ! -f mesa_repro.c ]; then
    echo "mesa_repro.c not found in the current directory — download it first:" >&2
    echo "  curl -O https://raw.githubusercontent.com/cheeseball456/arch-vm-firefox-repro-test/main/mesa_repro.c" >&2
    exit 1
fi

echo "=== Ensuring build tools and EGL/GL headers are present ==="
sudo pacman -S --needed --noconfirm base-devel mesa libglvnd

echo "=== Building ==="
gcc -o mesa_repro mesa_repro.c -lEGL -lGL

echo "=== Done. Run with: ==="
echo "  MESA_LOADER_DRIVER_OVERRIDE=zink ./mesa_repro"
echo ""
echo "WARNING: this reproduces the same driver crash as crash.html. On native"
echo "Wayland it has escalated to a full, unrecoverable system freeze in this"
echo "investigation — save your work first."
