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

echo "=== Checking build tools and EGL/GL libraries are already present ==="
echo "(not installing them here — they should already be pinned/installed by"
echo " install.sh and packages.sh; installing them fresh here could silently"
echo " pull a different, unpinned version depending on the current mirrorlist)"
MISSING=""
# gcc (not the "base-devel" group name — that's a group, not a queryable
# package) and libglvnd (provides the actual EGL/GL libraries we link
# against, pulled in as a dependency of mesa/vulkan-icd-loader).
for pkg in gcc mesa libglvnd; do
    pacman -Q "$pkg" > /dev/null 2>&1 || MISSING="$MISSING $pkg"
done
if [ -n "$MISSING" ]; then
    echo "Missing:$MISSING — run install.sh and packages.sh first, in order, before building this." >&2
    exit 1
fi

echo "=== Building ==="
gcc -o mesa_repro mesa_repro.c -lEGL -lGL

echo "=== Done. Run with: ==="
echo "  MESA_LOADER_DRIVER_OVERRIDE=zink ./mesa_repro"
echo ""
echo "WARNING: this reproduces the same driver crash as crash.html. On native"
echo "Wayland it has escalated to a full, unrecoverable system freeze in this"
echo "investigation — save your work first."
