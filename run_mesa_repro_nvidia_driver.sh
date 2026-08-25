#!/bin/bash
# Runs the EXISTING, unmodified mesa_repro binary through the proprietary
# NVIDIA driver explicitly, via GLVND vendor selection — rather than relying
# on EGL_DEFAULT_DISPLAY's implicit vendor resolution, which is ambiguous
# once both the Mesa and NVIDIA EGL/GLX vendor ICDs are registered.
#
# No source changes / no rebuild needed — mesa_repro.c calls only generic
# EGL/GL entry points and links against libglvnd's dispatch libraries, not
# Mesa directly. Which driver actually runs it is decided at runtime by
# these variables, not by anything in the C source.
#
# Prerequisite: driver-swap.sh has been run (target: nvidia) and the system
# has been rebooted since.
set -euo pipefail

NVIDIA_EGL_VENDOR="/usr/share/glvnd/egl_vendor.d/10_nvidia.json"
if [ ! -f "$NVIDIA_EGL_VENDOR" ]; then
    echo "NVIDIA EGL vendor file not found at $NVIDIA_EGL_VENDOR" >&2
    echo "Is nvidia-utils installed, and has the system been rebooted since driver-swap.sh?" >&2
    exit 1
fi

if [ ! -x ./mesa_repro ]; then
    echo "./mesa_repro not found or not executable — build it first with build-mesa-repro.sh" >&2
    exit 1
fi

# Explicitly unset — this is a Mesa-only variable; leaving it set would be
# meaningless (and potentially confusing) once forcing the NVIDIA vendor.
unset MESA_LOADER_DRIVER_OVERRIDE

# NVIDIA's EGL implementation needs a live Wayland or X11 connection —
# it does not go through DRM directly the way Mesa does. If the variables
# are already set (running from a desktop session), this block is a no-op.
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; then
    # Try to find a live Wayland socket owned by any logged-in user.
    WAYLAND_SOCK=$(find /run/user -name 'wayland-[0-9]*' 2>/dev/null | head -1)
    if [ -n "$WAYLAND_SOCK" ]; then
        export XDG_RUNTIME_DIR=$(dirname "$WAYLAND_SOCK")
        export WAYLAND_DISPLAY=$(basename "$WAYLAND_SOCK")
        echo "Auto-detected Wayland display: $WAYLAND_DISPLAY (XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR)"
    elif [ -S /tmp/.X11-unix/X0 ]; then
        export DISPLAY=:0
        echo "Auto-detected X11 display: $DISPLAY"
    else
        echo "ERROR: No Wayland or X11 display found." >&2
        echo "Run this script from a terminal inside the Plasma/desktop session, not over SSH or a bare TTY." >&2
        exit 1
    fi
fi

echo "=== Letting GLVND select the NVIDIA vendor automatically ==="
echo "=== (10_nvidia.json has higher priority than 50_mesa.json — GLVND picks it) ==="
echo "=== Verify GL_VENDOR/GL_RENDERER in the output below actually show NVIDIA ==="
echo "=== before treating any crash/no-crash result as meaningful.            ==="
echo

# __EGL_VENDOR_LIBRARY_FILENAMES is intentionally NOT set here — it bypasses
# GLVND's Wayland/X11 platform negotiation and calls NVIDIA's eglGetDisplay
# directly, which fails on EGL_DEFAULT_DISPLAY. Let GLVND handle the platform
# detection; the NVIDIA ICD wins by priority when nvidia-utils is installed.
unset __EGL_VENDOR_LIBRARY_FILENAMES
__GLX_VENDOR_LIBRARY_NAME="nvidia" \
./mesa_repro
