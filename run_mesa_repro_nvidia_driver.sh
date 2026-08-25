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

echo "=== Forcing GLVND vendor: nvidia ==="
echo "=== Verify GL_VENDOR/GL_RENDERER in the output below actually show NVIDIA ==="
echo "=== before treating any crash/no-crash result as meaningful.            ==="
echo

__EGL_VENDOR_LIBRARY_FILENAMES="$NVIDIA_EGL_VENDOR" \
__GLX_VENDOR_LIBRARY_NAME="nvidia" \
./mesa_repro
